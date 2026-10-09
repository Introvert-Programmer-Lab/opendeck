import '../models/deck_action.dart';

/// Compiles an action into the HID steps the deck runs by itself (USB keyboard +
/// media keys) when no desktop app is open. Format, per step:
///   ["k", mods, key...]  press and release keys      ["c", usage]  media key
///   ["w", ms]            wait                         ["t", text]   type ASCII text
/// Returns null when the action needs the desktop app (opening apps, websites,
/// commands): a USB device can't start programs by itself, and typing into
/// the Run box is not reliable. The desktop app runs in the tray for that.
List<List<Object>>? hidMacroFor(DeckAction a) {
  switch (a.type) {
    case ActionType.media:
      final usage = _media[a.param('op')];
      return usage == null ? null : [['c', usage]];
    case ActionType.speakerMute:
      return [['c', 0xE2]];
    case ActionType.micMute:
      // Windows 11 call mute (Teams, Zoom, Meet...). The desktop app does a true system mute.
      return [['k', _gui | _alt, _keys['k']!]];
    case ActionType.hotkey:
      final k = parseHotkey(a.param('keys'));
      return k == null ? null : [k];
    case ActionType.typeText:
      final t = _ascii(a.param('text'));
      return t.isEmpty ? null : [['t', t]];
    default:
      return null;
  }
}

String _ascii(String s) => String.fromCharCodes(s.codeUnits.where((c) => c >= 32 && c < 127));

const _ctrl = 0x01, _shift = 0x02, _alt = 0x04, _gui = 0x08;

const _media = {
  'volumeUp': 0xE9,
  'volumeDown': 0xEA,
  'mute': 0xE2,
  'playPause': 0xCD,
  'next': 0xB5,
  'previous': 0xB6,
  'stop': 0xB7,
};

final Map<String, int> _keys = {
  for (var i = 0; i < 26; i++) String.fromCharCode(97 + i): 0x04 + i,
  for (var i = 1; i <= 9; i++) '$i': 0x1E + i - 1,
  '0': 0x27,
  'enter': 0x28, 'return': 0x28, 'esc': 0x29, 'escape': 0x29, 'backspace': 0x2A, 'tab': 0x2B, 'space': 0x2C,
  'minus': 0x2D, '-': 0x2D, 'equal': 0x2E, '=': 0x2E, '[': 0x2F, ']': 0x30, '\\': 0x31, ';': 0x33, "'": 0x34,
  '`': 0x35, ',': 0x36, '.': 0x37, '/': 0x38, 'capslock': 0x39,
  for (var i = 1; i <= 12; i++) 'f$i': 0x3A + i - 1,
  for (var i = 13; i <= 24; i++) 'f$i': 0x68 + i - 13,
  'printscreen': 0x46, 'prtsc': 0x46, 'scrolllock': 0x47, 'pause': 0x48, 'insert': 0x49, 'home': 0x4A,
  'pageup': 0x4B, 'delete': 0x4C, 'del': 0x4C, 'end': 0x4D, 'pagedown': 0x4E,
  'right': 0x4F, 'left': 0x50, 'down': 0x51, 'up': 0x52,
};

/// "ctrl+shift+m" -> ["k", mods, keycode...]
List<Object>? parseHotkey(String combo) {
  var mods = 0;
  final keys = <int>[];
  for (final raw in combo.toLowerCase().split('+')) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    switch (p) {
      case 'ctrl' || 'control':
        mods |= _ctrl;
      case 'shift':
        mods |= _shift;
      case 'alt' || 'option':
        mods |= _alt;
      case 'win' || 'super' || 'cmd' || 'meta' || 'gui':
        mods |= _gui;
      default:
        final k = _keys[p];
        if (k == null) return null;
        keys.add(k);
    }
  }
  if (keys.isEmpty && mods == 0) return null;
  return ['k', mods, ...keys.take(6)];
}
