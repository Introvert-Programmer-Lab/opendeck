// Serial port list through SetupAPI (raw FFI), for Windows.
//
// libserialport is not used on Windows: its error path
// (sp_last_error_message) frees an uninitialized pointer when Windows has no
// text for the error code, which corrupts the heap and kills the app. Asking it
// for the USB IDs of a port that is not USB (Bluetooth, built-in COM) is enough
// to hit it.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

class WinPortInfo {
  const WinPortInfo(this.name, this.description, this.vid, this.pid);
  final String name;
  final String description;
  final int vid, pid;
}

const _digcfPresent = 0x2;
const _spdrpDeviceDesc = 0x0;
const _spdrpHardwareId = 0x1;
const _spdrpFriendlyName = 0xC;
const _dicsFlagGlobal = 1;
const _diregDev = 1;
const _keyRead = 0x20019;
const _devInfoSize = 32; // SP_DEVINFO_DATA on 64-bit Windows

typedef _GetClassDevsC = IntPtr Function(Pointer<Uint8>, Pointer<Utf16>, IntPtr, Uint32);
typedef _GetClassDevsDart = int Function(Pointer<Uint8>, Pointer<Utf16>, int, int);
typedef _EnumC = Int32 Function(IntPtr, Uint32, Pointer<Uint8>);
typedef _EnumDart = int Function(int, int, Pointer<Uint8>);
typedef _GetPropC = Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _GetPropDart = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint8>, int, Pointer<Uint32>);
typedef _OpenKeyC = IntPtr Function(IntPtr, Pointer<Uint8>, Uint32, Uint32, Uint32, Uint32);
typedef _OpenKeyDart = int Function(int, Pointer<Uint8>, int, int, int, int);
typedef _DestroyC = Int32 Function(IntPtr);
typedef _DestroyDart = int Function(int);
typedef _QueryC = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _QueryDart = int Function(int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);

class _Api {
  _Api() {
    final setup = DynamicLibrary.open('setupapi.dll');
    final adv = DynamicLibrary.open('advapi32.dll');
    getClassDevs = setup.lookupFunction<_GetClassDevsC, _GetClassDevsDart>('SetupDiGetClassDevsW');
    enumInfo = setup.lookupFunction<_EnumC, _EnumDart>('SetupDiEnumDeviceInfo');
    getProp = setup.lookupFunction<_GetPropC, _GetPropDart>('SetupDiGetDeviceRegistryPropertyW');
    openKey = setup.lookupFunction<_OpenKeyC, _OpenKeyDart>('SetupDiOpenDevRegKey');
    destroy = setup.lookupFunction<_DestroyC, _DestroyDart>('SetupDiDestroyDeviceInfoList');
    query = adv.lookupFunction<_QueryC, _QueryDart>('RegQueryValueExW');
    closeKey = adv.lookupFunction<_DestroyC, _DestroyDart>('RegCloseKey');
  }
  late final _GetClassDevsDart getClassDevs;
  late final _EnumDart enumInfo;
  late final _GetPropDart getProp;
  late final _OpenKeyDart openKey;
  late final _DestroyDart destroy;
  late final _QueryDart query;
  late final _DestroyDart closeKey;
}

_Api? _api;

/// GUID_DEVCLASS_PORTS {4d36e978-e325-11ce-bfc1-08002be10318}, in memory order.
const _portsClass = [
  0x78, 0xe9, 0x36, 0x4d, 0x25, 0xe3, 0xce, 0x11, //
  0xbf, 0xc1, 0x08, 0x00, 0x2b, 0xe1, 0x03, 0x18,
];

/// Present COM ports with their USB IDs (zero when the port is not USB).
List<WinPortInfo> listWinPorts() {
  final api = _api ??= _Api();
  return using((arena) {
    final guid = arena<Uint8>(16);
    guid.asTypedList(16).setAll(0, _portsClass);
    final set = api.getClassDevs(guid, nullptr, 0, _digcfPresent);
    if (set == -1 || set == 0) return const <WinPortInfo>[];
    final out = <WinPortInfo>[];
    try {
      final info = arena<Uint8>(_devInfoSize);
      const bufBytes = 4096;
      final buf = arena<Uint8>(bufBytes);
      final size = arena<Uint32>();
      final type = arena<Uint32>();
      final valueName = 'PortName'.toNativeUtf16(allocator: arena);

      String prop(int which) {
        buf.asTypedList(bufBytes).fillRange(0, bufBytes, 0);
        // The last two bytes stay zero, so the text is always terminated.
        if (api.getProp(set, info, which, type, buf, bufBytes - 2, size) == 0) return '';
        return buf.cast<Utf16>().toDartString();
      }

      for (var i = 0;; i++) {
        info.asTypedList(_devInfoSize).fillRange(0, _devInfoSize, 0);
        info.cast<Uint32>().value = _devInfoSize;
        if (api.enumInfo(set, i, info) == 0) break;

        var name = '';
        final key = api.openKey(set, info, _dicsFlagGlobal, 0, _diregDev, _keyRead);
        if (key != -1 && key != 0) {
          buf.asTypedList(bufBytes).fillRange(0, bufBytes, 0);
          size.value = bufBytes - 2;
          if (api.query(key, valueName, nullptr, type, buf, size) == 0) name = buf.cast<Utf16>().toDartString();
          api.closeKey(key);
        }
        if (!name.toUpperCase().startsWith('COM')) continue; // printer ports (LPT) and the like

        final ids = parseUsbIds(prop(_spdrpHardwareId));
        var desc = prop(_spdrpFriendlyName);
        if (desc.isEmpty) desc = prop(_spdrpDeviceDesc);
        desc = desc.replaceFirst(RegExp(r'\s*\(COM\d+\)$'), '');
        out.add(WinPortInfo(name, desc, ids.$1, ids.$2));
      }
    } finally {
      api.destroy(set);
    }
    return out;
  });
}

/// USB vendor and product ID from a hardware ID such as
/// `USB\VID_303A&PID_1001&REV_0101` or `FTDIBUS\COMPORT&VID_0403&PID_6001`.
(int, int) parseUsbIds(String hardwareId) {
  final vid = RegExp(r'VID_([0-9A-Fa-f]{4})').firstMatch(hardwareId);
  final pid = RegExp(r'PID_([0-9A-Fa-f]{4})').firstMatch(hardwareId);
  if (vid == null || pid == null) return (0, 0);
  return (int.parse(vid.group(1)!, radix: 16), int.parse(pid.group(1)!, radix: 16));
}
