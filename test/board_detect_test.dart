// Board identification: the decision rules, and the pin probes run against
// a simulated chip with a touch controller wired to its GPIOs.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/flasher/board_detect.dart';
import 'package:opendeck/core/services/flasher/board_probe.dart';
import 'package:opendeck/core/services/flasher/esp_loader.dart';
import 'package:opendeck/core/services/flasher/firmware_flasher.dart';
import 'package:opendeck/core/services/flasher/flash_port.dart';

import 'fake_rom.dart';

/// ESP32-S3 GPIO registers driving open-drain lines, with I2C devices attached.
class SimBoard {
  SimBoard(this.rom, this.devices) {
    rom.onWriteReg = _write;
    rom.onReadReg = (addr) => addr == _base + 0x3C ? _in(0) : (addr == _base + 0x40 ? _in(1) : null);
  }

  static const _base = 0x60004000;
  final FakeRom rom;
  final List<I2cDevice> devices;
  final _out = [0, 0], _enable = [0, 0];

  bool level(int pin) {
    final bank = pin >> 5, bit = 1 << (pin & 31);
    if (_enable[bank] & bit != 0) return _out[bank] & bit != 0;
    return !devices.any((d) => d.sda == pin && d.driveLow);
  }

  int _in(int bank) {
    var v = 0;
    for (var i = 0; i < 32; i++) {
      if (level(bank * 32 + i)) v |= 1 << i;
    }
    return v;
  }

  void _write(int addr, int value) {
    final before = {for (final d in devices) d: (level(d.sda), level(d.scl))};
    final off = addr - _base;
    for (final (reg, bank) in [(0x08, 0), (0x14, 1)]) {
      if (off == reg) _out[bank] |= value;
      if (off == reg + 4) _out[bank] &= ~value;
    }
    for (final (reg, bank) in [(0x24, 0), (0x30, 1)]) {
      if (off == reg) _enable[bank] |= value;
      if (off == reg + 4) _enable[bank] &= ~value;
    }
    for (final d in devices) {
      final (sda0, scl0) = before[d]!;
      final sda = level(d.sda), scl = level(d.scl);
      if (scl0 && scl && sda0 != sda) {
        sda ? d.stop() : d.start();
      } else if (!scl0 && scl) {
        d.sclRise(sda);
      } else if (scl0 && !scl) {
        d.sclFall();
      }
    }
  }
}

/// An I2C device with 16-bit register addresses, like the GT911.
class I2cDevice {
  I2cDevice(this.sda, this.scl, this.address, [this.mem = const {}]);
  final int sda, scl, address;
  final Map<int, int> mem;
  bool driveLow = false;

  bool _active = false, _reading = false, _ackPhase = false, _masterAck = true;
  int _bits = 0, _byte = 0, _index = 0, _ptr = 0, _current = 0;

  void start() {
    _active = true;
    _reading = false;
    _ackPhase = false;
    _bits = 0;
    _byte = 0;
    _index = 0;
    driveLow = false;
  }

  void stop() {
    _active = false;
    driveLow = false;
  }

  void sclRise(bool sda) {
    if (!_active) return;
    if (_ackPhase) {
      if (_reading) _masterAck = !sda;
      return;
    }
    if (_reading) return;
    _byte = (_byte << 1) | (sda ? 1 : 0);
    _bits++;
  }

  void _load() {
    _current = mem[_ptr++] ?? 0;
    _bits = 0;
    driveLow = (_current >> 7) & 1 == 0;
  }

  void sclFall() {
    if (!_active) return;
    if (_ackPhase) {
      _ackPhase = false;
      driveLow = false;
      if (_reading) {
        if (!_masterAck) {
          _active = false;
          return;
        }
        _load();
      }
      return;
    }
    if (_reading) {
      _bits++;
      if (_bits == 8) {
        driveLow = false;
        _masterAck = false;
        _ackPhase = true;
      } else {
        driveLow = (_current >> (7 - _bits)) & 1 == 0;
      }
      return;
    }
    if (_bits < 8) return;
    final b = _byte;
    _bits = 0;
    _byte = 0;
    if (_index == 0) {
      if (b >> 1 != address) {
        _active = false;
        return;
      }
      _reading = b & 1 == 1;
      _masterAck = true;
    } else if (_index == 1) {
      _ptr = b << 8;
    } else if (_index == 2) {
      _ptr |= b;
    }
    _index++;
    driveLow = true;
    _ackPhase = true;
  }
}

Map<int, int> _gt911(int w, int h) => {
      0x8140: 0x39, 0x8141: 0x31, 0x8142: 0x31, 0x8143: 0x00, // "911"
      0x8048: w & 0xFF, 0x8049: w >> 8, 0x804A: h & 0xFF, 0x804B: h >> 8,
    };

const _bridge = UsbPortInfo(id: 'COM3', label: 'USB-SERIAL CH340', vid: 0x1A86, pid: 0x7523);

FakeRom _bridgeRom() => FakeRom(inBootloader: true)..regs[0x3FCEF14C] = 2;

