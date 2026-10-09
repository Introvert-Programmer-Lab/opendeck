import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../models/deck_model.dart';

/// Size of the page as designed: the panel turned by the project's rotation.
Size logicalSize(DeckProject p) => p.rotation.isEven
    ? Size(p.panelW.toDouble(), p.panelH.toDouble())
    : Size(p.panelH.toDouble(), p.panelW.toDouble());

bool isLandscape(DeckProject p) => rotationIsLandscape(p, p.rotation);

/// Whether [rotation] turns this project's panel into a landscape page.
bool rotationIsLandscape(DeckProject p, int rotation) => (p.panelW > p.panelH) != rotation.isOdd;

/// One grid cell on a page, filled or empty.
class SlotRect {
  const SlotRect(this.section, this.index, this.rect, this.key);
  final int section;
  final int index;
  final Rect rect;
  final DeckKey? key;
}

class PageLayout {
  const PageLayout(this.size, this.slots, this.header, this.dot, this.sectionTitles);
  final Size size;
  final List<SlotRect> slots;
  final Rect? header;
  final Offset dot; // where the firmware draws its connection dot (logical)
  final List<(Rect, String)> sectionTitles;

  SlotRect? hit(Offset p) {
    for (final s in slots) {
      if (s.rect.contains(p)) return s;
    }
    return null;
  }
}

PageLayout layoutPage(DeckProject project, DeckPage page) {
  final size = logicalSize(project);
  final t = project.theme;
  const pad = 10.0;
  var top = pad;
  Rect? header;
  if (t.showHeader) {
    header = Rect.fromLTWH(pad, pad, size.width - pad * 2, 30);
    top = header.bottom + 6;
  }
  final dot = header != null ? Offset(header.right - 6, header.center.dy) : Offset(size.width - 8, 8);
  final slots = <SlotRect>[];
  final titles = <(Rect, String)>[];
  final totalFlex = page.sections.fold<int>(0, (a, s) => a + (s.flex < 1 ? 1 : s.flex));
  // Portrait stacks sections top to bottom; landscape puts them side by side.
  final horizontal = size.width > size.height;
  final area = Rect.fromLTRB(pad, top, size.width - pad, size.height - pad);
  var cursor = horizontal ? area.left : area.top;
  for (var si = 0; si < page.sections.length; si++) {
    final s = page.sections[si];
    final share = (s.flex < 1 ? 1 : s.flex) / (totalFlex == 0 ? 1 : totalFlex);
    final last = si == page.sections.length - 1;
    final extent = (horizontal ? area.width : area.height) * share;
    var box = horizontal
        ? Rect.fromLTWH(cursor, area.top, extent - (last ? 0 : t.gap), area.height)
        : Rect.fromLTWH(area.left, cursor, area.width, extent - (last ? 0 : t.gap));
    cursor += extent;
    if (s.title.isNotEmpty) {
      titles.add((Rect.fromLTWH(box.left + 2, box.top, box.width - 2, 16), s.title));
      box = Rect.fromLTRB(box.left, box.top + 18, box.right, box.bottom);
    }
    final cw = (box.width - t.gap * (s.cols - 1)) / s.cols;
    final ch = (box.height - t.gap * (s.rows - 1)) / s.rows;
    for (var r = 0; r < s.rows; r++) {
      for (var c = 0; c < s.cols; c++) {
        final i = r * s.cols + c;
        final rect = Rect.fromLTWH(box.left + c * (cw + t.gap), box.top + r * (ch + t.gap), cw, ch);
        slots.add(SlotRect(si, i, _snap(rect), i < s.keys.length ? s.keys[i] : null));
      }
    }
  }
  return PageLayout(size, slots, header, dot, titles);
}

Rect _snap(Rect r) => Rect.fromLTRB(r.left.roundToDouble(), r.top.roundToDouble(), r.right.roundToDouble(), r.bottom.roundToDouble());

