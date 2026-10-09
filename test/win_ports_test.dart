import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/win_ports.dart';

void main() {
  test('reads USB IDs from Windows hardware IDs', () {
    expect(parseUsbIds(r'USB\VID_303A&PID_1001&REV_0101'), (0x303A, 0x1001));
    expect(parseUsbIds(r'USB\VID_303A&PID_4004&MI_00'), (0x303A, 0x4004));
    expect(parseUsbIds(r'USB\VID_1A86&PID_7523&REV_0264'), (0x1A86, 0x7523));
    expect(parseUsbIds(r'FTDIBUS\COMPORT&VID_0403&PID_6001'), (0x0403, 0x6001));
    expect(parseUsbIds(r'BTHENUM\{00001101-0000-1000-8000-00805f9b34fb}_LOCALMFG&0002'), (0, 0));
    expect(parseUsbIds(r'ACPI\PNP0501'), (0, 0));
  });
}
