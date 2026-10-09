import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _ShellExecuteC = IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Int32);
typedef _ShellExecuteDart = int Function(int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, int);

final _shell32 = DynamicLibrary.open('shell32.dll');
final _user32 = DynamicLibrary.open('user32.dll');
final _shellExecute = _shell32.lookupFunction<_ShellExecuteC, _ShellExecuteDart>('ShellExecuteW');
final _sendInput = _user32.lookupFunction<Uint32 Function(Uint32, Pointer<Uint8>, Int32), int Function(int, Pointer<Uint8>, int)>('SendInput');
final _allowSetForeground = _user32.lookupFunction<Int32 Function(Uint32), int Function(int)>('AllowSetForegroundWindow');

const _asfwAny = 0xFFFFFFFF;
const _inputSize = 40; // sizeof(INPUT) on x64

/// Windows won't let a background (tray) app bring windows to the front, so a
/// launched app would only flash in the taskbar. Sending an empty mouse input
/// first makes this process the last input receiver, which lets it hand
/// foreground rights to whatever it launches.
void grantForeground() {
  using((arena) {
    final input = arena<Uint8>(_inputSize); // zeroed: INPUT_MOUSE, no movement
    _sendInput(1, input, _inputSize);
  });
  _allowSetForeground(_asfwAny);
}

/// Opens an app, file, shortcut, `shell:AppsFolder\…` entry or URL directly through
/// the Windows shell, in front: instant, no console window. Returns false if Windows refused.
bool shellOpen(String target, [String args = '']) {
  grantForeground();
  return using((arena) {
    final r = _shellExecute(
      0,
      'open'.toNativeUtf16(allocator: arena),
      target.toNativeUtf16(allocator: arena),
      args.isEmpty ? nullptr : args.toNativeUtf16(allocator: arena),
      nullptr,
      1, // SW_SHOWNORMAL
    );
    return r > 32;
  });
}