void main() {
  catalogMatchesFirmware();
  isolateRuns();

  group('decide', () {
    ProbeFacts s3Bridge({Map<String, TouchHit?> touch = const {}}) =>
        ProbeFacts(chip: ChipFamily.esp32s3, link: UsbLink.bridge, flashSize: 16 << 20, touch: touch);

    test('identifies the 4-inch square board by where its touch controller sits', () {
      final d = decide(s3Bridge(touch: {'19/20': null, '19/45': const TouchHit(0x5D, goodix: true, resolution: (480, 480))}));
      expect(d.boards.map((b) => b.id), ['esp32-4848s040c']);
    });

    test('800x480 boards differ only in screen size, so the user picks', () {
      final d = decide(s3Bridge(touch: {'19/20': const TouchHit(0x14, goodix: true, resolution: (800, 480)), '19/45': null}));
      expect(d.identified, isFalse);
      expect(d.boards.map((b) => b.id),
          containsAll(['esp32-8048s043c', 'esp32-8048s050c', 'jc8048w550c', 'esp32-8048s070c']));
      expect(d.boards.map((b) => b.id), isNot(contains('esp32-4827s043c')));
    });

    test('the touch resolution separates 480x272 from 800x480', () {
      final d = decide(s3Bridge(touch: {'19/20': const TouchHit(0x5D, goodix: true, resolution: (480, 272)), '19/45': null}));
      expect(d.boards.map((b) => b.id), ['esp32-4827s043c']);
    });

    test('nothing answering is not a supported board, even with the right chip', () {
      final d = decide(s3Bridge(touch: {'19/20': null, '19/45': null}));
      expect(d.supported, isFalse);
      expect(d.unsupported, Unsupported.noMatch);
      expect(d.family, isNotEmpty);
    });

    test('a chip, link and flash no supported board has', () {
      final d = decide(const ProbeFacts(chip: ChipFamily.esp32, link: UsbLink.native, flashSize: 4 << 20));
      expect(d.unsupported, Unsupported.hardware);
      expect(d.family, isEmpty);
    });

    test('native USB ESP32-S3 boards by touch controller', () {
      ProbeFacts s3(Map<String, TouchHit?> touch) =>
          ProbeFacts(chip: ChipFamily.esp32s3, link: UsbLink.native, flashSize: 16 << 20, touch: touch);
      expect(decide(s3({'4/8': const TouchHit(0x3B), '8/4': null, '16/15': null})).boards.map((b) => b.id), ['jc3248w535']);
      expect(decide(s3({'4/8': null, '8/4': null, '16/15': const TouchHit(0x38)})).boards.map((b) => b.id), ['es3c28p']);
    });

    test('4 MB of flash rules out 16 MB boards', () {
      final d = decide(const ProbeFacts(
          chip: ChipFamily.esp32s3, link: UsbLink.native, flashSize: 4 << 20, touch: {'4/8': TouchHit(0x3B), '8/4': null}));
      expect(d.supported, isFalse, reason: 'the JC3248W535 has 16 MB');
    });

    test('resistive CYD boards: the touch bus and the display ID tell them apart', () {
      ProbeFacts cyd({required bool ownBus, String? controller}) => ProbeFacts(
            chip: ChipFamily.esp32,
            link: UsbLink.bridge,
            flashSize: 4 << 20,
            touch: const {'33/32': null},
            resistive: {'25/32/39/33': ownBus, '14/13/12/33': !ownBus},
            controller: controller,
          );
      expect(decide(cyd(ownBus: true, controller: 'ILI9341')).boards.map((b) => b.id), ['esp32-2432s028r']);
      expect(decide(cyd(ownBus: true, controller: 'ST7789')).boards.map((b) => b.id), ['esp32-2432s028rv3']);
      expect(decide(cyd(ownBus: true)).boards.map((b) => b.id), ['esp32-2432s028r', 'esp32-2432s028rv3']);
      expect(decide(cyd(ownBus: false, controller: 'ST7796')).boards.map((b) => b.id), ['esp32-3248s035r']);
    });

    test('capacitive CYD boards by touch controller and resolution', () {
      ProbeFacts cyd(TouchHit hit) => ProbeFacts(
          chip: ChipFamily.esp32, link: UsbLink.bridge, flashSize: 4 << 20, touch: {'33/32': hit}, resistive: const {});
      expect(decide(cyd(const TouchHit(0x5D, goodix: true, resolution: (320, 480)))).boards.map((b) => b.id),
          ['esp32-3248s035c']);
      expect(decide(cyd(const TouchHit(0x5D, goodix: true, resolution: (240, 320)))).boards.map((b) => b.id),
          ['esp32-2432s032c']);
      expect(decide(cyd(const TouchHit(0x15))).boards.map((b) => b.id), ['jc2432w328c', 'esp32-2432s024c']);
    });
  });

  group('probes', () {
    test('display IDs are found at any bit alignment', () {
      expect(matchDisplayId(rddid: 0, id4: 0x00934100), 'ILI9341');
      expect(matchDisplayId(rddid: 0, id4: 0x0049A080), 'ILI9341', reason: 'shifted by a dummy bit');
      expect(matchDisplayId(rddid: 0x85855200, id4: 0), 'ST7789');
      expect(matchDisplayId(rddid: 0, id4: 0x00779600), 'ST7796');
      expect(matchDisplayId(rddid: 0xFFFFFFFF, id4: 0xFFFFFFFF), isNull);
      expect(matchDisplayId(rddid: 0, id4: 0), isNull);
    });

    test('an XPT2046 gives steady mid-range readings, an empty bus does not', () {
      expect(looksLikeXpt2046([742, 745, 740]), isTrue);
      expect(looksLikeXpt2046([4095, 4095, 4095]), isFalse);
      expect(looksLikeXpt2046([0, 0, 0]), isFalse);
      expect(looksLikeXpt2046([300, 2900, 1200]), isFalse);
    });

    test('bit-banged I2C reads a GT911 product ID and resolution', () async {
      final rom = FakeRom(inBootloader: true);
      SimBoard(rom, [I2cDevice(19, 20, 0x5D, _gt911(800, 480))]);
      final loader = EspLoader(rom)..chip = ChipFamily.esp32s3;
      final g = RomGpio(loader, ChipFamily.esp32s3);
      final hit = await probeI2cTouch(g, sda: 19, scl: 20, addresses: [0x14, 0x5D]);
      expect(hit?.address, 0x5D);
      expect(hit?.goodix, isTrue);
      expect(hit?.resolution, (800, 480));
      expect(await probeI2cTouch(g, sda: 19, scl: 45, addresses: [0x14, 0x5D]), isNull);
    });
  });

  group('runDetect', () {
    test('finds the 4.3" 480x272 board through a USB-UART bridge', () async {
      final rom = _bridgeRom();
      SimBoard(rom, [I2cDevice(19, 20, 0x5D, _gt911(480, 272))]);
      final d = await runDetect(FakeUsb(rom, port: _bridge), (_) {});
      expect(d.boards.map((b) => b.id), ['esp32-4827s043c']);
      expect(d.facts!.summary, contains('GT911 at 0x5D, 480x272'));
      expect(rom.writes, isEmpty, reason: 'detection never writes flash');
    });

    test('finds the JC3248W535 on native USB', () async {
      final rom = FakeRom(inBootloader: true);
      SimBoard(rom, [I2cDevice(4, 8, 0x3B)]);
      final d = await runDetect(FakeUsb(rom), (_) {});
      expect(d.boards.map((b) => b.id), ['jc3248w535']);
    });

    test('an ESP32-S3 dev board with nothing attached is unsupported', () async {
      final rom = _bridgeRom();
      SimBoard(rom, const []);
      final d = await runDetect(FakeUsb(rom, port: _bridge), (_) {});
      expect(d.supported, isFalse);
      expect(d.unsupported, Unsupported.noMatch);
    });

    test('another chip is unsupported', () async {
      final rom = _bridgeRom()..regs[0x40001000] = 0x1B31506F; // ESP32-C3
      final d = await runDetect(FakeUsb(rom, port: _bridge), (_) {});
      expect(d.unsupported, Unsupported.chip);
    });
  });
}

