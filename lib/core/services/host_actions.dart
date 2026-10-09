import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opendeck/features/deck/models/deck_action.dart';

import 'app_focus.dart';
import 'win/win_audio.dart' as win_audio;
import 'win/win_shell.dart' as win_shell;
import 'win/win_input.dart' as win_input;
import 'win/win_windows.dart' as win_windows;

/// Runs key actions on the computer the app is running on.
/// Windows is fully supported; macOS and Linux are best effort; mobile is a no-op
/// (phones configure the deck, the desktop app executes its actions).
class HostActions {
  HostActions._();
  static final instance = HostActions._();

  bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> run(DeckAction a) async {
    if (!supported || a.type == ActionType.none || a.type.runsOnDevice) return;
    try {
      if (Platform.isWindows) {
        await _runWindows(a);
      } else if (Platform.isMacOS) {
        await _runMac(a);
      } else {
        await _runLinux(a);
      }
    } catch (e) {
      debugPrint('HostActions.run(${a.type.name}) failed: $e');
    }
  }

  Future<bool?> micMuted() async {
    try {
      if (Platform.isWindows) return win_audio.endpointMuted(win_audio.eCapture);
      if (Platform.isLinux) return _pactlMuted('get-source-mute', '@DEFAULT_SOURCE@');
      if (Platform.isMacOS) {
        final r = await Process.run('osascript', ['-e', 'input volume of (get volume settings)']);
        return int.tryParse('${r.stdout}'.trim()) == 0;
      }
    } catch (e) {
      debugPrint('micMuted failed: $e');
    }
    return null;
  }

  Future<bool?> speakerMuted() async {
    try {
      if (Platform.isWindows) return win_audio.endpointMuted(win_audio.eRender);
      if (Platform.isLinux) return _pactlMuted('get-sink-mute', '@DEFAULT_SINK@');
      if (Platform.isMacOS) {
        final r = await Process.run('osascript', ['-e', 'output muted of (get volume settings)']);
        return '${r.stdout}'.trim() == 'true';
      }
    } catch (e) {
      debugPrint('speakerMuted failed: $e');
    }
    return null;
  }

  /// Like a taskbar button: a running app comes to the front instead of
  /// opening again. Keys can opt out with the "newWindow" parameter.
  bool _switchToOpen(DeckAction a) => a.param('newWindow') != 'true';

  // Windows
  Future<void> _runWindows(DeckAction a) async {
    switch (a.type) {
      case ActionType.openApp:
        final path = a.param('path').trim();
        if (path.isEmpty) return;
        if (_switchToOpen(a)) {
          final m = AppMatcher.forTarget(path);
          if (m != null && win_windows.focusApp(m, win_shell.grantForeground)) return;
        }
        if (!win_shell.shellOpen(path, a.param('args').trim())) {
          await Process.start('cmd', ['/c', 'start', '', path, ...splitArgs(a.param('args'))], mode: ProcessStartMode.detached);
        }
      case ActionType.openUrl:
        final url = a.param('url').trim();
        if (url.isEmpty) return;
        final scheme = schemeOf(url);
        if (scheme != null && !webSchemes.contains(scheme) && _switchToOpen(a)) {
          final cmd = win_windows.protocolCommand(scheme);
          final m = cmd == null ? null : AppMatcher.forProtocolCommand(cmd);
          if (m != null && win_windows.focusApp(m, win_shell.grantForeground)) return;
        }
        if (!win_shell.shellOpen(url)) await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
      case ActionType.runCommand:
        final cmd = a.param('command').trim();
        if (cmd.isEmpty) return;
        await Process.start('cmd', ['/c', cmd], mode: ProcessStartMode.detached);
      case ActionType.hotkey:
        if (!win_input.sendHotkey(a.param('keys'))) debugPrint('Unrecognised hotkey "${a.param('keys')}"');
      case ActionType.typeText:
        win_input.typeText(a.param('text'));
      case ActionType.media:
        final vk = switch (_mediaOp(a)) {
          MediaOp.volumeUp => 0xAF,
          MediaOp.volumeDown => 0xAE,
          MediaOp.mute => 0xAD,
          MediaOp.next => 0xB0,
          MediaOp.previous => 0xB1,
          MediaOp.stop => 0xB2,
          MediaOp.playPause => 0xB3,
        };
        win_input.tapVirtualKey(vk);
      case ActionType.micMute:
        win_audio.toggleEndpointMute(win_audio.eCapture);
      case ActionType.speakerMute:
        win_audio.toggleEndpointMute(win_audio.eRender);
      default:
        break;
    }
  }

