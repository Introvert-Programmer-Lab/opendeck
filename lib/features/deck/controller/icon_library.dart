import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

/// Official brand icons (Simple Icons, CC0): monochrome vector + brand color. Bundled offline.
class BrandIcon {
  const BrandIcon(this.title, this.slug, this.hex, this.path);
  final String title, slug, hex, path;

  Color get color => Color(0xFF000000 | int.parse(hex, radix: 16));

  /// Brand color, unless it's too dark to read on a dark key (then white).
  Color get displayColor => color.computeLuminance() < 0.06 ? const Color(0xFFFFFFFF) : color;

  String svg([Color? c]) {
    final col = (c ?? displayColor).toARGB32() & 0xFFFFFF;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#${col.toRadixString(16).padLeft(6, '0')}" d="$path"/></svg>';
  }
}

/// Full-color official app icons (homarr-labs Dashboard Icons, Apache-2.0).
/// Only the index is bundled; images download on demand and are cached.
class AppIcon {
  const AppIcon(this.name, this.base, this.aliases);
  final String name, base;
  final List<String> aliases;

  String get title => name.split('-').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  String get pngUrl => 'https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/$name.png';
}

class IconLibrary {
  IconLibrary._();
  static final instance = IconLibrary._();

  Future<List<BrandIcon>>? _brands;
  Future<List<AppIcon>>? _apps;

  Future<List<BrandIcon>> brands() => _brands ??= () async {
        final gz = await rootBundle.load('assets/icons/simple_icons.json.gz');
        final rows = jsonDecode(utf8.decode(gzip.decode(gz.buffer.asUint8List()))) as List;
        return [for (final r in rows) BrandIcon(r[0], r[1], r[2], r[3])];
      }();

  Future<List<AppIcon>> apps() => _apps ??= () async {
        final gz = await rootBundle.load('assets/icons/dashboard_icons.json.gz');
        final rows = jsonDecode(utf8.decode(gzip.decode(gz.buffer.asUint8List()))) as List;
        return [for (final r in rows) AppIcon(r[0], r[1], (r[2] as List).cast<String>())];
      }();

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int _score(String q, String name) {
    final n = _norm(name);
    if (n == q) return 0;
    if (n.startsWith(q)) return 1;
    if (n.contains(q)) return 2;
    return -1;
  }

  Future<List<BrandIcon>> searchBrands(String query, {int limit = 300}) async {
    final all = await brands();
    final q = _norm(query);
    if (q.isEmpty) return all.take(limit).toList();
    final hits = <(int, BrandIcon)>[];
    for (final b in all) {
      final sc = [_score(q, b.title), _score(q, b.slug)].where((x) => x >= 0).fold<int>(-1, (a, x) => a < 0 || x < a ? x : a);
      if (sc >= 0) hits.add((sc, b));
    }
    hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.title.length - b.$2.title.length);
    return hits.take(limit).map((e) => e.$2).toList();
  }

  Future<List<AppIcon>> searchApps(String query, {int limit = 300}) async {
    final all = await apps();
    final q = _norm(query);
    if (q.isEmpty) return all.take(limit).toList();
    final hits = <(int, AppIcon)>[];
    for (final a in all) {
      var best = -1;
      for (final n in [a.name, ...a.aliases]) {
        final sc = _score(q, n);
        if (sc >= 0 && (best < 0 || sc < best)) best = sc;
      }
      if (best >= 0) hits.add((best, a));
    }
    hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.name.length - b.$2.name.length);
    return hits.take(limit).map((e) => e.$2).toList();
  }

  /// Brand logo rendered to a transparent PNG, ready to use as a key icon.
  Future<Uint8List> brandPng(BrandIcon b, {Color? color, int size = 160}) async {
    final info = await vg.loadPicture(SvgStringLoader(b.svg(color)), null);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final s = size / info.size.width;
    c.scale(s);
    c.drawPicture(info.picture);
    final img = await rec.endRecording().toImage(size, size);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  /// Full-color app icon PNG (downloaded once, then cached on disk).
  Future<Uint8List?> appPng(AppIcon a) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}icon_cache');
    final f = File('${dir.path}${Platform.pathSeparator}${a.name}.png');
    if (await f.exists()) return f.readAsBytes();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(a.pngUrl));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(res);
      client.close();
      await dir.create(recursive: true);
      await f.writeAsBytes(bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