/// Every board in the app's catalog has a firmware build with matching settings.
void catalogMatchesFirmware() {
  test('the board catalog matches firmware/boards', () {
    for (final b in BoardProfile.all) {
      final f = File('firmware/boards/${b.firmwareId}/board.cmake');
      expect(f.existsSync(), isTrue, reason: '${b.id} has no firmware build');
      final vars = {
        for (final m in RegExp(r'set\((\w+)\s*([^)]*)\)').allMatches(f.readAsStringSync())) m[1]!: m[2]!.trim(),
      };
      expect(vars['BOARD_TARGET'], b.chip == ChipFamily.esp32s3 ? 'esp32s3' : 'esp32', reason: b.id);
      expect(vars['BOARD_LINK'], b.link == UsbLink.native ? 'usb' : 'uart', reason: b.id);
      expect(vars['BOARD_DECK'], '${b.width}x${b.height}', reason: b.id);
      expect(vars['BOARD_FLASH'], '${b.flashSize >> 20}mb', reason: b.id);
    }
  });
}

UsbBackend _simulatedJc3248() {
  final rom = FakeRom(inBootloader: true);
  SimBoard(rom, [I2cDevice(4, 8, 0x3B)]);
  return FakeUsb(rom);
}

/// The flasher runs in a background isolate on desktop. Only sendable values
/// may travel there, whatever else the caller (the UI) has in scope.
void isolateRuns() {
  test('detection runs in a background isolate next to unsendable UI state', () async {
    final uiState = Future<void>.delayed(const Duration(seconds: 1)); // like a provider's pending future
    final progress = ReceivePort();
    final stages = <int>[];
    progress.listen((m) => stages.add((m as List)[0] as int));
    final d = await runInIsolate(runDetect, progress.sendPort, _simulatedJc3248);
    progress.close();
    await uiState;
    expect(d.boards.map((b) => b.id), ['jc3248w535']);
    expect(stages, isNotEmpty);
  });
}
