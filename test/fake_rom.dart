// A simulated ROM bootloader with an in-memory flash chip, following
// Espressif's serial protocol description.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/flasher/flash_port.dart';

class FakeRom implements FlashPort {
  FakeRom({this.inBootloader = false, this.flashSize = 16 << 20}) : flash = Uint8List(flashSize)..fillRange(0, flashSize, 0x5A);

  final int flashSize;
  final Uint8List flash;
  bool inBootloader;
  bool attached = false;
  int paramsSize = 0;
  bool dtr = false, rts = false;
  bool resetToApp = false;
  bool _inReset = false, _bootRequested = false;
  final regs = <int, int>{0x40001000: 0x9, 0x3FCEF14C: 4, 0x600080B4: 0};

  /// JEDEC ID the flash chip answers with (Winbond, 2^0x18 = 16 MB).
  int jedec = 0x1840EF;

  /// Hardware around the chip: sees register writes, may answer reads.
  void Function(int addr, int value)? onWriteReg;
  int? Function(int addr)? onReadReg;
  final writes = <int>[];
  final _out = <int>[];
  final _in = <int>[];
  int _beginOffset = 0, _blocks = 0, _blockSize = 0;

  /// Models the USB-Serial/JTAG line logic: RTS without DTR holds the chip in
  /// reset, DTR without RTS requests download mode for the next boot.
  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    this.dtr = dtr ?? this.dtr;
    this.rts = rts ?? this.rts;
    if (this.dtr && !this.rts) _bootRequested = true;
    final reset = this.rts && !this.dtr;
    if (_inReset && !reset) {
      inBootloader = _bootRequested;
      resetToApp = !_bootRequested;
      _bootRequested = false;
      if (inBootloader) _out.addAll('ESP-ROM:esp32s3-20210327\r\nwaiting for download\r\n'.codeUnits);
    }
    _inReset = reset;
  }

  @override
  Future<void> setBaud(int baud) async {}

  @override
  Future<void> flushInput() async => _out.clear();

  @override
  Future<void> close() async {}

  @override
  Future<Uint8List> read(Duration timeout) async {
    if (_out.isEmpty) await Future.delayed(const Duration(milliseconds: 1));
    final r = Uint8List.fromList(_out);
    _out.clear();
    return r;
  }

  @override
  Future<void> write(Uint8List data) async {
    for (final b in data) {
      _in.add(b);
      if (b == 0xC0 && _in.length > 1) {
        _handle(_unslip(_in.sublist(1, _in.length - 1)));
        _in.clear();
      } else if (b == 0xC0) {
        _in
          ..clear()
          ..add(b);
      }
    }
  }

  List<int> _unslip(List<int> f) {
    final out = <int>[];
    for (var i = 0; i < f.length; i++) {
      if (f[i] == 0xDB) {
        out.add(f[++i] == 0xDC ? 0xC0 : 0xDB);
      } else {
        out.add(f[i]);
      }
    }
    return out;
  }

  int _u32(List<int> d, int o) => d[o] | d[o + 1] << 8 | d[o + 2] << 16 | d[o + 3] << 24;

  void _reply(int cmd, {int value = 0, List<int> body = const [], int status = 0}) {
    final data = [...body, status, 0, 0, 0];
    final pkt = [0x01, cmd, data.length & 0xFF, data.length >> 8, value & 0xFF, value >> 8 & 0xFF, value >> 16 & 0xFF, value >> 24 & 0xFF, ...data];
    _out.add(0xC0);
    for (final b in pkt) {
      if (b == 0xC0) {
        _out.addAll([0xDB, 0xDC]);
      } else if (b == 0xDB) {
        _out.addAll([0xDB, 0xDD]);
      } else {
        _out.add(b);
      }
    }
    _out.add(0xC0);
  }

  void _handle(List<int> p) {
    if (!inBootloader || p.length < 8 || p[0] != 0) return;
    final cmd = p[1];
    final size = p[2] | p[3] << 8;
    final checksum = _u32(p, 4);
    final d = p.sublist(8, 8 + size);
    switch (cmd) {
      case 0x08:
        for (var i = 0; i < 8; i++) {
          _reply(cmd);
        }
      case 0x0A:
        final addr = _u32(d, 0);
        _reply(cmd, value: onReadReg?.call(addr) ?? regs[addr] ?? 0);
      case 0x09:
        final addr = _u32(d, 0), value = _u32(d, 4);
        regs[addr] = value;
        // SPI flash user command (RDID): the S3's SPI1 at 0x60002000, the ESP32's at 0x3FF42000.
        if ((addr == 0x60002000 || addr == 0x3FF42000) && value & (1 << 18) != 0) {
          regs[addr] = 0;
          regs[addr + (addr == 0x60002000 ? 0x58 : 0x80)] = jedec;
        }
        onWriteReg?.call(addr, value);
        _reply(cmd);
      case 0x0D:
        attached = d.length == 8;
        _reply(cmd);
      case 0x0B:
        paramsSize = _u32(d, 4);
        _reply(cmd);
      case 0x0F:
        _reply(cmd);
      case 0x02:
        expect(attached, isTrue, reason: 'flash used before SPI attach');
        expect(d.length, regs[0x40001000] == 0x9 ? 20 : 16, reason: 'only newer ROMs take the encryption flag');
        final eraseSize = _u32(d, 0);
        _blocks = _u32(d, 4);
        _blockSize = _u32(d, 8);
        _beginOffset = _u32(d, 12);
        flash.fillRange(_beginOffset, _beginOffset + eraseSize, 0xFF);
        writes.add(_beginOffset);
        _reply(cmd);
      case 0x03:
        final len = _u32(d, 0), seq = _u32(d, 4);
        final block = d.sublist(16);
        var sum = 0xEF;
        for (final b in block) {
          sum ^= b;
        }
        if (sum != checksum || len != _blockSize || seq >= _blocks) {
          _reply(cmd, status: 1);
          return;
        }
        flash.setRange(_beginOffset + seq * _blockSize, _beginOffset + seq * _blockSize + len, block);
        _reply(cmd);
      case 0x13:
        final addr = _u32(d, 0), len = _u32(d, 4);
        _reply(cmd, body: md5.convert(flash.sublist(addr, addr + len)).toString().codeUnits);
      default:
        _reply(cmd, status: 1);
    }
  }
}

class FakeUsb implements UsbBackend {
  FakeUsb(this.rom, {this.port = const UsbPortInfo(id: 'COM6', label: 'USB JTAG/serial debug unit', vid: 0x303A, pid: 0x1001)});
  final FakeRom rom;
  final UsbPortInfo port;
  @override
  Future<List<UsbPortInfo>> list() async => [port];
  @override
  Future<FlashPort> open(UsbPortInfo port, {int baud = 115200}) async => rom;
}
