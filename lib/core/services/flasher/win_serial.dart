// Serial port through kernel32 (raw FFI). Used for everything serial on
// Windows: the bootloader reset needs DTR and RTS set one at a time, in a fixed
// order, and libserialport can crash the app there (see win_ports.dart).
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'flash_port.dart';

const _genericReadWrite = 0xC0000000;
const _openExisting = 3;
const _invalidHandle = -1;
const _setRts = 3, _clrRts = 4, _setDtr = 5, _clrDtr = 6;
const _purgeRx = 0x0002 | 0x0008; // PURGE_RXABORT | PURGE_RXCLEAR
const _dcbSize = 28;
const _maxDword = 0xFFFFFFFF;

typedef _CreateFileC = IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr);
typedef _CreateFileDart = int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _HandlePtrC = Int32 Function(IntPtr, Pointer<Uint8>);
typedef _HandlePtrDart = int Function(int, Pointer<Uint8>);
typedef _HandleIntC = Int32 Function(IntPtr, Uint32);
typedef _HandleIntDart = int Function(int, int);
typedef _ReadWriteC = Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _ReadWriteDart = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _CloseC = Int32 Function(IntPtr);
typedef _CloseDart = int Function(int);

final _k32 = DynamicLibrary.open('kernel32.dll');
final _createFile = _k32.lookupFunction<_CreateFileC, _CreateFileDart>('CreateFileW');
final _getCommState = _k32.lookupFunction<_HandlePtrC, _HandlePtrDart>('GetCommState');
final _setCommState = _k32.lookupFunction<_HandlePtrC, _HandlePtrDart>('SetCommState');
final _setCommTimeouts = _k32.lookupFunction<_HandlePtrC, _HandlePtrDart>('SetCommTimeouts');
final _escape = _k32.lookupFunction<_HandleIntC, _HandleIntDart>('EscapeCommFunction');
final _purge = _k32.lookupFunction<_HandleIntC, _HandleIntDart>('PurgeComm');
final _readFile = _k32.lookupFunction<_ReadWriteC, _ReadWriteDart>('ReadFile');
final _writeFile = _k32.lookupFunction<_ReadWriteC, _ReadWriteDart>('WriteFile');
final _closeHandle = _k32.lookupFunction<_CloseC, _CloseDart>('CloseHandle');

class WinSerialPort implements FlashPort {
  WinSerialPort._(this._h);
  final int _h;
  final _buf = calloc<Uint8>(16384);
  final _count = calloc<Uint32>();
  final _timeouts = calloc<Uint32>(5);
  int _readTimeoutMs = -1;
  bool _closed = false;

  static WinSerialPort open(String name, int baud) {
    final path = (r'\\.\' + name).toNativeUtf16();
    final h = _createFile(path, _genericReadWrite, 0, nullptr, _openExisting, 0, 0);
    calloc.free(path);
    if (h == _invalidHandle || h == 0) throw PortBusyException(name, 'it may be open in another program');
    final p = WinSerialPort._(h);
    p._configure(baud);
    p._setReadTimeout(0); // also sets the write timeout before the first write
    return p;
  }

  void _configure(int baud) {
    final dcb = calloc<Uint8>(_dcbSize);
    try {
      final d = ByteData.sublistView(dcb.asTypedList(_dcbSize));
      d.setUint32(0, _dcbSize, Endian.little);
      _getCommState(_h, dcb);
      d.setUint32(4, baud, Endian.little);
      // fBinary on, DTR and RTS under manual control (EscapeCommFunction), no flow control.
      d.setUint32(8, 0x1, Endian.little);
      d.setUint8(18, 8); // ByteSize
      d.setUint8(19, 0); // NOPARITY
      d.setUint8(20, 0); // ONESTOPBIT
      if (_setCommState(_h, dcb) == 0) throw const SocketException('Could not configure the serial port');
    } finally {
      calloc.free(dcb);
    }
  }

  void _setReadTimeout(int ms) {
    if (ms == _readTimeoutMs) return;
    _readTimeoutMs = ms;
    // Return at once with whatever is buffered, or wait up to ms for the first byte.
    _timeouts[0] = _maxDword;
    _timeouts[1] = _maxDword;
    _timeouts[2] = ms < 1 ? 1 : ms;
    _timeouts[3] = 0;
    _timeouts[4] = 2000;
    _setCommTimeouts(_h, _timeouts.cast());
  }

  /// Whatever has arrived, without waiting. Null when the port is gone.
  Uint8List? poll() {
    const noWait = -2;
    if (_readTimeoutMs != noWait) {
      _readTimeoutMs = noWait;
      _timeouts[0] = _maxDword;
      _timeouts[1] = 0;
      _timeouts[2] = 0;
      _timeouts[3] = 0;
      _timeouts[4] = 2000;
      _setCommTimeouts(_h, _timeouts.cast());
    }
    if (_readFile(_h, _buf, 16384, _count, nullptr) == 0) return null;
    return Uint8List.fromList(_buf.asTypedList(_count.value));
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    if (rts != null) _escape(_h, rts ? _setRts : _clrRts);
    if (dtr != null) _escape(_h, dtr ? _setDtr : _clrDtr);
  }

  @override
  Future<void> setBaud(int baud) async => _configure(baud);

  @override
  Future<void> write(Uint8List data) async => writeSync(data);

  void writeSync(Uint8List data) {
    var off = 0;
    // Each WriteFile gives up after 2 s without room in the driver; a board
    // busy writing its flash can stop reading for longer than that.
    final stalled = Stopwatch();
    while (off < data.length) {
      final n = data.length - off > 16384 ? 16384 : data.length - off;
      _buf.asTypedList(n).setRange(0, n, data, off);
      if (_writeFile(_h, _buf, n, _count, nullptr) == 0) throw const SocketException('USB write failed');
      if (_count.value == 0) {
        stalled.start();
        if (stalled.elapsedMilliseconds > 6000) throw const SocketException('USB write timed out');
        continue;
      }
      stalled
        ..stop()
        ..reset();
      off += _count.value;
    }
  }

  @override
  Future<Uint8List> read(Duration timeout) async {
    _setReadTimeout(timeout.inMilliseconds);
    if (_readFile(_h, _buf, 16384, _count, nullptr) == 0) throw const SocketException('USB read failed');
    return Uint8List.fromList(_buf.asTypedList(_count.value));
  }

  @override
  Future<void> flushInput() async => _purge(_h, _purgeRx);

  @override
  Future<void> close() async => closeSync();

  void closeSync() {
    if (_closed) return;
    _closed = true;
    _closeHandle(_h);
    calloc.free(_buf);
    calloc.free(_count);
    calloc.free(_timeouts);
  }
}
