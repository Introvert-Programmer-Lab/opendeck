// Looks at the board around the chip while it sits in the ROM bootloader:
// pins are driven and read through register writes, so nothing is flashed
// to find out what is connected. Every probe is read-only for the parts on
// the board (I2C address checks and register reads, SPI ID reads).
import 'dart:typed_data';

import 'esp_loader.dart';

/// GPIO control through the chip's registers.
class RomGpio {
  RomGpio(this.regs, this.chip);
  final ChipRegisters regs;
  final ChipFamily chip;
  final _claimed = <int>{};

  bool get _esp32 => chip == ChipFamily.esp32;
  int get _base => _esp32 ? 0x3FF44000 : 0x60004000;
  int get _funcOutSel => _base + (_esp32 ? 0x530 : 0x554);

  int _ioMux(int pin) {
    if (!_esp32) return 0x60009004 + 4 * pin;
    final off = _esp32IoMux[pin];
    if (off == null) throw ArgumentError('GPIO$pin has no pad on the ESP32');
    return 0x3FF49000 + off;
  }

  // Output and enable registers: bank 1 (GPIO32 and up) sits 0x0C further.
  Future<void> _bit(int reg, int pin) => regs.writeReg(_base + reg + (pin >= 32 ? 0x0C : 0), 1 << (pin & 31));

  /// Makes [pin] a plain GPIO with input enabled, output off and its output level low.
  Future<void> claim(int pin, {bool pullUp = false}) async {
    final func = _esp32 ? 2 : 1;
    await regs.writeReg(_ioMux(pin), (func << 12) | (2 << 10) | (1 << 9) | (pullUp ? 1 << 8 : 0));
    // Simple GPIO output, enabled through the GPIO_ENABLE registers.
    await regs.writeReg(_funcOutSel + 4 * pin, 0x100 | (1 << 10));
    await _bit(0x0C, pin);
    await _bit(0x28, pin);
    _claimed.add(pin);
  }

  Future<void> set(int pin, bool high) => _bit(high ? 0x08 : 0x0C, pin);
  Future<void> outputOn(int pin) => _bit(0x24, pin);
  Future<void> outputOff(int pin) => _bit(0x28, pin);

  Future<void> drive(int pin, bool high) async {
    await set(pin, high);
    await outputOn(pin);
  }

  Future<bool> read(int pin) async {
    final v = await regs.readReg(_base + (pin >= 32 ? 0x40 : 0x3C));
    return (v >> (pin & 31)) & 1 == 1;
  }

  /// Stops driving every pin touched so far.
  Future<void> releaseAll() async {
    for (final p in _claimed) {
      await outputOff(p);
    }
    _claimed.clear();
  }
}

/// I2C master by bit-banging two open-drain pins.
class BitI2c {
  BitI2c(this.g, this.sda, this.scl);
  final RomGpio g;
  final int sda, scl;

  Future<void> _sda(bool high) => high ? g.outputOff(sda) : g.outputOn(sda);
  Future<void> _scl(bool high) => high ? g.outputOff(scl) : g.outputOn(scl);

  Future<void> begin() async {
    await g.claim(sda, pullUp: true);
    await g.claim(scl, pullUp: true);
    // Clock out anything a device was in the middle of sending.
    for (var i = 0; i < 9; i++) {
      await _scl(false);
      await _scl(true);
    }
    await _stop();
  }

  Future<void> _start() async {
    await _sda(true);
    await _scl(true);
    await _sda(false);
    await _scl(false);
  }

  Future<void> _stop() async {
    await _sda(false);
    await _scl(true);
    await _sda(true);
  }

  Future<bool> _write(int byte) async {
    for (var i = 7; i >= 0; i--) {
      await _sda((byte >> i) & 1 == 1);
      await _scl(true);
      await _scl(false);
    }
    await _sda(true);
    await _scl(true);
    final nack = await g.read(sda);
    await _scl(false);
    return !nack;
  }

  Future<int> _read({required bool ack}) async {
    await _sda(true);
    var v = 0;
    for (var i = 0; i < 8; i++) {
      await _scl(true);
      v = (v << 1) | (await g.read(sda) ? 1 : 0);
      await _scl(false);
    }
    await _sda(!ack);
    await _scl(true);
    await _scl(false);
    await _sda(true);
    return v;
  }

