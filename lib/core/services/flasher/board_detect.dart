// Decides which supported board is plugged in, from what the chip reports
// and what answers on the pins each supported board uses for touch and display.
import 'board_probe.dart';
import 'boards.dart';
import 'esp_loader.dart';

/// Everything learned about the plugged-in board.
class ProbeFacts {
  const ProbeFacts({
    required this.chip,
    required this.link,
    required this.flashSize,
    this.touch = const {},
    this.resistive = const {},
    this.controller,
  });

  final ChipFamily chip;
  final UsbLink link;

  /// Bytes, 0 when the flash ID could not be read.
  final int flashSize;

  /// I2C touch buses checked, by [TouchProbe.key]. Null: nothing answered.
  final Map<String, TouchHit?> touch;

  /// XPT2046 checks, by [SpiPins.key].
  final Map<String, bool> resistive;

  /// Display controller read back over SPI, if any was read.
  final String? controller;

  ProbeFacts copyWith({Map<String, TouchHit?>? touch, Map<String, bool>? resistive, String? controller}) => ProbeFacts(
        chip: chip,
        link: link,
        flashSize: flashSize,
        touch: touch ?? this.touch,
        resistive: resistive ?? this.resistive,
        controller: controller ?? this.controller,
      );

  /// Short facts for the UI, e.g. "ESP32-S3", "16 MB flash", "GT911 at 0x5D, 800x480".
  List<String> get summary => [
        chip == ChipFamily.esp32s3 ? 'ESP32-S3' : 'ESP32',
        link == UsbLink.native ? 'native USB' : 'USB-UART bridge',
        if (flashSize > 0) '${flashSize >> 20} MB flash',
        for (final h in touch.values) ?h?.toString(),
        if (resistive.values.any((v) => v)) 'XPT2046 resistive touch',
        ?controller,
      ];
}

enum Unsupported {
  /// Not an ESP32 or ESP32-S3.
  chip,

  /// No supported board has this chip, USB link and flash size.
  hardware,

  /// The chip fits, but nothing answered where a supported board has its touch controller.
  noMatch,
}

class Detection {
  const Detection({this.facts, this.boards = const [], this.family = const [], this.unsupported, this.detail = ''});

  final ProbeFacts? facts;

  /// Boards that match everything that was found. One: identified. Several:
  /// the user picks (they differ in things the probes cannot see, like screen size).
  final List<BoardProfile> boards;

  /// Boards with the same chip, USB link and flash, whatever the probes said.
  final List<BoardProfile> family;
  final Unsupported? unsupported;
  final String detail;

  bool get identified => boards.length == 1;
  bool get supported => boards.isNotEmpty;
}

/// Boards built around the same chip, USB link and flash size as [f].
List<BoardProfile> familyOf(ProbeFacts f, [List<BoardProfile> boards = BoardProfile.all]) => [
      for (final b in boards)
        if (b.chip == f.chip && b.link == f.link && (f.flashSize == 0 || b.flashSize <= f.flashSize)) b,
    ];

bool _sameSize((int, int) a, (int, int) b) => (a.$1 == b.$1 && a.$2 == b.$2) || (a.$1 == b.$2 && a.$2 == b.$1);

/// Whether [f] is consistent with [b]. A board is only accepted when its own
/// touch controller answered: missing evidence counts against it.
bool fits(BoardProfile b, ProbeFacts f) {
  final t = b.touch;
  if (t != null) {
    final hit = f.touch[t.key];
    if (hit == null || !t.addresses.contains(hit.address)) return false;
    final res = hit.resolution;
    if (t.goodix && res != null && !_sameSize(res, b.touchResolution ?? (b.width, b.height))) return false;
  } else {
    final r = b.resistive;
    if (r == null || f.resistive[r.key] != true) return false;
  }
  if (f.controller != null && b.controller != null && f.controller != b.controller) return false;
  if (f.controller != null && !b.controllerReadable) return false;
  return true;
}

Detection decide(ProbeFacts f, [List<BoardProfile> boards = BoardProfile.all]) {
  final family = familyOf(f, boards);
  if (family.isEmpty) return Detection(facts: f, unsupported: Unsupported.hardware);
  final matches = [for (final b in family) if (fits(b, f)) b];
  if (matches.isEmpty) return Detection(facts: f, family: family, unsupported: Unsupported.noMatch);
  return Detection(facts: f, boards: matches, family: family);
}

/// Runs the probes that matter for boards with this chip, link and flash.
/// The loader must be connected. Pins are released afterwards.
Future<ProbeFacts> probeBoard(EspLoader loader, UsbLink link, int flashSize,
    {List<BoardProfile> boards = BoardProfile.all}) async {
  var facts = ProbeFacts(chip: loader.chip, link: link, flashSize: flashSize);
  final family = familyOf(facts, boards);
  if (family.isEmpty) return facts;

  final g = RomGpio(loader, loader.chip);
  // Chip selects of every SPI part on these boards, held high while another one is read.
  final selects = {
    for (final b in family) ...[?b.display?.cs, ?b.resistive?.cs],
  };
  try {
    final buses = <String, List<TouchProbe>>{};
    for (final b in family) {
      if (b.touch != null) buses.putIfAbsent(b.touch!.key, () => []).add(b.touch!);
    }
    final touch = <String, TouchHit?>{};
    for (final probes in buses.values) {
      final p = probes.first;
      touch[p.key] = await probeI2cTouch(
        g,
        sda: p.sda,
        scl: p.scl,
        addresses: {for (final q in probes) ...q.addresses}.toList(),
        reset: probes.map((q) => q.reset).nonNulls.firstOrNull,
      );
    }
    facts = facts.copyWith(touch: touch);

    final xpt = <String, SpiPins>{
      for (final b in family)
        if (b.resistive != null) b.resistive!.key: b.resistive!,
    };
    final resistive = <String, bool>{};
    for (final p in xpt.values) {
      resistive[p.key] = await probeXpt2046(g,
          sclk: p.sclk, mosi: p.mosi, miso: p.miso, cs: p.cs, deselect: [...selects.where((c) => c != p.cs)]);
    }
    facts = facts.copyWith(resistive: resistive);

    // The display ID only matters when it would tell the remaining boards apart.
    final left = decide(facts, boards).boards;
    final display = left.map((b) => b.display).nonNulls.firstOrNull;
    if (display != null && left.map((b) => b.controller).toSet().length > 1) {
      final id = await probeDisplayController(g,
          sclk: display.sclk,
          mosi: display.mosi,
          miso: display.miso,
          cs: display.cs,
          dc: display.dc!,
          deselect: [...selects.where((c) => c != display.cs)]);
      if (id != null) facts = facts.copyWith(controller: id);
    }
  } finally {
    await g.releaseAll();
  }
  return facts;
}
