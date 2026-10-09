import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/deck_action.dart';
import '../models/deck_model.dart';
import 'icon_library.dart';

const int kLime = 0xFFCCFF00;
const int kDark = 0xFF0A100E;
const int kInk = 0xFF0A100E;

DeckKey _k(String label, IconData icon, DeckAction action,
    {IconData? altIcon, String altLabel = '', int? bg, int? fg, int? altBg, int? altFg}) {
  return DeckKey(
    id: newId(),
    label: label,
    icon: KeyIcon.glyph(icon.codePoint),
    altIcon: altIcon != null ? KeyIcon.glyph(altIcon.codePoint) : const KeyIcon.none(),
    altLabel: altLabel,
    background: bg,
    foreground: fg,
    altBackground: altBg,
    altForeground: altFg,
    action: action,
  );
}

DeckAction _media(MediaOp op) => DeckAction(ActionType.media, {'op': op.name});

/// Key with an official app icon (PNG bytes).
DeckKey _app(String label, Uint8List icon, DeckAction action) =>
    DeckKey(id: newId(), label: label, icon: KeyIcon.image(icon), action: action);

Future<Uint8List> _asset(String name) async => (await rootBundle.load('assets/default_icons/$name.png')).buffer.asUint8List();

Future<Uint8List> _brand(String slug) async {
  final b = (await IconLibrary.instance.brands()).firstWhere((x) => x.slug == slug);
  return IconLibrary.instance.brandPng(b);
}

/// OBS's default install location, valid on any PC (FOLDERID_ProgramFiles).
const _obsLaunch = r'shell:AppsFolder\{6D809377-6AF0-444B-8957-A3773F02200E}\obs-studio\bin\64bit\obs64.exe';

