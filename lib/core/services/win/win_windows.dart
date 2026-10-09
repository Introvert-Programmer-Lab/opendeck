// Top-level window lookup and activation on Windows (raw FFI), used to switch
// to an app that is already open instead of launching it again.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../app_focus.dart';

const _gwOwner = 4;
const _gwlExStyle = -20;
const _wsExToolWindow = 0x80;
const _swRestore = 9;
const _processQueryLimited = 0x1000;
const _dwmCloaked = 14;
// Predefined registry keys are sign-extended 32-bit values.
const _hkeyClassesRoot = -0x80000000;
const _hkeyCurrentUser = -0x7FFFFFFF;
const _rrfRtRegSz = 0x2;
const _vtLpwstr = 31;
const _iidPropertyStore = '886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99';
const _pkeyAppUserModelId = '9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3';

/// Shell windows that are visible but never what the user means by "the app".
const _ignoredClasses = {'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Windows.UI.Core.CoreWindow'};

typedef _EnumProc = Int32 Function(IntPtr hwnd, IntPtr lParam);

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');
final _dwmapi = DynamicLibrary.open('dwmapi.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _enumWindows = _user32
    .lookupFunction<
      Int32 Function(Pointer<NativeFunction<_EnumProc>>, IntPtr),
      int Function(Pointer<NativeFunction<_EnumProc>>, int)
    >('EnumWindows');
final _isWindowVisible = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
final _isIconic = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _getWindow = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetWindow');
final _getWindowLongPtr = _user32.lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
  'GetWindowLongPtrW',
);
final _getWindowTextLength = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GetWindowTextLengthW');
final _getClassName = _user32
    .lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32), int Function(int, Pointer<Utf16>, int)>(
      'GetClassNameW',
    );
final _getWindowThreadProcessId = _user32
    .lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
      'GetWindowThreadProcessId',
    );
final _getForegroundWindow = _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
final _setForegroundWindow = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final _openProcess = _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>(
  'OpenProcess',
);
final _queryImageName = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
    >('QueryFullProcessImageNameW');
final _closeHandle = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _getPropertyStore = _shell32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Pointer<Pointer<Void>>),
      int Function(int, Pointer<Uint8>, Pointer<Pointer<Void>>)
    >('SHGetPropertyStoreForWindow');
final _propVariantClear = _ole32.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>(
  'PropVariantClear',
);
final _dwmGetWindowAttribute = _dwmapi
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint32>, Uint32),
      int Function(int, int, Pointer<Uint32>, int)
    >('DwmGetWindowAttribute');
final _regGetValue = _advapi32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>)
    >('RegGetValueW');

class AppWindow {
  const AppWindow(this.hwnd, this.exePath, this.aumid);
  final int hwnd;
  final String exePath;
  final String? aumid;
}

final _found = <int>[];

int _collect(int hwnd, int _) {
  _found.add(hwnd);
  return 1;
}

/// Windows that show up in Alt+Tab, front to back, minimized ones included.
List<AppWindow> appWindows() {
  _found.clear();
  _enumWindows(Pointer.fromFunction<_EnumProc>(_collect, 0), 0);
  final out = <AppWindow>[];
  return using((a) {
    final cls = a<Uint16>(256).cast<Utf16>();
    final owner = a<Uint32>();
    final cloaked = a<Uint32>();
    for (final h in _found) {
      if (_isWindowVisible(h) == 0 || _getWindow(h, _gwOwner) != 0) continue;
      if (_getWindowLongPtr(h, _gwlExStyle) & _wsExToolWindow != 0) continue;
      if (_getWindowTextLength(h) == 0) continue;
      cloaked.value = 0;
      if (_dwmGetWindowAttribute(h, _dwmCloaked, cloaked, 4) == 0 && cloaked.value != 0) continue;
      _getClassName(h, cls, 256);
      if (_ignoredClasses.contains(cls.toDartString())) continue;
      _getWindowThreadProcessId(h, owner);
      if (owner.value == 0 || owner.value == pid) continue;
      final exe = _imagePath(owner.value);
      if (exe == null) continue;
      out.add(AppWindow(h, exe, _windowAumid(h)));
    }
    return out;
  });
}

