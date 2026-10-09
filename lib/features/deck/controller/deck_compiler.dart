import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import '../models/deck_model.dart';
import 'deck_renderer.dart';
import 'hid_macro.dart';

class CompiledDeck {
  const CompiledDeck(this.files, this.quality, this.includesProject);
  final Map<String, Uint8List> files;
  final int quality;
  final bool includesProject;
  int get totalBytes => files.values.fold(0, (a, b) => a + b.length);
}

class DeckTooLargeException implements Exception {
  DeckTooLargeException(this.bytes, this.budget);
  final int bytes, budget;
  @override
  String toString() => 'Deck needs ${bytes ~/ 1024} KB but the board has ${budget ~/ 1024} KB free';
}

class _Raster {
  _Raster(this.name, this.rgba, this.w, this.h);
  final String name;
  final Uint8List rgba;
  final int w, h;
}

/// RGB565 the way the firmware stores colors.
int rgb565(int argb) => (((argb >> 16) & 0xF8) << 8) | (((argb >> 8) & 0xFC) << 3) | ((argb & 0xFF) >> 3);

/// Renders and encodes the whole project into the files the firmware reads.
/// [budgetBytes]: free storage on the board (we keep room for staging).
Future<CompiledDeck> compileDeck(DeckProject project, {int? budgetBytes, void Function(String step)? onStep}) async {
  final rot = project.rotation & 3;
  final rasters = <_Raster>[];
  final pagesJson = <Map<String, dynamic>>[];

  for (var pi = 0; pi < project.pages.length; pi++) {
    onStep?.call('page ${pi + 1}/${project.pages.length}');
    final page = project.pages[pi];
    final layout = layoutPage(project, page);
    final base = await renderPage(project, pi);
    rasters.add(_Raster('p$pi.jpg', await imageRgba(base), base.width, base.height));

    final toggles = layout.slots.where((s) => s.key?.hasAltState ?? false).toList();
    Uint8List? altRgba;
    if (toggles.isNotEmpty) {
      final alt = await renderPage(project, pi, altIds: toggles.map((s) => s.key!.id).toSet());
      altRgba = await imageRgba(alt);
    }

    final keys = <Map<String, dynamic>>[];
    var n = 0;
    for (final s in layout.slots) {
      final k = s.key;
      if (k == null) continue;
      final entry = <String, dynamic>{'id': k.id, 'r': toNativeRect(s.rect, rot, layout.size)};
      final dev = k.action.toDeviceJson();
      if (dev != null) entry['dev'] = dev;
      final hid = hidMacroFor(k.action);
      if (hid != null) entry['hid'] = hid;
      if (k.hasAltState && altRgba != null) {
        final name = 'p${pi}_${n}a.jpg';
        rasters.add(_cropRaster(name, altRgba, base.width, s.rect));
        entry['alt'] = name;
      }
      keys.add(entry);
      n++;
    }
    pagesJson.add({'img': 'p$pi.jpg', 'keys': keys});
  }

  final first = layoutPage(project, project.pages.first);
  final dot = toNativePoint(first.dot, rot, first.size);
  final manifest = {
    'v': 1,
    'rot': rot,
    'bright': project.brightness,
    'acc': rgb565(project.theme.accent),
    if (project.theme.showHeader) 'dot': dot,
    'start': 0,
    'pages': pagesJson,
  };

  final projectBytes = utf8.encode(jsonEncode(project.toJson()));
  final budget = budgetBytes ?? 6 * 1024 * 1024;
  final qualities = project.autoQuality
      ? [for (var q = project.jpegQuality; q >= 30; q -= 8) q]
      : [project.jpegQuality];

  for (final q in qualities) {
    onStep?.call('encoding q$q');
    final encoded = await Isolate.run(() => {
          for (final r in rasters) r.name: _encode(r, rot, q),
        });
    final files = <String, Uint8List>{...encoded};
    final imagesBytes = files.values.fold<int>(0, (a, b) => a + b.length);
    // project.json lets another copy of the app (phone/PC) pull this deck back
    final withProject = imagesBytes + projectBytes.length <= budget && projectBytes.length < 2 * 1024 * 1024;
    if (withProject) files['project.json'] = Uint8List.fromList(projectBytes);
    files['deck.json'] = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    final total = files.values.fold<int>(0, (a, b) => a + b.length);
    if (total <= budget) return CompiledDeck(files, q, withProject);
    if (q == qualities.last) throw DeckTooLargeException(total, budget);
  }
  throw StateError('unreachable');
}

_Raster _cropRaster(String name, Uint8List rgba, int fullW, Rect r) {
  final x0 = r.left.round(), y0 = r.top.round(), w = r.width.round(), h = r.height.round();
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final src = ((y0 + y) * fullW + x0) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, rgba, src);
  }
  return _Raster(name, out, w, h);
}

Uint8List _encode(_Raster r, int rot, int quality) {
  var im = img.Image.fromBytes(width: r.w, height: r.h, bytes: r.rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  if (rot != 0) im = img.copyRotate(im, angle: 90 * rot);
  // 4:4:4 keeps thin colored edges (lime icons on dark) crisp; drop to 4:2:0 when squeezing.
  return img.encodeJpg(im, quality: quality, chroma: quality >= 70 ? img.JpegChroma.yuv444 : img.JpegChroma.yuv420);
}