/// The deck a new install starts with, using official app icons.
Future<DeckProject> buildDefaultDeck({bool arabic = false}) async {
  String t(String en, String ar) => arabic ? ar : en;
  final chrome = await _asset('google-chrome'), explorer = await _asset('windows-explorer'), vscode = await _asset('visual-studio-code');
  final spotify = await _asset('spotify'), discord = await _asset('discord'), youtube = await _asset('youtube');
  final obs = await _brand('obsstudio');

  final mic = _k(t('Mic', 'المايك'), Icons.mic_rounded, const DeckAction(ActionType.micMute),
      altIcon: Icons.mic_off_rounded, altLabel: t('Muted', 'مكتوم'), fg: kLime, altBg: kLime, altFg: kInk);
  final speaker = _k(t('Sound', 'الصوت'), Icons.volume_up_rounded, const DeckAction(ActionType.speakerMute),
      altIcon: Icons.volume_off_rounded, altLabel: t('Silent', 'صامت'), fg: kLime, altBg: kLime, altFg: kInk);

  final main = DeckPage(
    id: newId(),
    name: t('Main', 'الرئيسية'),
    sections: [
      DeckSection(title: t('Apps', 'التطبيقات'), rows: 2, cols: 3, flex: 1, keys: [
        _app('Chrome', chrome, const DeckAction(ActionType.openApp, {'path': 'chrome'})),
        _app(t('Explorer', 'المستكشف'), explorer, const DeckAction(ActionType.openApp, {'path': 'explorer'})),
        _app('VS Code', vscode, const DeckAction(ActionType.openApp, {'path': 'code'})),
        _app('Spotify', spotify, const DeckAction(ActionType.openUrl, {'url': 'spotify:'})),
        _app('Discord', discord, const DeckAction(ActionType.openUrl, {'url': 'discord:'})),
        _app('YouTube', youtube, const DeckAction(ActionType.openUrl, {'url': 'https://www.youtube.com'})),
      ]),
      DeckSection(title: t('Controls', 'التحكم'), rows: 2, cols: 3, flex: 1, keys: [
        mic,
        speaker,
        _k(t('Play', 'تشغيل'), Icons.play_arrow_rounded, _media(MediaOp.playPause), fg: kLime),
        _k(t('Vol -', 'خفض'), Icons.volume_down_rounded, _media(MediaOp.volumeDown)),
        _k(t('Vol +', 'رفع'), Icons.volume_up_rounded, _media(MediaOp.volumeUp)),
        _k(t('Next', 'التالي'), Icons.skip_next_rounded, _media(MediaOp.next)),
      ]),
    ],
  );

  final media = DeckPage(
    id: newId(),
    name: t('Media', 'الوسائط'),
    sections: [
      DeckSection(title: t('Playback', 'التشغيل'), rows: 2, cols: 3, keys: [
        _k(t('Previous', 'السابق'), Icons.skip_previous_rounded, _media(MediaOp.previous)),
        _k(t('Play', 'تشغيل'), Icons.play_arrow_rounded, _media(MediaOp.playPause), bg: kLime, fg: kInk),
        _k(t('Next', 'التالي'), Icons.skip_next_rounded, _media(MediaOp.next)),
        _k(t('Stop', 'إيقاف'), Icons.stop_rounded, _media(MediaOp.stop)),
        _k(t('Vol -', 'خفض'), Icons.volume_down_rounded, _media(MediaOp.volumeDown)),
        _k(t('Vol +', 'رفع'), Icons.volume_up_rounded, _media(MediaOp.volumeUp)),
      ]),
      DeckSection(title: t('Deck', 'اللوحة'), rows: 1, cols: 3, keys: [
        _k(t('Dimmer', 'أخفت'), Icons.brightness_low_rounded, const DeckAction(ActionType.brightnessDown)),
        _k(t('Brighter', 'أسطع'), Icons.brightness_high_rounded, const DeckAction(ActionType.brightnessUp)),
        _app('Spotify', spotify, const DeckAction(ActionType.openUrl, {'url': 'spotify:'})),
      ]),
    ].map((s) => s.copyWith(flex: s.rows)).toList(),
  );

  final stream = DeckPage(
    id: newId(),
    name: t('Streaming', 'البث'),
    sections: [
      DeckSection(title: t('Recording', 'التسجيل'), rows: 2, cols: 3, keys: [
        _app('OBS', obs, const DeckAction(ActionType.openApp, {'path': _obsLaunch})),
        _k(t('Record', 'تسجيل'), Icons.fiber_manual_record_rounded,
            const DeckAction(ActionType.hotkey, {'keys': 'ctrl+alt+r'}), fg: 0xFFFF5A4E),
        _k(t('Scene 1', 'مشهد 1'), Icons.videocam_rounded, const DeckAction(ActionType.hotkey, {'keys': 'ctrl+alt+1'})),
        _k(t('Scene 2', 'مشهد 2'), Icons.desktop_windows_rounded, const DeckAction(ActionType.hotkey, {'keys': 'ctrl+alt+2'})),
        mic.copyWith(),
        _k(t('Snip', 'لقطة'), Icons.screenshot_monitor_rounded, const DeckAction(ActionType.hotkey, {'keys': 'win+shift+s'})),
      ]),
      DeckSection(title: t('System', 'النظام'), rows: 1, cols: 3, keys: [
        _k(t('Tasks', 'المهام'), Icons.monitor_heart_rounded, const DeckAction(ActionType.hotkey, {'keys': 'ctrl+shift+esc'})),
        _k(t('Lock', 'قفل'), Icons.lock_rounded, const DeckAction(ActionType.hotkey, {'keys': 'win+l'}), fg: kLime),
        _k(t('Desktop', 'سطح المكتب'), Icons.space_dashboard_rounded, const DeckAction(ActionType.hotkey, {'keys': 'win+d'})),
      ]),
    ].map((s) => s.copyWith(flex: s.rows)).toList(),
  );

  return DeckProject(name: t('OpenDeck', 'أوبن ديك'), pages: [main, media, stream]);
}
