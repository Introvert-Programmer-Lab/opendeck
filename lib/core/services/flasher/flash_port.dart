import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../win_ports.dart';
import 'flash_log.dart';
import 'win_serial.dart';

/// A USB serial port the flasher can use.
class UsbPortInfo {
  const UsbPortInfo({required this.id, required this.label, required this.vid, required this.pid});
  final String id;
  final String label;
  final int vid, pid;

  static const espressif = 0x303A;

  bool get isEspressif => vid == espressif;

  /// The chip's built-in USB-Serial/JTAG (also used by the ROM bootloader).
  bool get isUsbJtag => vid == espressif && pid == 0x1001;

  /// The OpenDeck firmware's own USB port.
  bool get isOpenDeck => vid == espressif && pid == 0x4004;

  @override
  String toString() => label.isEmpty ? id : '$id ($label)';
}

/// Raw byte access to a serial port, with the control lines the bootloader reset uses.
abstract class FlashPort {
  Future<void> setSignals({bool? dtr, bool? rts});
  Future<void> setBaud(int baud);
  Future<void> write(Uint8List data);

  /// Returns what arrived within [timeout], possibly nothing.
  Future<Uint8List> read(Duration timeout);
  Future<void> flushInput();
  Future<void> close();
}

abstract class UsbBackend {
  Future<List<UsbPortInfo>> list();
  Future<FlashPort> open(UsbPortInfo port, {int baud = 115200});
}

/// Windows, macOS and Linux. Calls block, so run it off the UI isolate.
class DesktopUsbBackend implements UsbBackend {
  @override
  Future<List<UsbPortInfo>> list() async {
    final out = <UsbPortInfo>[];
    FlashLog.line('list: enumerating ports');
    if (Platform.isWindows) {
      for (final p in listWinPorts()) {
        FlashLog.line('list: ${p.name} vid=0x${p.vid.toRadixString(16)} pid=0x${p.pid.toRadixString(16)} "${p.description}"');
        out.add(UsbPortInfo(id: p.name, label: p.description, vid: p.vid, pid: p.pid));
      }
      return out;
    }
    final names = SerialPort.availablePorts;
    FlashLog.line('list: ${names.length} ports: ${names.join(', ')}');
    for (final name in names) {
      FlashLog.line('list: $name details');
      final p = SerialPort(name);
      var vid = 0, pid = 0;
      var label = '';
      try {
        vid = p.vendorId ?? 0;
        pid = p.productId ?? 0;
        label = p.description ?? '';
      } catch (_) {
        // Ports without USB details (built-in UARTs, Bluetooth) stay listed with zeros.
      } finally {
        p.dispose();
      }
      FlashLog.line('list: $name vid=0x${vid.toRadixString(16)} pid=0x${pid.toRadixString(16)} "$label"');
      out.add(UsbPortInfo(id: name, label: label, vid: vid, pid: pid));
    }
    return out;
  }

  @override
  Future<FlashPort> open(UsbPortInfo port, {int baud = 115200}) async {
    FlashLog.line('open: ${port.id} at $baud');
    final p = Platform.isWindows ? WinSerialPort.open(port.id, baud) : _LibSerialFlashPort.open(port.id, baud);
    FlashLog.line('open: ${port.id} ok');
    return p;
  }
}

class _LibSerialFlashPort implements FlashPort {
  _LibSerialFlashPort(this._port);
  final SerialPort _port;
  bool _dtr = false, _rts = false;
  int _baud = 115200;

  static _LibSerialFlashPort open(String name, int baud) {
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      final msg = SerialPort.lastError?.message;
      port.dispose();
      throw PortBusyException(name, msg);
    }
    final p = _LibSerialFlashPort(port).._baud = baud;
    p._apply();
    return p;
  }

  void _apply() {
    final cfg = SerialPortConfig()
      ..baudRate = _baud
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    cfg
      ..dtr = _dtr ? SerialPortDtr.on : SerialPortDtr.off
      ..rts = _rts ? SerialPortRts.on : SerialPortRts.off;
    _port.config = cfg;
    cfg.dispose();
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    _dtr = dtr ?? _dtr;
    _rts = rts ?? _rts;
    _apply();
  }

  @override
  Future<void> setBaud(int baud) async {
    _baud = baud;
    _apply();
  }

  @override
  Future<void> write(Uint8List data) async {
    var off = 0;
    while (off < data.length) {
      final n = _port.write(Uint8List.sublistView(data, off), timeout: 2000);
      if (n <= 0) throw const SocketException('USB write failed');
      off += n;
    }
  }

  @override
  Future<Uint8List> read(Duration timeout) async {
    final first = _port.read(1, timeout: timeout.inMilliseconds);
    if (first.isEmpty) return first;
    final more = _port.bytesAvailable;
    if (more <= 0) return first;
    return Uint8List.fromList([...first, ..._port.read(more, timeout: 0)]);
  }

  @override
  Future<void> flushInput() async => _port.flush(SerialPortBuffer.input);

  @override
  Future<void> close() async {
    try {
      _port.close();
    } finally {
      _port.dispose();
    }
  }
}

/// Android USB host, through the CDC-ACM driver in UsbSerialChannel.kt.
class AndroidUsbBackend implements UsbBackend {
  static const _methods = MethodChannel('opendeck/usb');
  static const _events = EventChannel('opendeck/usb/data');

  @override
  Future<List<UsbPortInfo>> list() async {
    final rows = await _methods.invokeListMethod<Map>('list') ?? const [];
    return [
      for (final r in rows)
        UsbPortInfo(id: '${r['id']}', label: '${r['name'] ?? ''}', vid: r['vid'] as int, pid: r['pid'] as int),
    ];
  }

  @override
  Future<FlashPort> open(UsbPortInfo port, {int baud = 115200}) async {
    try {
      await _methods.invokeMethod('open', {'id': port.id, 'baud': baud});
    } on PlatformException catch (e) {
      throw PortBusyException(port.id, e.message);
    }
    return _AndroidFlashPort(_methods, _events.receiveBroadcastStream());
  }
}

class _AndroidFlashPort implements FlashPort {
  _AndroidFlashPort(this._methods, Stream<dynamic> data) {
    _sub = data.listen((d) {
      if (d is Uint8List) _buf.add(d);
      _signal?.complete();
      _signal = null;
    }, onDone: () => _closed = true);
  }

  final MethodChannel _methods;
  late final StreamSubscription<dynamic> _sub;
  final _buf = BytesBuilder(copy: false);
  Completer<void>? _signal;
  bool _closed = false;

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) => _methods.invokeMethod('signals', {'dtr': dtr, 'rts': rts});

  @override
  Future<void> setBaud(int baud) => _methods.invokeMethod('baud', {'baud': baud});

  @override
  Future<void> write(Uint8List data) async {
    if (_closed) throw const SocketException('The board was unplugged');
    await _methods.invokeMethod('write', {'data': data});
  }

  @override
  Future<Uint8List> read(Duration timeout) async {
    if (_buf.isEmpty && !_closed) {
      final s = _signal ??= Completer<void>();
      await s.future.timeout(timeout, onTimeout: () {});
    }
    return _buf.takeBytes();
  }

  @override
  Future<void> flushInput() async => _buf.clear();

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _methods.invokeMethod('close');
  }
}

class PortBusyException implements Exception {
  PortBusyException(this.port, this.detail);
  final String port;
  final String? detail;
  @override
  String toString() => 'Could not open $port${detail == null ? '' : ': $detail'}';
}