/// Logical rect -> native panel rect (the page image is rotated clockwise by
/// rotation*90°). [ls] is the logical page size.
List<int> toNativeRect(Rect r, int rotation, Size ls) {
  final x = r.left.round(), y = r.top.round(), w = r.width.round(), h = r.height.round();
  return switch (rotation & 3) {
    1 => [ls.height.round() - (y + h), x, h, w],
    2 => [ls.width.round() - (x + w), ls.height.round() - (y + h), w, h],
    3 => [y, ls.width.round() - (x + w), h, w],
    _ => [x, y, w, h],
  };
}

List<int> toNativePoint(Offset p, int rotation, Size ls) {
  final r = toNativeRect(Rect.fromLTWH(p.dx, p.dy, 1, 1), rotation, ls);
  return [r[0], r[1]];
}

bool _isRtl(String s) => RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]').hasMatch(s);

/// The logo mark drawn in the page header, loaded once.
class LogoArt {
  static PictureInfo? logo;
  static Future<void>? _loading;

  static Future<void> ensure() => _loading ??= () async {
        final svg = await rootBundle.loadString('assets/logo/opendeck_mark.svg');
        logo = await vg.loadPicture(SvgStringLoader(svg), null);
      }();
}

final Map<String, ui.Image> _imageCache = {};

Future<ui.Image> _decode(Uint8List bytes) async {
  final key = '${bytes.length}:${Object.hashAll(bytes.take(64))}:${Object.hashAll(bytes.skip(bytes.length > 64 ? bytes.length - 64 : 0))}';
  final cached = _imageCache[key];
  if (cached != null) return cached;
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  if (_imageCache.length > 64) _imageCache.clear();
  return _imageCache[key] = img;
}

/// Renders a whole page. `altIds` are toggle keys drawn in their "on" state.
Future<ui.Image> renderPage(DeckProject project, int pageIndex, {Set<String> altIds = const {}}) async {
  await LogoArt.ensure();
  final page = project.pages[pageIndex];
  final layout = layoutPage(project, page);
  final t = project.theme;
  final size = layout.size;

  // Decode every image this page needs before recording.
  final images = <Uint8List, ui.Image>{};
  Future<void> need(Uint8List? b) async {
    if (b != null && !images.containsKey(b)) images[b] = await _decode(b);
  }

  await need(page.backgroundImage);
  for (final k in page.allKeys) {
    await need(k.icon.image);
    await need(k.altIcon.image);
  }

  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Offset.zero & size);

  // Background
  c.drawRect(Offset.zero & size, Paint()..color = Color(page.background ?? t.background));
  if (page.backgroundImage != null) {
    final img = images[page.backgroundImage]!;
    paintImage(canvas: c, rect: Offset.zero & size, image: img, fit: BoxFit.cover, filterQuality: FilterQuality.high);
    c.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, page.backgroundDim.clamp(0, 1)));
  }

  // Header: logo, page name, page dots
  final header = layout.header;
  if (header != null) {
    final logoBox = Rect.fromLTWH(header.left, header.top + 3, 24, 24);
    _drawLogo(c, logoBox, Color(t.accent));
    final rtl = _isRtl(page.name);
    final name = _text(page.name.isEmpty ? project.name : page.name, 13, Color(t.foreground), FontWeight.w600,
        maxWidth: header.width - 110, rtl: rtl);
    name.paint(c, Offset(logoBox.right + 8, header.center.dy - name.height / 2));
    final n = project.pages.length;
    if (n > 1) {
      var x = layout.dot.dx - 16;
      for (var i = n - 1; i >= 0; i--) {
        final current = i == pageIndex;
        final w = current ? 14.0 : 5.0;
        x -= w;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, header.center.dy - 2.5, w, 5), const Radius.circular(3)),
            Paint()..color = current ? Color(t.accent) : Color(t.foreground).withValues(alpha: 0.25));
        x -= 4;
      }
    }
  }

  for (final (rect, title) in layout.sectionTitles) {
    final tp = _text(title.toUpperCase(), 9.5, Color(t.foreground).withValues(alpha: 0.55), FontWeight.w600,
        maxWidth: rect.width, rtl: _isRtl(title), spacing: 1.2);
    tp.paint(c, Offset(_isRtl(title) ? rect.right - tp.width : rect.left, rect.top + 2));
  }

  for (final s in layout.slots) {
    final k = s.key;
    if (k == null) continue;
    _drawKey(c, s.rect, k, t, images, alt: altIds.contains(k.id));
  }

  final pic = rec.endRecording();
  return pic.toImage(size.width.round(), size.height.round());
}

