import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'deck_action.dart';

String newId() {
  final r = Random();
  return 'k${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
}

int _c(dynamic v, int def) => v is int ? v : (v is String ? int.tryParse(v) ?? def : def);

/// The icon shown on a key: a Material icon glyph or a user image (PNG bytes,
/// already downscaled so the project stays small).
class KeyIcon {
  const KeyIcon.glyph(this.codePoint) : image = null;
  const KeyIcon.image(this.image) : codePoint = null;
  const KeyIcon.none() : codePoint = null, image = null;

  final int? codePoint;
  final Uint8List? image;

  bool get isNone => codePoint == null && image == null;

  Map<String, dynamic> toJson() => {
        if (codePoint != null) 'glyph': codePoint,
        if (image != null) 'image': base64Encode(image!),
      };

  factory KeyIcon.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const KeyIcon.none();
    if (j['image'] is String) return KeyIcon.image(base64Decode(j['image']));
    if (j['glyph'] is int) return KeyIcon.glyph(j['glyph']);
    return const KeyIcon.none();
  }
}

class DeckKey {
  const DeckKey({
    required this.id,
    this.label = '',
    this.icon = const KeyIcon.none(),
    this.altIcon = const KeyIcon.none(),
    this.altLabel = '',
    this.background,
    this.foreground,
    this.altBackground,
    this.altForeground,
    this.showLabel = true,
    this.action = const DeckAction.none(),
  });

  final String id;
  final String label;
  final KeyIcon icon;
  /// Toggle keys ("on" state, e.g. mic muted) use these when set.
  final KeyIcon altIcon;
  final String altLabel;
  final int? background; // ARGB; null = page key color
  final int? foreground; // icon + label color; null = page default
  final int? altBackground;
  final int? altForeground;
  final bool showLabel;
  final DeckAction action;

  bool get hasAltState => action.type.isToggle;

  DeckKey copyWith({
    String? label,
    KeyIcon? icon,
    KeyIcon? altIcon,
    String? altLabel,
    int? Function()? background,
    int? Function()? foreground,
    int? Function()? altBackground,
    int? Function()? altForeground,
    bool? showLabel,
    DeckAction? action,
  }) =>
      DeckKey(
        id: id,
        label: label ?? this.label,
        icon: icon ?? this.icon,
        altIcon: altIcon ?? this.altIcon,
        altLabel: altLabel ?? this.altLabel,
        background: background != null ? background() : this.background,
        foreground: foreground != null ? foreground() : this.foreground,
        altBackground: altBackground != null ? altBackground() : this.altBackground,
        altForeground: altForeground != null ? altForeground() : this.altForeground,
        showLabel: showLabel ?? this.showLabel,
        action: action ?? this.action,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': icon.toJson(),
        'altIcon': altIcon.toJson(),
        'altLabel': altLabel,
        'bg': background,
        'fg': foreground,
        'altBg': altBackground,
        'altFg': altForeground,
        'showLabel': showLabel,
        'action': action.toJson(),
      };

  factory DeckKey.fromJson(Map<String, dynamic> j) => DeckKey(
        id: j['id'] ?? newId(),
        label: j['label'] ?? '',
        icon: KeyIcon.fromJson(j['icon']),
        altIcon: KeyIcon.fromJson(j['altIcon']),
        altLabel: j['altLabel'] ?? '',
        background: j['bg'],
        foreground: j['fg'],
        altBackground: j['altBg'],
        altForeground: j['altFg'],
        showLabel: j['showLabel'] ?? true,
        action: DeckAction.fromJson(j['action']),
      );
}

/// A grid region of a page. Pages stack sections vertically; `flex` sets each
/// section's share of the height.
class DeckSection {
  const DeckSection({this.title = '', this.rows = 2, this.cols = 3, this.flex = 1, this.keys = const []});

  final String title;
  final int rows;
  final int cols;
  final int flex;
  /// Row-major, length rows*cols; null = empty slot.
  final List<DeckKey?> keys;

