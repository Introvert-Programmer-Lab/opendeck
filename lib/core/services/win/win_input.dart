// Keyboard injection on Windows through user32!SendInput (raw FFI, no win32 package).
import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _inputKeyboard = 1;
const _keyeventfExtendedKey = 0x0001;
const _keyeventfKeyUp = 0x0002;
const _keyeventfUnicode = 0x0004;
const _inputSize = 40; // sizeof(INPUT) on x64

typedef _SendInputC = Uint32 Function(Uint32 n, Pointer<Uint8> inputs, Int32 size);
typedef _SendInputDart = int Function(int n, Pointer<Uint8> inputs, int size);

final _user32 = DynamicLibrary.open('user32.dll');
final _sendInput = _user32.lookupFunction<_SendInputC, _SendInputDart>('SendInput');

class _Key {
  const _Key(this.vk, {this.scan = 0, this.flags = 0});
  final int vk, scan, flags;
}

/// Virtual-key codes that need the extended-key flag.
const _extended = {
  0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, // page/home/end/arrows/ins/del
  0x5B, 0xA3, 0xA5, // win, right ctrl, right alt
  0xAD, 0xAE, 0xAF, 0xB0, 0xB1, 0xB2, 0xB3, // media
  0x2C, // print screen
};

void _send(List<_Key> keys, {required bool up}) {
  if (keys.isEmpty) return;
  final buf = calloc<Uint8>(_inputSize * keys.length);
  try {
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final base = buf + i * _inputSize;
      base.cast<Uint32>().value = _inputKeyboard;
      (base + 8).cast<Uint16>().value = k.vk;
      (base + 10).cast<Uint16>().value = k.scan;
      var flags = k.flags;
      if (_extended.contains(k.vk)) flags |= _keyeventfExtendedKey;
      if (up) flags |= _keyeventfKeyUp;
      (base + 12).cast<Uint32>().value = flags;
    }
    _sendInput(keys.length, buf, _inputSize);
  } finally {
    calloc.free(buf);
  }
}

/// Press and release a single virtual key.
void tapVirtualKey(int vk) {
  _send([_Key(vk)], up: false);
  _send([_Key(vk)], up: true);
}

const _named = <String, int>{
  'ctrl': 0x11, 'control': 0x11, 'shift': 0x10, 'alt': 0x12, 'win': 0x5B, 'meta': 0x5B, 'cmd': 0x5B,
  'enter': 0x0D, 'return': 0x0D, 'esc': 0x1B, 'escape': 0x1B, 'tab': 0x09, 'space': 0x20,
  'backspace': 0x08, 'delete': 0x2E, 'del': 0x2E, 'insert': 0x2D, 'ins': 0x2D,
  'home': 0x24, 'end': 0x23, 'pageup': 0x21, 'pagedown': 0x22,
  'up': 0x26, 'down': 0x28, 'left': 0x25, 'right': 0x27,
  'printscreen': 0x2C, 'prtsc': 0x2C,
  'volumeup': 0xAF, 'volumedown': 0xAE, 'mute': 0xAD, 'playpause': 0xB3, 'next': 0xB0, 'prev': 0xB1,
  'stop': 0xB2,
  'plus': 0xBB, 'minus': 0xBD, 'comma': 0xBC, 'period': 0xBE,
};

int? _vkFor(String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return null;
  final v = _named[n];
  if (v != null) return v;
  if (n.length == 1) {
    final c = n.codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7A) return c - 0x20; // a-z -> 'A'-'Z'
    if (c >= 0x30 && c <= 0x39) return c; // 0-9
  }
  final f = RegExp(r'^f(\d{1,2})$').firstMatch(n);
  if (f != null) {
    final i = int.parse(f.group(1)!);
    if (i >= 1 && i <= 24) return 0x70 + i - 1;
  }
  return null;
}

/// Send a combo like "ctrl+shift+m" or "win+shift+s". Returns false if unparseable.
bool sendHotkey(String combo) {
  final parts = combo.split('+').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final keys = <_Key>[];
  for (final p in parts) {
    final vk = _vkFor(p);
    if (vk == null) return false;
    keys.add(_Key(vk));
  }
  if (keys.isEmpty) return false;
  for (final k in keys) {
    _send([k], up: false);
  }
  for (final k in keys.reversed) {
    _send([k], up: true);
  }
  return true;
}

/// Type arbitrary text (any script, including Arabic) as Unicode key events.
void typeText(String text) {
  for (final unit in text.codeUnits) {
    final k = _Key(0, scan: unit, flags: _keyeventfUnicode);
    _send([k], up: false);
    _send([k], up: true);
  }
}
