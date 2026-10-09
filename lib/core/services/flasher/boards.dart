// The boards OpenDeck has firmware for, and how to recognise each one.
import 'esp_loader.dart';

/// How the board's USB-C port reaches the chip.
enum UsbLink {
  /// The ESP32-S3's own USB: the board is also a USB keyboard.
  native,

  /// A USB-UART bridge (CH340, CP2102): serial only, no keyboard.
  bridge,
}

/// A touch controller on I2C, used to recognise the board.
class TouchProbe {
  const TouchProbe({required this.sda, required this.scl, required this.addresses, this.goodix = false, this.reset});
  final int sda, scl;
  final List<int> addresses;

  /// GT911: its configured resolution can be read back to tell panels apart.
  final bool goodix;

  /// Pulsed before probing to wake controllers that sleep (CST816).
  final int? reset;

  String get key => '$sda/$scl';
}

/// Pins of a SPI device: the display (with [dc]) or an XPT2046 touch controller.
class SpiPins {
  const SpiPins({required this.sclk, required this.mosi, required this.miso, required this.cs, this.dc});
  final int sclk, mosi, miso, cs;
  final int? dc;

  String get key => '$sclk/$mosi/$miso/$cs';
}

class BoardProfile {
  const BoardProfile({
    required this.id,
    required this.name,
    required this.inches,
    required this.width,
    required this.height,
    required this.chip,
    required this.link,
    required this.flashSizes,
    this.firmware,
    this.aliases = const [],
    this.touchKind = 'capacitive',
    this.touch,
    this.touchResolution,
    this.resistive,
    this.display,
    this.controller,
    this.verified = false,
    this.stockUrl,
    this.stockSha256,
  });

  final String id;
  final String name;
  final double inches;

  /// Native panel size in pixels.
  final int width, height;
  final ChipFamily chip;
  final UsbLink link;

  /// Flash sizes this board ships with, in bytes.
  final Set<int> flashSizes;

  /// Firmware build to flash, when several boards share one.
  final String? firmware;
  final List<String> aliases;
  final String touchKind;
  final TouchProbe? touch;

  /// What a GT911 on this board reports as its resolution, if it differs from the panel's.
  final (int, int)? touchResolution;

  /// XPT2046 resistive touch controller, for boards without I2C touch.
  final SpiPins? resistive;
  final SpiPins? display;

  /// Display controller (for SPI panels, matched against the ID read back).
  final String? controller;

  /// Tested on real hardware. Other boards are built from their published pinouts.
  final bool verified;

  /// The manufacturer's factory image, pinned by checksum. Null when unknown.
  final String? stockUrl;
  final String? stockSha256;

  String get firmwareId => firmware ?? id;

  /// File name of the merged image in the app bundle and in GitHub releases.
  String get firmwareFile => 'opendeck-$firmwareId.bin';

  bool get hasStockFirmware => stockUrl != null && stockSha256 != null;

  /// Flash size the firmware is built for: the smallest one the board ships with.
  int get flashSize => flashSizes.reduce((a, b) => a < b ? a : b);

  String get title => '$name (${_inch(inches)}")';

  static BoardProfile? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  static const jc3248w535 = BoardProfile(
    id: 'jc3248w535',
    name: 'Guition JC3248W535',
    aliases: ['JC3248W535C', 'JC3248W535EN', 'JC3248W535C_I_Y', 'Guition HMI W5'],
    inches: 3.5,
    width: 320,
    height: 480,
    chip: ChipFamily.esp32s3,
    link: UsbLink.native,
    flashSizes: {_mb16},
    touch: TouchProbe(sda: 4, scl: 8, addresses: [0x3B]),
    verified: true,
    // JC3248W535C_I_Y.bin from Guition's JC3248W535EN data package ("8-Burn operation/Burn files"),
    // a full image written at 0x0. Mirrored in a community repo; the checksum pins the exact file.
    stockUrl: 'https://raw.githubusercontent.com/NorthernMan54/JC3248W535EN/94ffc13bd011e897e82e4097afd272d6932f3cab/'
        'JC3248W535EN/8-Burn%20operation/Burn%20files/JC3248W535C_I_Y.bin',
    stockSha256: '41a39a2fef1a2af92b9d9b42984402445267b4b61a2f4288e7ff428140a14d79',
  );

