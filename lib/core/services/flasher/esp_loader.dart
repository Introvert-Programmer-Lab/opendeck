// Client for the ESP32 and ESP32-S3 ROM serial bootloader, the protocol esptool speaks.
// Only what a full firmware write needs: sync, attach flash, write, verify, reset.
// Reference: https://docs.espressif.com/projects/esptool/en/latest/esp32s3/advanced-topics/serial-protocol.html
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'flash_port.dart';

class FlashException implements Exception {
  FlashException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A run of bytes written to flash at [offset].
class FlashSegment {
  const FlashSegment(this.offset, this.data);
  final int offset;
  final Uint8List data;
}

/// Splits a merged image (as written from offset 0) into the parts worth
/// writing. Blank (0xFF) gaps shorter than [keepGap] are written as is, so
/// small regions like NVS get wiped. Longer gaps are skipped: they are the
/// unused tail of the app or filesystem partition, which nothing reads.
List<FlashSegment> splitImage(Uint8List image, {int sector = 0x1000, int keepGap = 0x20000}) {
  final sectors = (image.length + sector - 1) ~/ sector;
  bool blank(int s) {
    final end = (s + 1) * sector < image.length ? (s + 1) * sector : image.length;
    for (var i = s * sector; i < end; i++) {
      if (image[i] != 0xFF) return false;
    }
    return true;
  }

  final used = [for (var s = 0; s < sectors; s++) !blank(s)];
  final out = <FlashSegment>[];
  var s = 0;
  while (s < sectors) {
    if (!used[s]) {
      s++;
      continue;
    }
    final start = s;
    var end = s + 1;
    while (true) {
      while (end < sectors && used[end]) {
        end++;
      }
      var gap = end;
      while (gap < sectors && !used[gap]) {
        gap++;
      }
      if (gap < sectors && (gap - end) * sector < keepGap) {
        end = gap;
      } else {
        break;
      }
    }
    final from = start * sector;
    final to = end * sector < image.length ? end * sector : image.length;
    out.add(FlashSegment(from, Uint8List.sublistView(image, from, to)));
    s = end;
  }
  return out;
}

enum ChipFamily { esp32, esp32s3 }

/// Register access on the chip, as the ROM loader offers it.
abstract class ChipRegisters {
  Future<int> readReg(int addr);
  Future<void> writeReg(int addr, int value);
}

class EspLoader implements ChipRegisters {
  EspLoader(this.port, {this.usbJtag = false});

  final FlashPort port;

  /// True when talking to the chip's built-in USB-Serial/JTAG (no UART bridge).
  bool usbJtag;

  /// Set by [connect].
  ChipFamily chip = ChipFamily.esp32s3;

  static const _sync = 0x08;
  static const _flashBegin = 0x02;
  static const _flashData = 0x03;
  static const _writeReg = 0x09;
  static const _readReg = 0x0A;
  static const _spiSetParams = 0x0B;
  static const _spiAttach = 0x0D;
  static const _changeBaud = 0x0F;
  static const _spiFlashMd5 = 0x13;

  static const _blockSize = 0x400;
  static const _statusLen = 4; // the ROM loader ends every reply with 4 status bytes
  static const _chipMagicReg = 0x40001000;
  static const _esp32s3Magic = 0x9;
  static const _esp32Magic = 0x00F01D83;

  // ESP32-S3 registers used to stop the watchdogs during a USB-Serial/JTAG session.
  static const _rtcCntl = 0x60008000;
  static const _wdtConfig0 = _rtcCntl + 0x98;
  static const _wdtProtect = _rtcCntl + 0xB0;
  static const _wdtKey = 0x50D83AA1;
  static const _swdConf = _rtcCntl + 0xB4;
  static const _swdProtect = _rtcCntl + 0xB8;
  static const _swdKey = 0x8F1D312A;
  static const _swdAutoFeed = 1 << 31;
  static const _uartDevBufNo = 0x3FCEF14C;
  static const _bufNoUsbJtag = 4;
  // Set by firmware that restarts into the bootloader; must be cleared or the
  // chip comes back in download mode after the reset.
  static const _rtcOption1 = 0x6000812C;
  static const _forceDownloadBoot = 0x1;