  /// True when a device acknowledges [address].
  Future<bool> probe(int address) async {
    await _start();
    final ack = await _write(address << 1);
    await _stop();
    return ack;
  }

  /// Reads [count] bytes from a device with 16-bit register addresses (GT911).
  Future<Uint8List?> read16(int address, int reg, int count) async {
    await _start();
    final ok = await _write(address << 1) && await _write(reg >> 8) && await _write(reg & 0xFF);
    if (!ok) {
      await _stop();
      return null;
    }
    await _start();
    if (!await _write((address << 1) | 1)) {
      await _stop();
      return null;
    }
    final out = Uint8List(count);
    for (var i = 0; i < count; i++) {
      out[i] = await _read(ack: i < count - 1);
    }
    await _stop();
    return out;
  }
}

/// SPI master (mode 0) by bit-banging.
class BitSpi {
  BitSpi(this.g, {required this.sclk, required this.mosi, required this.miso, required this.cs, this.dc});
  final RomGpio g;
  final int sclk, mosi, miso, cs;
  final int? dc;
  bool _mosi = false;

  Future<void> begin() async {
    for (final p in [sclk, mosi, cs, ?dc]) {
      await g.claim(p);
    }
    await g.claim(miso, pullUp: true);
    await g.drive(cs, true);
    await g.drive(sclk, false);
    await g.drive(mosi, false);
    _mosi = false;
    if (dc != null) await g.drive(dc!, true);
  }

  Future<void> select(bool on) => g.set(cs, !on);
  Future<void> data(bool on) => g.set(dc!, on);

  Future<void> write(int value, {int bits = 8}) async {
    for (var i = bits - 1; i >= 0; i--) {
      final b = (value >> i) & 1 == 1;
      if (b != _mosi) {
        await g.set(mosi, b);
        _mosi = b;
      }
      await g.set(sclk, true);
      await g.set(sclk, false);
    }
  }

  Future<int> read(int bits) async {
    var v = 0;
    for (var i = 0; i < bits; i++) {
      await g.set(sclk, true);
      v = (v << 1) | (await g.read(miso) ? 1 : 0);
      await g.set(sclk, false);
    }
    return v;
  }
}

/// What answered on an I2C bus.
class TouchHit {
  const TouchHit(this.address, {this.goodix = false, this.resolution});
  final int address;

  /// The product ID read back says GT9xx.
  final bool goodix;

  /// GT911 configured resolution (x, y), when it could be read.
  final (int, int)? resolution;

  @override
  String toString() {
    final a = '0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final r = resolution == null ? '' : ', ${resolution!.$1}x${resolution!.$2}';
    return goodix ? 'GT911 at $a$r' : 'I2C device at $a';
  }
}