  static const all = <BoardProfile>[
    jc3248w535,
    BoardProfile(
      id: 'jc4827w543c',
      name: 'Guition JC4827W543C',
      aliases: ['JC4827W543'],
      inches: 4.3,
      width: 480,
      height: 272,
      chip: ChipFamily.esp32s3,
      link: UsbLink.native,
      flashSizes: {_mb4},
      touch: TouchProbe(sda: 8, scl: 4, addresses: [0x5D, 0x14], goodix: true),
    ),
    BoardProfile(
      id: 'es3c28p',
      name: 'LCDWIKI ES3C28P',
      aliases: ['Hosyond ESP32-S3 2.8"'],
      inches: 2.8,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32s3,
      link: UsbLink.native,
      flashSizes: {_mb16},
      touch: TouchProbe(sda: 16, scl: 15, addresses: [0x38], reset: 18),
    ),
    BoardProfile(
      id: 'esp32-8048s043c',
      name: 'Sunton ESP32-8048S043C',
      aliases: ['ESP32-8048S043C_I'],
      inches: 4.3,
      width: 800,
      height: 480,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb16},
      touch: _rgbTouch,
    ),
    BoardProfile(
      id: 'esp32-8048s050c',
      name: 'Sunton ESP32-8048S050C',
      inches: 5,
      width: 800,
      height: 480,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb16},
      touch: _rgbTouch,
    ),
    BoardProfile(
      id: 'jc8048w550c',
      name: 'Guition JC8048W550C',
      firmware: 'esp32-8048s050c',
      inches: 5,
      width: 800,
      height: 480,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb16},
      touch: _rgbTouch,
    ),
    BoardProfile(
      id: 'esp32-8048s070c',
      name: 'Sunton ESP32-8048S070C',
      inches: 7,
      width: 800,
      height: 480,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb16},
      touch: _rgbTouch,
    ),
    BoardProfile(
      id: 'esp32-4827s043c',
      name: 'Sunton ESP32-4827S043C',
      inches: 4.3,
      width: 480,
      height: 272,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb4, _mb16},
      touch: _rgbTouch,
    ),
    BoardProfile(
      id: 'esp32-4848s040c',
      name: 'Guition ESP32-4848S040C',
      aliases: ['ESP32-S3-4848S040', 'ESP32-4848S040C_I_Y_1', 'ESP32-4848S040C_I_Y_3'],
      inches: 4,
      width: 480,
      height: 480,
      chip: ChipFamily.esp32s3,
      link: UsbLink.bridge,
      flashSizes: {_mb16},
      touch: TouchProbe(sda: 19, scl: 45, addresses: [0x5D, 0x14], goodix: true),
    ),
    BoardProfile(
      id: 'esp32-2432s028r',
      name: 'Sunton ESP32-2432S028R',
      aliases: ['Cheap Yellow Display', 'CYD'],
      inches: 2.8,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touchKind: 'resistive',
      resistive: _xptOwnBus,
      display: _cydDisplay,
      controller: 'ILI9341',
    ),
    BoardProfile(
      id: 'esp32-2432s028rv3',
      name: 'Sunton ESP32-2432S028R v3',
      aliases: ['Cheap Yellow Display (USB-C, ST7789)'],
      inches: 2.8,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touchKind: 'resistive',
      resistive: _xptOwnBus,
      display: _cydDisplay,
      controller: 'ST7789',
    ),
    BoardProfile(
      id: 'jc2432w328c',
      name: 'Guition JC2432W328C',
      aliases: ['Capacitive Cheap Yellow Display'],
      inches: 2.8,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touch: _cydTouchCst,
      display: _cydDisplay,
      controller: 'ST7789',
    ),
    BoardProfile(
      id: 'esp32-2432s024c',
      name: 'Sunton ESP32-2432S024C',
      inches: 2.4,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touch: _cydTouchCst,
      display: _cydDisplay,
      controller: 'ILI9341',
    ),
    BoardProfile(
      id: 'esp32-2432s024r',
      name: 'Sunton ESP32-2432S024R',
      inches: 2.4,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touchKind: 'resistive',
      resistive: _xptSharedBus,
      display: _cydDisplay,
      controller: 'ILI9341',
    ),
    BoardProfile(
      id: 'esp32-2432s032c',
      name: 'Sunton ESP32-2432S032C',
      inches: 3.2,
      width: 240,
      height: 320,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touch: _cydTouchGt911,
      display: _cydDisplay,
      controller: 'ST7789',
    ),
    BoardProfile(
      id: 'esp32-3248s035c',
      name: 'Sunton ESP32-3248S035C',
      inches: 3.5,
      width: 320,
      height: 480,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touch: _cydTouchGt911,
      display: _cydDisplay,
      controller: 'ST7796',
    ),
    BoardProfile(
      id: 'esp32-3248s035r',
      name: 'Sunton ESP32-3248S035R',
      inches: 3.5,
      width: 320,
      height: 480,
      chip: ChipFamily.esp32,
      link: UsbLink.bridge,
      flashSizes: {_mb4},
      touchKind: 'resistive',
      resistive: _xptSharedBus,
      display: _cydDisplay,
      controller: 'ST7796',
    ),
  ];
}

const _mb4 = 4 << 20;
const _mb16 = 16 << 20;

const _rgbTouch = TouchProbe(sda: 19, scl: 20, addresses: [0x5D, 0x14], goodix: true);
const _cydTouchGt911 = TouchProbe(sda: 33, scl: 32, addresses: [0x5D, 0x14], goodix: true, reset: 25);
const _cydTouchCst = TouchProbe(sda: 33, scl: 32, addresses: [0x15], reset: 25);
const _cydDisplay = SpiPins(sclk: 14, mosi: 13, miso: 12, cs: 15, dc: 2);
const _xptOwnBus = SpiPins(sclk: 25, mosi: 32, miso: 39, cs: 33);
const _xptSharedBus = SpiPins(sclk: 14, mosi: 13, miso: 12, cs: 33);

String _inch(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
