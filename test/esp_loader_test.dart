// Runs the flasher against a simulated ESP32-S3 ROM bootloader.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/flasher/esp_loader.dart';
import 'package:opendeck/core/services/flasher/firmware_flasher.dart';
import 'package:opendeck/core/services/flasher/flash_port.dart';

import 'fake_rom.dart';

Uint8List _image() {
  final rnd = Random(1);
  final img = Uint8List(0x320000)..fillRange(0, 0x320000, 0xFF);
  void fill(int from, int len) {
    for (var i = 0; i < len; i++) {
      img[from + i] = rnd.nextInt(256);
    }
  }

  fill(0, 0x5000); // bootloader
  img[0] = 0xE9;
  img[12] = 9; // chip ID: ESP32-S3
  img[13] = 0;
  fill(0x8000, 0xC00); // partition table
  fill(0x10000, 0x40000); // app, then a long blank tail
  fill(0x310000, 0x3000); // start of the filesystem
  img[0x310000 + 0x8000] = 0x01; // a used block after a small gap
  return img;
}

void main() {
  test('splitImage keeps small gaps and skips long ones', () {
    final segs = splitImage(_image());
    expect(segs.map((s) => s.offset), [0x0, 0x310000]);
    expect(segs.first.data.length, 0x50000);
    expect(segs.last.data.length, 0x9000);
  });

  test('flashes a merged image through the ROM protocol', () async {
    final rom = FakeRom();
    final image = _image();
    final stages = <FlashStage>{};
    await runFlash(FakeUsb(rom), image, BoardProfile.jc3248w535, (p) => stages.add(p.stage));

    expect(rom.paramsSize, 16 << 20);
    expect(rom.regs[0x60008098], 0, reason: 'RTC watchdog disabled on USB-Serial/JTAG');
    expect(rom.regs[0x600080B4]! & (1 << 31), isNonZero, reason: 'super watchdog auto feed on');
    for (final s in splitImage(image)) {
      expect(rom.flash.sublist(s.offset, s.offset + s.data.length), s.data);
    }
    // The NVS region between the partition table and the app got wiped.
    expect(rom.flash.sublist(0x9000, 0x10000).every((b) => b == 0xFF), isTrue);
    expect(rom.resetToApp, isTrue);
    expect(stages, containsAll([FlashStage.connect, FlashStage.write, FlashStage.verify, FlashStage.restart, FlashStage.done]));
  });

  test('asks running OpenDeck firmware to restart into the bootloader', () async {
    final usb = _RunningDeckUsb(FakeRom());
    final image = _image();
    await runFlash(usb, image, BoardProfile.jc3248w535, (_) {});
    expect(usb.sentDfu, isTrue);
    expect(usb.rom.writes, isNotEmpty);
  });

  test('refuses an image built for another chip', () async {
    final rom = FakeRom();
    final image = _image();
    image[0] = 0xFF; // an ESP32 image: bootloader header at 0x1000
    image[0x1000] = 0xE9;
    image[0x100C] = 0;
    image[0x100D] = 0;
    await expectLater(
      runFlash(FakeUsb(rom), image, null, (_) {}),
      throwsA(isA<FlashFailure>().having((e) => e.error, 'error', FlashError.wrongBoard)),
    );
    expect(rom.writes, isEmpty);
  });

  test('refuses a board with less flash than the firmware needs', () async {
    final rom = FakeRom()..jedec = 0x1640EF; // 4 MB
    await expectLater(
      runFlash(FakeUsb(rom), _image(), BoardProfile.jc3248w535, (_) {}),
      throwsA(isA<FlashFailure>().having((e) => e.error, 'error', FlashError.wrongBoard)),
    );
    expect(rom.writes, isEmpty);
  });

  test('reads the chip family from a merged image', () {
    expect(imageChip(_image()), ChipFamily.esp32s3);
    final esp32 = Uint8List(0x20000)..fillRange(0, 0x20000, 0xFF);
    esp32[0x1000] = 0xE9;
    esp32[0x100C] = 0;
    esp32[0x100D] = 0;
    expect(imageChip(esp32), ChipFamily.esp32);
    expect(imageChip(Uint8List(0x20000)), isNull);
  });

  test('reports a board that never enters download mode', () async {
    final usb = FakeUsb(_StuckRom());
    await expectLater(
      runFlash(usb, _image(), BoardProfile.jc3248w535, (_) {}),
      throwsA(isA<FlashFailure>().having((e) => e.error, 'error', FlashError.noBootloader)),
    );
  });
}

/// Control lines not wired to the chip: resets do nothing.
class _StuckRom extends FakeRom {
  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {}
}

/// Starts as the OpenDeck firmware's USB port; {"t":"dfu"} turns it into the ROM port.
class _RunningDeckUsb extends FakeUsb {
  _RunningDeckUsb(super.rom);
  bool sentDfu = false;

  @override
  Future<List<UsbPortInfo>> list() async => sentDfu
      ? const [UsbPortInfo(id: 'COM7', label: '', vid: 0x303A, pid: 0x1001)]
      : const [UsbPortInfo(id: 'COM9', label: 'OpenDeck', vid: 0x303A, pid: 0x4004)];

  @override
  Future<FlashPort> open(UsbPortInfo port, {int baud = 115200}) async =>
      port.isOpenDeck ? _AppPort(this) : rom;
}

class _AppPort extends FakeRom {
  _AppPort(this.usb);
  final _RunningDeckUsb usb;

  @override
  Future<void> write(Uint8List data) async {
    if (String.fromCharCodes(data).contains('"t":"dfu"')) {
      usb.sentDfu = true;
      usb.rom.inBootloader = true;
    }
  }
}