  DeckSection copyWith({String? title, int? rows, int? cols, int? flex, List<DeckKey?>? keys}) {
    final r = rows ?? this.rows, c = cols ?? this.cols;
    var k = keys ?? this.keys;
    if (r * c != k.length) {
      k = List<DeckKey?>.generate(r * c, (i) => i < k.length ? k[i] : null);
    }
    return DeckSection(title: title ?? this.title, rows: r, cols: c, flex: flex ?? this.flex, keys: k);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'rows': rows,
        'cols': cols,
        'flex': flex,
        'keys': keys.map((k) => k?.toJson()).toList(),
      };

  factory DeckSection.fromJson(Map<String, dynamic> j) {
    final rows = _c(j['rows'], 2), cols = _c(j['cols'], 3);
    final raw = (j['keys'] as List?) ?? const [];
    return DeckSection(
      title: j['title'] ?? '',
      rows: rows,
      cols: cols,
      flex: _c(j['flex'], 1),
      keys: List<DeckKey?>.generate(
          rows * cols, (i) => i < raw.length && raw[i] != null ? DeckKey.fromJson(Map<String, dynamic>.from(raw[i])) : null),
    );
  }
}

class DeckPage {
  const DeckPage({
    required this.id,
    this.name = '',
    this.sections = const [],
    this.background,
    this.backgroundImage,
    this.backgroundDim = 0.35,
  });

  final String id;
  final String name;
  final List<DeckSection> sections;
  final int? background; // null = theme background
  final Uint8List? backgroundImage; // JPEG/PNG bytes, already fitted to the screen
  final double backgroundDim; // dark overlay over a background image, 0..1

  Iterable<DeckKey> get allKeys sync* {
    for (final s in sections) {
      for (final k in s.keys) {
        if (k != null) yield k;
      }
    }
  }

  DeckPage copyWith({
    String? name,
    List<DeckSection>? sections,
    int? Function()? background,
    Uint8List? Function()? backgroundImage,
    double? backgroundDim,
  }) =>
      DeckPage(
        id: id,
        name: name ?? this.name,
        sections: sections ?? this.sections,
        background: background != null ? background() : this.background,
        backgroundImage: backgroundImage != null ? backgroundImage() : this.backgroundImage,
        backgroundDim: backgroundDim ?? this.backgroundDim,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sections': sections.map((s) => s.toJson()).toList(),
        'bg': background,
        if (backgroundImage != null) 'bgImage': base64Encode(backgroundImage!),
        'bgDim': backgroundDim,
      };

  factory DeckPage.fromJson(Map<String, dynamic> j) => DeckPage(
        id: j['id'] ?? newId(),
        name: j['name'] ?? '',
        sections: ((j['sections'] as List?) ?? const [])
            .map((s) => DeckSection.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        background: j['bg'],
        backgroundImage: j['bgImage'] is String ? base64Decode(j['bgImage']) : null,
        backgroundDim: (j['bgDim'] as num?)?.toDouble() ?? 0.35,
      );
}

/// Look shared by every page.
class DeckTheme {
  const DeckTheme({
    this.background = 0xFF0A100E,
    this.keyColor = 0xFF141D19,
    this.foreground = 0xFFFBFFE9,
    this.accent = 0xFFCCFF00,
    this.cornerRadius = 16,
    this.gap = 8,
    this.showHeader = true,
    this.labelSize = 11,
  });

  final int background;
  final int keyColor;
  final int foreground;
  final int accent;
  final double cornerRadius;
  final double gap;
  final bool showHeader;
  final double labelSize;

  DeckTheme copyWith({
    int? background,
    int? keyColor,
    int? foreground,
    int? accent,
    double? cornerRadius,
    double? gap,
    bool? showHeader,
    double? labelSize,
  }) =>
      DeckTheme(
        background: background ?? this.background,
        keyColor: keyColor ?? this.keyColor,
        foreground: foreground ?? this.foreground,
        accent: accent ?? this.accent,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        gap: gap ?? this.gap,
        showHeader: showHeader ?? this.showHeader,
        labelSize: labelSize ?? this.labelSize,
      );