  final _frames = <Uint8List>[];
  final _frame = <int>[];
  bool _inFrame = false;
  bool _escape = false;
  bool _dtr = false;

  Future<void> _setDtr(bool v) async {
    _dtr = v;
    await port.setSignals(dtr: v);
  }

  Future<void> _setRts(bool v) async {
    await port.setSignals(rts: v);
    // usbser.sys on Windows only sends the line state when DTR is written.
    await port.setSignals(dtr: _dtr);
  }

  /// Reset into the ROM bootloader through the USB-Serial/JTAG control lines.
  Future<void> resetUsbJtag() async {
    await _setRts(false);
    await _setDtr(false);
    await _sleep(100);
    await _setDtr(true);
    await _setRts(false);
    await _sleep(100);
    await _setRts(true);
    await _setDtr(false);
    await _setRts(true);
    await _sleep(100);
    await _setDtr(false);
    await _setRts(false);
  }

  /// Reset into the ROM bootloader on boards with a USB-UART bridge (EN on RTS, IO0 on DTR).
  Future<void> resetClassic() async {
    await _setDtr(false);
    await _setRts(true);
    await _sleep(100);
    await _setDtr(true);
    await _setRts(false);
    await _sleep(50);
    await _setDtr(false);
  }

  /// Leave the bootloader and start the new firmware.
  Future<void> hardReset() async {
    if (chip == ChipFamily.esp32s3) {
      try {
        await writeReg(_rtcOption1, 0, mask: _forceDownloadBoot);
      } on Object {
        // Best effort: the reset below still works when the flag was not set.
      }
    }
    await _setDtr(false);
    await _setRts(true);
    await _sleep(usbJtag ? 200 : 100);
    await _setRts(false);
    await _sleep(200);
  }

  void _feed(Uint8List bytes) {
    for (final b in bytes) {
      if (b == 0xC0) {
        if (_inFrame && _frame.isNotEmpty) _frames.add(Uint8List.fromList(_frame));
        _frame.clear();
        _inFrame = true;
        _escape = false;
      } else if (_inFrame) {
        if (_escape) {
          _frame.add(b == 0xDC ? 0xC0 : (b == 0xDD ? 0xDB : b));
          _escape = false;
        } else if (b == 0xDB) {
          _escape = true;
        } else {
          _frame.add(b);
        }
      }
    }
  }

  Future<void> _write(int cmd, List<int> data, {int checksum = 0}) async {
    final pkt = BytesBuilder(copy: false)
      ..addByte(0x00)
      ..addByte(cmd)
      ..add(_u16(data.length))
      ..add(_u32(checksum))
      ..add(data);
    final out = BytesBuilder(copy: false)..addByte(0xC0);
    for (final b in pkt.takeBytes()) {
      if (b == 0xC0) {
        out.add(const [0xDB, 0xDC]);
      } else if (b == 0xDB) {
        out.add(const [0xDB, 0xDD]);
      } else {
        out.addByte(b);
      }
    }
    out.addByte(0xC0);
    await port.write(out.takeBytes());
  }

  /// Waits for the reply to [cmd]. Returns (value, data without status bytes).
  Future<(int, Uint8List)> _reply(int cmd, Duration timeout) async {
    final until = DateTime.now().add(timeout);
    while (true) {
      while (_frames.isNotEmpty) {
        final f = _frames.removeAt(0);
        if (f.length < 8 || f[0] != 0x01 || f[1] != cmd) continue;
        final size = f[2] | (f[3] << 8);
        final value = ByteData.sublistView(f, 4, 8).getUint32(0, Endian.little);
        final data = Uint8List.sublistView(f, 8, 8 + size > f.length ? f.length : 8 + size);
        if (data.length >= _statusLen && data[data.length - _statusLen] != 0) {
          throw FlashException(
              'The bootloader rejected command 0x${cmd.toRadixString(16)} (error 0x${data[data.length - _statusLen + 1].toRadixString(16)})');
        }
        final body = data.length > _statusLen ? Uint8List.sublistView(data, 0, data.length - _statusLen) : Uint8List(0);
        return (value, body);
      }
      final left = until.difference(DateTime.now());
      if (left.isNegative) throw TimeoutException('No reply to command 0x${cmd.toRadixString(16)}');
      final chunk = await port.read(left < const Duration(milliseconds: 50) ? left : const Duration(milliseconds: 50));
      if (chunk.isNotEmpty) _feed(chunk);
    }
  }