String? _imagePath(int processId) {
  final hp = _openProcess(_processQueryLimited, 0, processId);
  if (hp == 0) return null;
  try {
    return using((a) {
      final buf = a<Uint16>(1024).cast<Utf16>();
      final len = a<Uint32>()..value = 1024;
      return _queryImageName(hp, 0, buf, len) == 0 ? null : buf.toDartString(length: len.value);
    });
  } finally {
    _closeHandle(hp);
  }
}

/// The window's explicit AppUserModelID (PKEY_AppUserModel_ID), if it sets one.
String? _windowAumid(int hwnd) => using((a) {
  final store = a<Pointer<Void>>();
  if (_getPropertyStore(hwnd, _guid(a, _iidPropertyStore), store) != 0 || store.value == nullptr) return null;
  final obj = store.value;
  try {
    final key = a<Uint8>(20);
    key.asTypedList(16).setAll(0, _guid(a, _pkeyAppUserModelId).asTypedList(16));
    (key + 16).cast<Uint32>().value = 5;
    final pv = a<Uint8>(32);
    final getValue = _vt<Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      obj,
      5,
    ).asFunction<int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>();
    if (getValue(obj, key, pv) != 0) return null;
    try {
      if (pv.cast<Uint16>().value != _vtLpwstr) return null;
      final s = (pv + 8).cast<Pointer<Utf16>>().value;
      return s == nullptr ? null : s.toDartString();
    } finally {
      _propVariantClear(pv);
    }
  } finally {
    _vt<Uint32 Function(Pointer<Void>)>(obj, 2).asFunction<int Function(Pointer<Void>)>()(obj);
  }
});

/// Brings one of the app's windows to the front. When the app is already in
/// front, moves on to its next window, so repeated presses cycle through them.
/// Returns false when the app has no open window.
bool focusApp(AppMatcher m, void Function() grantForeground) {
  final wins = appWindows().where((w) => m.matches(exePath: w.exePath, aumid: w.aumid)).toList();
  if (wins.isEmpty) return false;
  var target = wins.first;
  if (target.hwnd == _getForegroundWindow()) {
    if (wins.length == 1) return true;
    target = wins.last;
  }
  if (_isIconic(target.hwnd) != 0) _showWindow(target.hwnd, _swRestore);
  grantForeground();
  _setForegroundWindow(target.hwnd);
  return true;
}

/// Command line registered for a URL scheme, e.g. `discord` or `spotify`.
String? protocolCommand(String scheme) => using((a) {
  for (final (root, path) in [
    (_hkeyCurrentUser, 'Software\\Classes\\$scheme\\shell\\open\\command'),
    (_hkeyClassesRoot, '$scheme\\shell\\open\\command'),
  ]) {
    final key = path.toNativeUtf16(allocator: a);
    final size = a<Uint32>()..value = 4096;
    final buf = a<Uint8>(4096);
    if (_regGetValue(root, key, nullptr, _rrfRtRegSz, nullptr, buf, size) == 0) {
      return buf.cast<Utf16>().toDartString();
    }
  }
  return null;
});

Pointer<NativeFunction<T>> _vt<T extends Function>(Pointer<Void> obj, int index) =>
    obj.cast<Pointer<Pointer<Void>>>().value[index].cast<NativeFunction<T>>();

Pointer<Uint8> _guid(Arena a, String s) {
  final hex = s.replaceAll('-', '');
  final g = a<Uint8>(16);
  g.cast<Uint32>().value = int.parse(hex.substring(0, 8), radix: 16);
  (g + 4).cast<Uint16>().value = int.parse(hex.substring(8, 12), radix: 16);
  (g + 6).cast<Uint16>().value = int.parse(hex.substring(12, 16), radix: 16);
  for (var i = 0; i < 8; i++) {
    g[8 + i] = int.parse(hex.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return g;
}