  Map<String, dynamic> toJson() => {
        'bg': background,
        'key': keyColor,
        'fg': foreground,
        'accent': accent,
        'radius': cornerRadius,
        'gap': gap,
        'header': showHeader,
        'labelSize': labelSize,
      };

  factory DeckTheme.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const DeckTheme();
    const d = DeckTheme();
    return DeckTheme(
      background: j['bg'] ?? d.background,
      keyColor: j['key'] ?? d.keyColor,
      foreground: j['fg'] ?? d.foreground,
      accent: j['accent'] ?? d.accent,
      cornerRadius: (j['radius'] as num?)?.toDouble() ?? d.cornerRadius,
      gap: (j['gap'] as num?)?.toDouble() ?? d.gap,
      showHeader: j['header'] ?? d.showHeader,
      labelSize: (j['labelSize'] as num?)?.toDouble() ?? d.labelSize,
    );
  }
}

/// Rotation is clockwise from the panel's native orientation: 0 = native,
/// 1 = 90°, 2 = 180°, 3 = 270°.
class DeckProject {
  const DeckProject({
    this.name = 'My Deck',
    this.pages = const [],
    this.theme = const DeckTheme(),
    this.panelW = 320,
    this.panelH = 480,
    this.rotation = 0,
    this.brightness = 200,
    this.jpegQuality = 85,
    this.autoQuality = true,
  });

  final String name;
  final List<DeckPage> pages;
  final DeckTheme theme;

  /// Native size of the board's screen, as its firmware reports it.
  final int panelW, panelH;
  final int rotation;
  final int brightness;
  final int jpegQuality; // 30..95
  final bool autoQuality; // lower quality automatically if the deck does not fit

  DeckKey? keyById(String id) {
    for (final p in pages) {
      for (final k in p.allKeys) {
        if (k.id == id) return k;
      }
    }
    return null;
  }

  DeckProject copyWith({
    String? name,
    List<DeckPage>? pages,
    DeckTheme? theme,
    int? panelW,
    int? panelH,
    int? rotation,
    int? brightness,
    int? jpegQuality,
    bool? autoQuality,
  }) =>
      DeckProject(
        name: name ?? this.name,
        pages: pages ?? this.pages,
        theme: theme ?? this.theme,
        panelW: panelW ?? this.panelW,
        panelH: panelH ?? this.panelH,
        rotation: rotation ?? this.rotation,
        brightness: brightness ?? this.brightness,
        jpegQuality: jpegQuality ?? this.jpegQuality,
        autoQuality: autoQuality ?? this.autoQuality,
      );

  Map<String, dynamic> toJson() => {
        'format': 1,
        'name': name,
        'pages': pages.map((p) => p.toJson()).toList(),
        'theme': theme.toJson(),
        'panel': [panelW, panelH],
        'rotation': rotation,
        'brightness': brightness,
        'quality': jpegQuality,
        'autoQuality': autoQuality,
      };

  factory DeckProject.fromJson(Map<String, dynamic> j) => DeckProject(
        name: j['name'] ?? 'My Deck',
        pages: ((j['pages'] as List?) ?? const []).map((p) => DeckPage.fromJson(Map<String, dynamic>.from(p))).toList(),
        theme: DeckTheme.fromJson(j['theme'] == null ? null : Map<String, dynamic>.from(j['theme'])),
        panelW: j['panel'] is List && (j['panel'] as List).length == 2 ? _c((j['panel'] as List)[0], 320) : 320,
        panelH: j['panel'] is List && (j['panel'] as List).length == 2 ? _c((j['panel'] as List)[1], 480) : 480,
        rotation: _c(j['rotation'], 0),
        brightness: _c(j['brightness'], 200),
        jpegQuality: _c(j['quality'], 85),
        autoQuality: j['autoQuality'] ?? true,
      );
}