  // MacOS
  Future<void> _runMac(DeckAction a) async {
    Future<void> osa(String script) => Process.run('osascript', ['-e', script]);
    switch (a.type) {
      case ActionType.openApp:
        final path = a.param('path').trim();
        if (path.isEmpty) return;
        final isFile = path.contains('/');
        // `open -a` already brings a running app to the front; -n forces a new instance.
        await Process.start('open', [
          if (!_switchToOpen(a)) '-n',
          if (!isFile) '-a',
          path,
          if (a.param('args').isNotEmpty) '--args',
          ...splitArgs(a.param('args')),
        ], mode: ProcessStartMode.detached);
      case ActionType.openUrl:
        await Process.start('open', [a.param('url')], mode: ProcessStartMode.detached);
      case ActionType.runCommand:
        await Process.start('/bin/sh', ['-c', a.param('command')], mode: ProcessStartMode.detached);
      case ActionType.media:
        switch (_mediaOp(a)) {
          case MediaOp.volumeUp:
            await osa('set volume output volume ((output volume of (get volume settings)) + 6)');
          case MediaOp.volumeDown:
            await osa('set volume output volume ((output volume of (get volume settings)) - 6)');
          case MediaOp.mute:
            await osa('set volume output muted (not (output muted of (get volume settings)))');
          case MediaOp.playPause:
            await osa('tell application "Music" to playpause');
          case MediaOp.next:
            await osa('tell application "Music" to next track');
          case MediaOp.previous:
            await osa('tell application "Music" to previous track');
          case MediaOp.stop:
            await osa('tell application "Music" to stop');
        }
      case ActionType.speakerMute:
        await osa('set volume output muted (not (output muted of (get volume settings)))');
      case ActionType.micMute:
        final muted = await micMuted() ?? false;
        await osa('set volume input volume ${muted ? _macMicRestore : 0}');
        if (!muted) {
          final r = await Process.run('osascript', ['-e', 'input volume of (get volume settings)']);
          _macMicRestore = int.tryParse('${r.stdout}'.trim()) ?? 75;
          if (_macMicRestore == 0) _macMicRestore = 75;
        }
      default:
        break;
    }
  }

  int _macMicRestore = 75;

  // Linux
  Future<void> _runLinux(DeckAction a) async {
    switch (a.type) {
      case ActionType.openApp:
        final path = a.param('path').trim();
        if (path.isEmpty) return;
        await Process.start(path, splitArgs(a.param('args')), mode: ProcessStartMode.detached, runInShell: true);
      case ActionType.openUrl:
        await Process.start('xdg-open', [a.param('url')], mode: ProcessStartMode.detached);
      case ActionType.runCommand:
        await Process.start('/bin/sh', ['-c', a.param('command')], mode: ProcessStartMode.detached);
      case ActionType.media:
        switch (_mediaOp(a)) {
          case MediaOp.volumeUp:
            await Process.run('pactl', ['set-sink-volume', '@DEFAULT_SINK@', '+5%']);
          case MediaOp.volumeDown:
            await Process.run('pactl', ['set-sink-volume', '@DEFAULT_SINK@', '-5%']);
          case MediaOp.mute:
            await Process.run('pactl', ['set-sink-mute', '@DEFAULT_SINK@', 'toggle']);
          case MediaOp.playPause:
            await Process.run('playerctl', ['play-pause']);
          case MediaOp.next:
            await Process.run('playerctl', ['next']);
          case MediaOp.previous:
            await Process.run('playerctl', ['previous']);
          case MediaOp.stop:
            await Process.run('playerctl', ['stop']);
        }
      case ActionType.speakerMute:
        await Process.run('pactl', ['set-sink-mute', '@DEFAULT_SINK@', 'toggle']);
      case ActionType.micMute:
        await Process.run('pactl', ['set-source-mute', '@DEFAULT_SOURCE@', 'toggle']);
      default:
        break;
    }
  }

  Future<bool?> _pactlMuted(String cmd, String target) async {
    final r = await Process.run('pactl', [cmd, target]);
    if (r.exitCode != 0) return null;
    return '${r.stdout}'.toLowerCase().contains('yes');
  }

  MediaOp _mediaOp(DeckAction a) =>
      MediaOp.values.firstWhere((m) => m.name == a.param('op'), orElse: () => MediaOp.playPause);
}

/// Split a command-line argument string, honouring double quotes.
List<String> splitArgs(String s) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  var has = false;
  for (final ch in s.split('')) {
    if (ch == '"') {
      quoted = !quoted;
      has = true;
    } else if (ch == ' ' && !quoted) {
      if (has || cur.isNotEmpty) out.add(cur.toString());
      cur.clear();
      has = false;
    } else {
      cur.write(ch);
    }
  }
  if (has || cur.isNotEmpty) out.add(cur.toString());
  return out;
}