/// Checks [addresses] on the I2C bus at [sda]/[scl], first pulsing [reset]
/// (active low) if given. Returns the first device that answers.
Future<TouchHit?> probeI2cTouch(RomGpio g, {required int sda, required int scl, required List<int> addresses, int? reset}) async {
  if (reset != null) {
    await g.claim(reset);
    await g.drive(reset, false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await g.set(reset, true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final bus = BitI2c(g, sda, scl);
  await bus.begin();
  for (final a in addresses) {
    if (!await bus.probe(a)) continue;
    if (a != 0x5D && a != 0x14) return TouchHit(a);
    final id = await bus.read16(a, 0x8140, 4);
    final goodix = id != null && id[0] == 0x39; // "9xx"
    final cfg = goodix ? await bus.read16(a, 0x8048, 4) : null;
    (int, int)? res;
    if (cfg != null) {
      final x = cfg[0] | (cfg[1] << 8), y = cfg[2] | (cfg[3] << 8);
      if (x > 0 && y > 0 && x <= 4096 && y <= 4096) res = (x, y);
    }
    return TouchHit(a, goodix: goodix, resolution: res);
  }
  return null;
}

/// True when an XPT2046 answers on these pins: its temperature channel gives
/// steady mid-range readings, where an empty bus reads all zeros or all ones.
/// Pins in [deselect] (other chip selects on the same bus) are held high.
Future<bool> probeXpt2046(RomGpio g,
    {required int sclk, required int mosi, required int miso, required int cs, List<int> deselect = const []}) async {
  for (final p in deselect) {
    await g.claim(p);
    await g.drive(p, true);
  }
  final spi = BitSpi(g, sclk: sclk, mosi: mosi, miso: miso, cs: cs);
  await spi.begin();
  final values = <int>[];
  for (var i = 0; i < 3; i++) {
    await spi.select(true);
    await spi.write(0x84); // TEMP0, 12-bit, single ended
    values.add((await spi.read(16) >> 3) & 0xFFF);
    await spi.select(false);
  }
  return looksLikeXpt2046(values);
}

bool looksLikeXpt2046(List<int> temps) {
  if (temps.isEmpty) return false;
  final lo = temps.reduce((a, b) => a < b ? a : b);
  final hi = temps.reduce((a, b) => a > b ? a : b);
  return lo >= 150 && hi <= 3000 && hi - lo <= 300;
}

/// Reads a SPI display controller's ID registers. Returns ILI9341, ST7789,
/// ST7796 or null when the panel does not answer (some boards leave the
/// display's data out line unconnected).
Future<String?> probeDisplayController(RomGpio g,
    {required int sclk, required int mosi, required int miso, required int cs, required int dc, List<int> deselect = const []}) async {
  for (final p in deselect) {
    await g.claim(p);
    await g.drive(p, true);
  }
  final spi = BitSpi(g, sclk: sclk, mosi: mosi, miso: miso, cs: cs, dc: dc);
  await spi.begin();

  Future<int> command(int cmd, int bits) async {
    await spi.select(true);
    await spi.data(false);
    await spi.write(cmd);
    await spi.data(true);
    final v = await spi.read(bits);
    await spi.select(false);
    return v;
  }

  final found = matchDisplayId(rddid: await command(0x04, 32), id4: await command(0xD3, 32));
  if (found != null) return found;

  // ILI9341 over SPI often returns only the first parameter of a read; its
  // undocumented 0xD9 index register selects which one.
  var id4 = 0;
  for (var i = 1; i <= 3; i++) {
    await spi.select(true);
    await spi.data(false);
    await spi.write(0xD9);
    await spi.data(true);
    await spi.write(0x10 + i);
    await spi.data(false);
    await spi.write(0xD3);
    await spi.data(true);
    id4 = (id4 << 8) | await spi.read(8);
    await spi.select(false);
  }
  return matchDisplayId(rddid: 0, id4: id4 << 8);
}

/// Finds a known controller ID in 32 bits read after RDDID (0x04) and
/// ID4 (0xD3). The reply may start after a dummy bit, so every alignment is tried.
String? matchDisplayId({required int rddid, required int id4}) {
  bool has(int v, int pattern) {
    if (v == 0 || v == 0xFFFFFFFF) return false;
    for (var s = 0; s <= 8; s++) {
      if (((v >> (8 - s)) & 0xFFFFFF) == pattern) return true;
    }
    return false;
  }

  if (has(id4, 0x009341)) return 'ILI9341';
  if (has(id4, 0x007796)) return 'ST7796';
  if (has(rddid, 0x858552)) return 'ST7789';
  return null;
}

// ESP32 IO_MUX register offsets by GPIO number (the pads are not in order).
const _esp32IoMux = <int, int>{
  0: 0x44, 1: 0x88, 2: 0x40, 3: 0x84, 4: 0x48, 5: 0x6C, 12: 0x34, 13: 0x38, 14: 0x30, 15: 0x3C, //
  16: 0x4C, 17: 0x50, 18: 0x70, 19: 0x74, 21: 0x7C, 22: 0x80, 23: 0x8C, 25: 0x24, 26: 0x28, 27: 0x2C, //
  32: 0x1C, 33: 0x20, 34: 0x14, 35: 0x18, 36: 0x04, 37: 0x08, 38: 0x0C, 39: 0x10,
};
