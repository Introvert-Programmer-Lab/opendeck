import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'flasher/flash_log.dart';
import 'flasher/flash_port.dart' show PortBusyException;
import 'flasher/win_serial.dart';
import 'win_ports.dart';

/// A line-oriented link to a deck (USB serial or TCP).
abstract class DeckTransport {
  String get label;
  bool get isUsb;

  /// Complete text lines (without the newline). Closes when the link drops.
  Stream<String> get lines;
  Future<void> send(String line);
  Future<void> close();
}

/// Splits a byte stream into UTF-8 text lines.
class _LineSplitter {
  _LineSplitter(this._out);
  final StreamController<String> _out;
  final _pending = <int>[];

  void add(List<int> bytes) {
    for (final b in bytes) {
      if (b == 0x0A) {
        var line = utf8.decode(_pending, allowMalformed: true);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        _pending.clear();
        if (!_out.isClosed) _out.add(line);
      } else {
        _pending.add(b);
      }
    }
  }
}

class SerialPortEntry {
  const SerialPortEntry({required this.name, required this.description, required this.isEspressif, this.isBridge = false});
  final String name;
  final String description;
  final bool isEspressif;

  /// A USB-UART bridge (CH340, CP210x, FTDI), as on boards without native USB.
  final bool isBridge;

  bool get likelyDeck => isEspressif || isBridge;
}

/// Baud rate of the firmware's UART link. Native USB ignores it.
const kDeckBaud = 921600;

bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class SerialDeckTransport implements DeckTransport {
  SerialDeckTransport._(this._port, this._name) {
    _splitter = _LineSplitter(_lines);
    _reader = SerialPortReader(_port, timeout: _readerWaitMs);
    _sub = _reader.stream.listen(
      _splitter.add,
      onError: (_) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  final SerialPort _port;
  final String _name;

  /// The reader's background isolate waits on the native port for up to this
  /// long at a time, and keeps using it until its wait returns.
  static const _readerWaitMs = 100;
  late final SerialPortReader _reader;
  late final StreamSubscription<Uint8List> _sub;
  final _lines = StreamController<String>.broadcast();
  late final _LineSplitter _splitter;
  bool _closed = false;

  static List<SerialPortEntry> listPorts() {
    if (!_isDesktop) return const [];
    try {
      final out = <SerialPortEntry>[];
      if (Platform.isWindows) {
        for (final p in listWinPorts()) {
          out.add(SerialPortEntry(
              name: p.name, description: p.description, isEspressif: p.vid == 0x303A, isBridge: _bridgeVids.contains(p.vid)));
        }
      } else {
        for (final name in SerialPort.availablePorts) {
          final p = SerialPort(name);
          var desc = '';
          var vid = 0;
          try {
            desc = p.description ?? '';
          } catch (_) {}
          try {
            vid = p.vendorId ?? 0;
          } catch (_) {}
          p.dispose();
          out.add(SerialPortEntry(
              name: name, description: desc, isEspressif: vid == 0x303A, isBridge: _bridgeVids.contains(vid)));
        }
      }
      int rank(SerialPortEntry e) => e.isEspressif ? 2 : (e.isBridge ? 1 : 0);
      out.sort((a, b) => rank(b) - rank(a));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static const _bridgeVids = {0x1A86, 0x10C4, 0x0403};

  static Future<DeckTransport> open(String portName) async {
    if (!_isDesktop) throw UnsupportedError('USB serial is only available on desktop');
    if (Platform.isWindows) return WinDeckTransport.open(portName);
    FlashLog.line('deck link: opening $portName');
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw _openError(portName, err?.message);
    }
    // RTS drives the chip reset and DTR the boot strap (USB-Serial/JTAG and the
    // usual auto-reset circuit on bridge boards): keep both released so
    // opening the port never resets the deck.
    final cfg = SerialPortConfig()
      ..baudRate = kDeckBaud
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..dtr = SerialPortDtr.off
      ..rts = SerialPortRts.off
      ..setFlowControl(SerialPortFlowControl.none);
    // setFlowControl resets dtr/rts handling, so pin them again.
    cfg
      ..dtr = SerialPortDtr.off
      ..rts = SerialPortRts.off;
    port.config = cfg;
    cfg.dispose();
    return SerialDeckTransport._(port, portName);
  }

  @override
  String get label => _name;

  @override
  bool get isUsb => true;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> send(String line) async {
    if (_closed) throw const SocketException('USB link closed');
    final data = Uint8List.fromList(utf8.encode('$line\n'));
    var off = 0;
    while (off < data.length) {
      final n = _port.write(Uint8List.sublistView(data, off), timeout: 2000);
      if (n <= 0) throw const SocketException('USB write failed');
      off += n;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    FlashLog.line('deck link: closing $_name');
    await _sub.cancel();
    try {
      _reader.close();
    } catch (_) {}
    // Freeing the port while the reader isolate is still inside a native wait
    // on it crashes the whole app, so let that wait run out first.
    await Future<void>.delayed(const Duration(milliseconds: _readerWaitMs * 3));
    FlashLog.line('deck link: freeing $_name');
    try {
      _port.close();
      _port.dispose();
    } catch (_) {}
    FlashLog.line('deck link: closed $_name');
    await _lines.close();
  }
}

/// The USB link on Windows, on the kernel32 port. Reads are polled on a timer
/// without blocking, so no background isolate holds the port and closing it
/// is immediate.
class WinDeckTransport implements DeckTransport {
  WinDeckTransport._(this._port, this._name) {
    _splitter = _LineSplitter(_lines);
    _poll = Timer.periodic(const Duration(milliseconds: 10), (_) => _read());
  }

  final WinSerialPort _port;
  final String _name;
  late final Timer _poll;
  final _lines = StreamController<String>.broadcast();
  late final _LineSplitter _splitter;
  bool _closed = false;

  static Future<WinDeckTransport> open(String portName) async {
    FlashLog.line('deck link: opening $portName');
    final WinSerialPort port;
    try {
      // Opening configures DTR and RTS off, so the deck is not reset.
      port = WinSerialPort.open(portName, kDeckBaud);
    } on PortBusyException catch (e) {
      throw _openError(portName, e.detail);
    }
    return WinDeckTransport._(port, portName);
  }

  void _read() {
    if (_closed) return;
    // A full buffer means more is waiting: keep reading, a few times at most.
    for (var i = 0; i < 8; i++) {
      final data = _port.poll();
      if (data == null) {
        FlashLog.line('deck link: $_name read failed');
        close();
        return;
      }
      if (data.isEmpty) return;
      _splitter.add(data);
      if (data.length < 16384) return;
    }
  }

  @override
  String get label => _name;

  @override
  bool get isUsb => true;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> send(String line) async {
    if (_closed) throw const SocketException('USB link closed');
    _port.writeSync(Uint8List.fromList(utf8.encode('$line\n')));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _poll.cancel();
    _port.closeSync();
    FlashLog.line('deck link: closed $_name');
    await _lines.close();
  }
}

class TcpDeckTransport implements DeckTransport {
  TcpDeckTransport._(this._socket, this._host) {
    _splitter = _LineSplitter(_lines);
    _socket.listen(_splitter.add, onError: (_) => close(), onDone: close, cancelOnError: true);
  }

  final Socket _socket;
  final String _host;
  final _lines = StreamController<String>.broadcast();
  late final _LineSplitter _splitter;
  bool _closed = false;

  static Future<TcpDeckTransport> connect(String host,
      {int port = 7777, Duration timeout = const Duration(seconds: 4)}) async {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.setOption(SocketOption.tcpNoDelay, true);
    return TcpDeckTransport._(s, host);
  }

  @override
  String get label => _host;

  @override
  bool get isUsb => false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> send(String line) async {
    if (_closed) throw const SocketException('Wi-Fi link closed');
    _socket.add(utf8.encode('$line\n'));
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close();
    } catch (_) {}
    _socket.destroy();
    await _lines.close();
  }
}

SocketException _openError(String port, String? msg) =>
    SocketException('Could not open $port${msg == null ? '' : ': $msg'}');