  Future<(int, Uint8List)> command(int cmd, List<int> data,
      {int checksum = 0, Duration timeout = const Duration(seconds: 3)}) async {
    await _write(cmd, data, checksum: checksum);
    return _reply(cmd, timeout);
  }

  Future<void> _drain(Duration d) async {
    final until = DateTime.now().add(d);
    while (DateTime.now().isBefore(until)) {
      await port.read(const Duration(milliseconds: 20));
    }
    _frames.clear();
    _frame.clear();
    _inFrame = false;
  }

  /// Tries to sync with the ROM loader. Returns false if it does not answer.
  Future<bool> sync({int attempts = 5}) async {
    await port.flushInput();
    final payload = [0x07, 0x07, 0x12, 0x20, ...List.filled(32, 0x55)];
    for (var i = 0; i < attempts; i++) {
      try {
        await command(_sync, payload, timeout: const Duration(milliseconds: 150));
        // The ROM answers a sync several times; drop the extra replies.
        await _drain(const Duration(milliseconds: 150));
        return true;
      } on TimeoutException {
        continue;
      } on FlashException {
        continue;
      }
    }
    return false;
  }

  @override
  Future<int> readReg(int addr) async => (await command(_readReg, _u32(addr))).$1;

  @override
  Future<void> writeReg(int addr, int value, {int mask = 0xFFFFFFFF}) =>
      command(_writeReg, [..._u32(addr), ..._u32(value), ..._u32(mask), ..._u32(0)]);

  /// Identifies the chip, stops watchdogs and enables flash access. Call after
  /// [sync]. Throws for chips OpenDeck does not support.
  Future<void> connect() async {
    final magic = await readReg(_chipMagicReg);
    if (magic == _esp32s3Magic) {
      chip = ChipFamily.esp32s3;
    } else if (magic == _esp32Magic) {
      chip = ChipFamily.esp32;
    } else {
      throw FlashException('Unsupported chip (id 0x${magic.toRadixString(16)}). OpenDeck runs on ESP32 and ESP32-S3.');
    }
    usbJtag = chip == ChipFamily.esp32s3 && (await readReg(_uartDevBufNo)) == _bufNoUsbJtag;
    if (usbJtag) {
      await writeReg(_wdtProtect, _wdtKey);
      await writeReg(_wdtConfig0, 0);
      await writeReg(_wdtProtect, 0);
      await writeReg(_swdProtect, _swdKey);
      await writeReg(_swdConf, (await readReg(_swdConf)) | _swdAutoFeed);
      await writeReg(_swdProtect, 0);
    }
    await command(_spiAttach, List.filled(8, 0));
  }

  /// Size of the flash chip in bytes, from its JEDEC ID. 0 when unreadable.
  Future<int> flashSize() async {
    final id = await _spiFlashCommand(0x9F, 24);
    final capacity = (id >> 16) & 0xFF;
    return capacity >= 0x12 && capacity <= 0x1A ? 1 << capacity : 0;
  }

