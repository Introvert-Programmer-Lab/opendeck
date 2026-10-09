// Renders the editor at desktop/mobile sizes (EN + AR) with real fonts and
// writes PNGs to build/ui_shots/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/deck_client.dart';
import 'package:opendeck/core/theme/app_theme.dart';
import 'package:opendeck/features/deck/controller/default_deck.dart';
import 'package:opendeck/features/deck/models/deck_model.dart';
import 'package:opendeck/features/deck/pages/editor_page.dart';
import 'package:opendeck/features/deck/providers/project_provider.dart';
import 'package:opendeck/features/device/providers/device_provider.dart';
import 'package:opendeck/core/services/flasher/firmware_flasher.dart';
import 'package:opendeck/core/widgets/common_widgets.dart';
import 'package:opendeck/features/onboarding/pages/onboarding_page.dart';
import 'package:opendeck/features/onboarding/providers/flash_provider.dart';
import 'package:opendeck/features/onboarding/widgets/flash_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

class _Project extends ProjectNotifier {
  _Project(this.p);
  final DeckProject p;
  @override
  DeckProject build() => p;
}

class _Device extends DeviceController {
  @override
  DeviceState build() => DeviceState(
        status: LinkStatus.connected,
        label: 'COM6',
        isUsb: true,
        info: DeviceInfo.fromJson({
          'fw': '0.1.0',
          'board': 'JC3248W535',
          'name': 'OpenDeck',
          'w': 320,
          'h': 480,
          'fs_total': 13565952,
          'fs_used': 270336,
          'psram_free': 7749444,
          'pages': 3,
          'page': 0,
          'wifi': {'ap': true, 'connected': false, 'ssid': 'OpenDeck-2844', 'ip': '192.168.4.1'},
        }),
      );
}

class _Flashing extends FlashController {
  @override
  FlashState build() => const FlashState(running: true, progress: FlashProgress(FlashStage.write, fraction: 0.42));
}

void main() {
  final shots = <(String, Size, String, int, bool)>[
    ('wide_en', const Size(1440, 900), 'en', 0, false),
    ('wide_en_landscape', const Size(1440, 900), 'en', 1, false),
    ('wide_en_key', const Size(1440, 900), 'en', 0, true),
    ('wide_ar', const Size(1440, 900), 'ar', 0, false),
    ('mobile_en', const Size(390, 844), 'en', 0, false),
    ('setup_en', const Size(1100, 760), 'en', 0, false),
    ('setup_ar', const Size(1100, 760), 'ar', 0, false),
    ('setup_flash_en', const Size(1100, 760), 'en', 0, false),
  ];

  for (final (name, size, lang, rot, selectKey) in shots) {
    testWidgets('screen $name', (tester) async {
      SharedPreferences.setMockInitialValues({'lang': lang});
      late DeckProject project;
      await tester.runAsync(() async {
        final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Dev/flutter/flutter';
        await _font('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
        await _font('Lexend', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Lexend-$w.ttf']);
        await _font('Alexandria', [for (final w in ['Regular', 'Medium', 'Bold']) 'assets/fonts/Alexandria-$w.ttf']);
        await _font('Unbounded', ['assets/fonts/Unbounded-SemiBold.ttf']);
        project = await buildDefaultDeck(arabic: lang == 'ar');
        if (rot == 1) {
          project = project.copyWith(rotation: 1, pages: [
            for (final p in project.pages) p.copyWith(sections: [for (final s in p.sections) s.copyWith(rows: s.cols, cols: s.rows, flex: s.rows)]),
          ]);
        }
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final container = ProviderContainer(overrides: [
        projectProvider.overrideWith(() => _Project(project)),
        deviceProvider.overrideWith(_Device.new),
        if (name == 'setup_flash_en') flashProvider.overrideWith(_Flashing.new),
      ]);
      addTearDown(container.dispose);
      if (selectKey) container.read(selectionProvider.notifier).slot(0, 0);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Locale(lang)),
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: switch (name) {
              'setup_flash_en' => const Scaffold(
                  body: Center(child: SizedBox(width: 520, child: Panel(padding: EdgeInsets.all(20), child: FlashPanel()))),
                ),
              _ when name.startsWith('setup') => const OnboardingPage(),
              _ => const EditorPage(),
            },
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/ui_shots').createSync(recursive: true);
        File('build/ui_shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    });
  }
}
