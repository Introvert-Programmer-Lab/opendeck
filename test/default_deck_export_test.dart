// Renders the default deck with the real fonts and writes:
//   build/deck_preview/*.png              previews of every page (always)
//   firmware/fs_image/<WxH>/deck/*        the deck baked into the firmware for each screen size (OPENDECK_EXPORT=1)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opendeck/features/deck/controller/deck_compiler.dart';
import 'package:opendeck/features/deck/controller/deck_renderer.dart';
import 'package:opendeck/features/deck/controller/default_deck.dart';
import 'package:opendeck/features/deck/models/deck_model.dart';

/// Screen sizes the firmware builds for (firmware/boards/*/board.cmake BOARD_DECK).
const _panels = [(320, 480), (240, 320), (480, 272), (480, 480), (800, 480)];

/// The default deck laid out for a panel, in the panel's own orientation.
DeckProject _forPanel(DeckProject p, int w, int h) {
  final sized = p.copyWith(panelW: w, panelH: h);
  if (!isLandscape(sized)) return sized;
  return sized.copyWith(pages: [
    for (final page in sized.pages)
      page.copyWith(sections: [for (final s in page.sections) s.copyWith(rows: s.cols, cols: s.rows)]),
  ]);
}

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Dev/flutter/flutter';
  await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await _font('Lexend', ['assets/fonts/Lexend-Regular.ttf', 'assets/fonts/Lexend-Medium.ttf', 'assets/fonts/Lexend-SemiBold.ttf']);
  await _font('Alexandria', ['assets/fonts/Alexandria-Regular.ttf', 'assets/fonts/Alexandria-Medium.ttf']);
}

void main() {
  test('rotation maps logical rects onto the clockwise-rotated panel', () {
    // A 2x1 image rotated 90° clockwise: the left pixel ends up on top.
    final im = img.Image(width: 2, height: 1);
    im.setPixelRgb(0, 0, 255, 0, 0);
    final r = img.copyRotate(im, angle: 90);
    expect(r.width, 1);
    expect(r.getPixel(0, 0).r, 255);
    // Logical landscape 480x320, rect at top-left -> native portrait top-right.
    const land = ui.Size(480, 320), port = ui.Size(320, 480);
    expect(toNativeRect(const ui.Rect.fromLTWH(0, 0, 100, 50), 1, land), [270, 0, 50, 100]);
    expect(toNativeRect(const ui.Rect.fromLTWH(0, 0, 100, 50), 3, land), [0, 380, 50, 100]);
    expect(toNativeRect(const ui.Rect.fromLTWH(0, 0, 100, 50), 2, port), [220, 430, 100, 50]);
  });

  test('orientation follows the panel: rotation 0 on an 800x480 panel is landscape', () {
    const wide = DeckProject(panelW: 800, panelH: 480);
    expect(isLandscape(wide), isTrue);
    expect(isLandscape(wide.copyWith(rotation: 1)), isFalse);
    expect(logicalSize(wide.copyWith(rotation: 1)), const ui.Size(480, 800));
    expect(isLandscape(const DeckProject()), isFalse);
    final j = DeckProject.fromJson(wide.toJson());
    expect((j.panelW, j.panelH), (800, 480));
  });

  testWidgets('render and export default deck', (tester) async {
    await tester.runAsync(() async {
      await loadFonts();
      for (final arabic in [false, true]) {
        final project = await buildDefaultDeck(arabic: arabic);
        final dir = Directory('build/deck_preview')..createSync(recursive: true);
        for (var i = 0; i < project.pages.length; i++) {
          final toggles = project.pages[i].allKeys.where((k) => k.hasAltState).map((k) => k.id).toSet();
          for (final alt in [false, true]) {
            if (alt && toggles.isEmpty) continue;
            final image = await renderPage(project, i, altIds: alt ? toggles : {});
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${dir.path}/${arabic ? 'ar' : 'en'}_p$i${alt ? '_on' : ''}.png').writeAsBytesSync(png!.buffer.asUint8List());
          }
        }
        // landscape variant: grids transposed, sections side by side
        final land = project.copyWith(rotation: 1, pages: [
          for (final p in project.pages)
            p.copyWith(sections: [for (final s in p.sections) s.copyWith(rows: s.cols, cols: s.rows)]),
        ]);
        for (var i = 0; i < land.pages.length; i++) {
          final image = await renderPage(land, i);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/${arabic ? 'ar' : 'en'}_land_p$i.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
        expect((await compileDeck(land)).files['p0.jpg'], isNotNull);
        final compiled = await compileDeck(project);
        // ignore: avoid_print
        print('${arabic ? 'ar' : 'en'}: ${compiled.files.length} files, ${compiled.totalBytes ~/ 1024} KB at q${compiled.quality}');
        expect(compiled.files.containsKey('deck.json'), isTrue);
        for (final (w, h) in _panels) {
          final sized = _forPanel(project, w, h);
          final first = await renderPage(sized, 0);
          expect((first.width, first.height), (w, h));
          final png = await first.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/${arabic ? 'ar' : 'en'}_${w}x${h}_p0.png').writeAsBytesSync(png!.buffer.asUint8List());
          if (arabic || Platform.environment['OPENDECK_EXPORT'] != '1') continue;
          final files = (await compileDeck(sized)).files;
          final out = Directory('firmware/fs_image/${w}x$h/deck');
          if (out.existsSync()) out.deleteSync(recursive: true);
          out.createSync(recursive: true);
          files.forEach((name, bytes) => File('${out.path}/$name').writeAsBytesSync(bytes));
        }
      }
    });
  });
}