  /// Runs a flash command through the SPI peripheral's user mode (as esptool
  /// does) and returns up to 32 bits read back.
  Future<int> _spiFlashCommand(int cmd, int readBits) async {
    final base = chip == ChipFamily.esp32 ? 0x3FF42000 : 0x60002000;
    final usr = base + (chip == ChipFamily.esp32 ? 0x1C : 0x18);
    final usr2 = base + (chip == ChipFamily.esp32 ? 0x24 : 0x20);
    final misoDlen = base + (chip == ChipFamily.esp32 ? 0x2C : 0x28);
    final w0 = base + (chip == ChipFamily.esp32 ? 0x80 : 0x58);
    final oldUsr = await readReg(usr);
    final oldUsr2 = await readReg(usr2);
    await writeReg(misoDlen, readBits - 1);
    await writeReg(usr, (1 << 31) | (1 << 28)); // command + MISO phases
    await writeReg(usr2, (7 << 28) | cmd);
    await writeReg(w0, 0);
    await writeReg(base, 1 << 18); // start
    for (var i = 0; i < 10 && ((await readReg(base)) & (1 << 18)) != 0; i++) {}
    final value = await readReg(w0);
    await writeReg(usr, oldUsr);
    await writeReg(usr2, oldUsr2);
    return value;
  }

  /// Tells the ROM how big the flash is. Call after [connect].
  Future<void> setFlashSize(int bytes) async {
    await command(_spiSetParams, [
      ..._u32(0),
      ..._u32(bytes),
      ..._u32(64 * 1024),
      ..._u32(4 * 1024),
      ..._u32(256),
      ..._u32(0xFFFF),
    ]);
  }

  /// Speeds up UART bridges. The USB-Serial/JTAG link ignores baud rates.
  Future<void> changeBaud(int baud) async {
    if (usbJtag) return;
    await command(_changeBaud, [..._u32(baud), ..._u32(0)]);
    await port.setBaud(baud);
    await _drain(const Duration(milliseconds: 50));
  }

  /// Erases and writes one segment. [onBlock] gets the bytes written so far.
  Future<void> writeSegment(FlashSegment seg, {void Function(int written)? onBlock}) async {
    final blocks = (seg.data.length + _blockSize - 1) ~/ _blockSize;
    final eraseTimeout = _perMb(30, seg.data.length);
    await command(
        _flashBegin,
        [
          ..._u32(seg.data.length), ..._u32(blocks), ..._u32(_blockSize), ..._u32(seg.offset),
          // Newer ROMs take an "encrypted" flag; the ESP32's does not.
          if (chip != ChipFamily.esp32) ..._u32(0),
        ],
        timeout: eraseTimeout);
    for (var seq = 0; seq < blocks; seq++) {
      final from = seq * _blockSize;
      final to = from + _blockSize < seg.data.length ? from + _blockSize : seg.data.length;
      final block = Uint8List(_blockSize)..fillRange(0, _blockSize, 0xFF);
      block.setRange(0, to - from, seg.data, from);
      var checksum = 0xEF;
      for (final b in block) {
        checksum ^= b;
      }
      final payload = [..._u32(_blockSize), ..._u32(seq), ..._u32(0), ..._u32(0), ...block];
      for (var attempt = 0;; attempt++) {
        try {
          await command(_flashData, payload, checksum: checksum, timeout: const Duration(seconds: 5));
          break;
        } on Object {
          if (attempt >= 2) rethrow;
          await _drain(const Duration(milliseconds: 100));
        }
      }
      onBlock?.call(to);
    }
  }

  /// Compares the flash contents with [seg] using the ROM's MD5 command.
  Future<void> verifySegment(FlashSegment seg) async {
    final (_, body) = await command(_spiFlashMd5, [..._u32(seg.offset), ..._u32(seg.data.length), ..._u32(0), ..._u32(0)],
        timeout: _perMb(8, seg.data.length));
    final got = body.length == 32
        ? String.fromCharCodes(body).toLowerCase()
        : body.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final want = md5.convert(seg.data).toString();
    if (got != want) {
      throw FlashException('Verification failed at 0x${seg.offset.toRadixString(16)}. Try again with another cable.');
    }
  }
}

Duration _perMb(int seconds, int size) {
  final ms = (seconds * 1000 * size / 1e6).round();
  return Duration(milliseconds: ms < 3000 ? 3000 : ms);
}

Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v & 0xFFFFFFFF, Endian.little);