void _drawKey(Canvas c, Rect r, DeckKey k, DeckTheme t, Map<Uint8List, ui.Image> images, {required bool alt}) {
  final useAlt = alt && k.hasAltState;
  final bg = Color((useAlt ? k.altBackground : null) ?? k.background ?? t.keyColor);
  final fg = Color((useAlt ? k.altForeground : null) ?? k.foreground ?? t.foreground);
  final icon = useAlt && !k.altIcon.isNone ? k.altIcon : k.icon;
  final label = useAlt && k.altLabel.isNotEmpty ? k.altLabel : k.label;
  final rr = RRect.fromRectAndRadius(r, Radius.circular(t.cornerRadius));

  c.drawRRect(rr, Paint()..color = bg);
  // soft highlight on the top half
  c.save();
  c.clipRRect(rr);
  c.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.5),
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.center, [
          const Color(0x14FFFFFF),
          const Color(0x00FFFFFF),
        ]));
  c.restore();
  c.drawRRect(rr.deflate(0.5), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0x18FFFFFF));

  final hasLabel = k.showLabel && label.isNotEmpty;
  final labelH = hasLabel ? (t.labelSize * 1.45) : 0.0;
  final iconMax = (r.shortestSide * (hasLabel ? 0.46 : 0.58)).clamp(10.0, 120.0);
  final iconCenter = Offset(r.center.dx, r.top + (r.height - labelH) / 2 + (hasLabel ? 2 : 0));

  if (icon.image != null && images[icon.image] != null) {
    final img = images[icon.image]!;
    final box = Rect.fromCenter(center: iconCenter, width: iconMax * 1.12, height: iconMax * 1.12);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(box.width * 0.22)));
    paintImage(canvas: c, rect: box, image: img, fit: BoxFit.cover, filterQuality: FilterQuality.high);
    c.restore();
  } else if (icon.codePoint != null) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint!),
        style: TextStyle(fontFamily: 'MaterialIcons', fontSize: iconMax, color: fg, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, iconCenter - Offset(tp.width / 2, tp.height / 2));
  }

  if (hasLabel) {
    final tp = _text(label, t.labelSize, fg, FontWeight.w500, maxWidth: r.width - 8, rtl: _isRtl(label), align: TextAlign.center);
    tp.paint(c, Offset(r.center.dx - tp.width / 2, r.bottom - labelH - 4 + (labelH - tp.height) / 2));
  }
}

TextPainter _text(String s, double size, Color color, FontWeight weight,
    {required double maxWidth, bool rtl = false, TextAlign align = TextAlign.start, double spacing = 0}) {
  return TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: rtl ? 'Alexandria' : 'Lexend',
        fontFamilyFallback: const ['Alexandria', 'Lexend'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: 1.15,
      ),
    ),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth < 1 ? 1 : maxWidth);
}

void _drawLogo(Canvas c, Rect box, Color color) {
  final logo = LogoArt.logo;
  if (logo == null) return;
  final s = box.width / logo.size.width;
  c.saveLayer(box.inflate(2), Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn));
  c.translate(box.left, box.top + (box.height - logo.size.height * s) / 2);
  c.scale(s);
  c.drawPicture(logo.picture);
  c.restore();
}

/// RGBA bytes of an image (for encoding off the UI thread).
Future<Uint8List> imageRgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}
