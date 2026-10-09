// Default audio endpoint mute through Core Audio (IMMDeviceEnumerator ->
// IMMDevice -> IAudioEndpointVolume), called by vtable index over raw FFI.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _clsctxAll = 0x17;
const _coinitApartmentThreaded = 0x2;
const eRender = 0;
const eCapture = 1;
const _eConsole = 0;
const _eCommunications = 2;

typedef _CoInitC = Int32 Function(Pointer<Void>, Uint32);
typedef _CoInitDart = int Function(Pointer<Void>, int);
typedef _CoCreateC = Int32 Function(Pointer<Uint8>, Pointer<Void>, Uint32, Pointer<Uint8>, Pointer<Pointer<Void>>);
typedef _CoCreateDart = int Function(Pointer<Uint8>, Pointer<Void>, int, Pointer<Uint8>, Pointer<Pointer<Void>>);

typedef _ReleaseC = Uint32 Function(Pointer<Void>);
typedef _ReleaseDart = int Function(Pointer<Void>);
typedef _GetDefaultC = Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Pointer<Void>>);
typedef _GetDefaultDart = int Function(Pointer<Void>, int, int, Pointer<Pointer<Void>>);
typedef _GetIdC = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>);
typedef _GetIdDart = int Function(Pointer<Void>, Pointer<Pointer<Utf16>>);
typedef _ActivateC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ActivateDart = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SetMuteC = Int32 Function(Pointer<Void>, Int32, Pointer<Void>);
typedef _SetMuteDart = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _GetMuteC = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _GetMuteDart = int Function(Pointer<Void>, Pointer<Int32>);
typedef _CoTaskMemFreeC = Void Function(Pointer<Void>);
typedef _CoTaskMemFreeDart = void Function(Pointer<Void>);

final _ole32 = DynamicLibrary.open('ole32.dll');
final _coInit = _ole32.lookupFunction<_CoInitC, _CoInitDart>('CoInitializeEx');
final _coCreate = _ole32.lookupFunction<_CoCreateC, _CoCreateDart>('CoCreateInstance');
final _coTaskMemFree = _ole32.lookupFunction<_CoTaskMemFreeC, _CoTaskMemFreeDart>('CoTaskMemFree');

/// Function pointer at vtable [index] of COM object [obj].
Pointer<NativeFunction<T>> _vt<T extends Function>(Pointer<Void> obj, int index) {
  final vtbl = obj.cast<Pointer<Pointer<Void>>>().value;
  return vtbl[index].cast<NativeFunction<T>>();
}

void _release(Pointer<Void> obj) {
  if (obj == nullptr) return;
  _vt<_ReleaseC>(obj, 2).asFunction<_ReleaseDart>()(obj);
}

Pointer<Uint8> _guid(Arena a, String s) {
  final hex = s.replaceAll(RegExp(r'[{}-]'), '');
  final g = a<Uint8>(16);
  final d1 = int.parse(hex.substring(0, 8), radix: 16);
  final d2 = int.parse(hex.substring(8, 12), radix: 16);
  final d3 = int.parse(hex.substring(12, 16), radix: 16);
  g.cast<Uint32>().value = d1;
  (g + 4).cast<Uint16>().value = d2;
  (g + 6).cast<Uint16>().value = d3;
  for (var i = 0; i < 8; i++) {
    g[8 + i] = int.parse(hex.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return g;
}

const _clsidEnumerator = 'BCDE0395-E52F-467C-8E3D-C4579291692E';
const _iidEnumerator = 'A95664D2-9614-4F35-A746-DE8DB63617E6';
const _iidEndpointVolume = '5CDF2C82-841E-4546-9722-0CF74078229A';

bool _comReady = false;
void _ensureCom() {
  if (_comReady) return;
  _coInit(nullptr, _coinitApartmentThreaded); // S_FALSE / RPC_E_CHANGED_MODE are fine
  _comReady = true;
}

/// Runs [body] with the IAudioEndpointVolume of the default [flow] endpoint for [role].
T? _withEndpoint<T>(int flow, int role, T Function(Pointer<Void> vol, String id) body) {
  _ensureCom();
  return using((a) {
    final pEnum = a<Pointer<Void>>();
    if (_coCreate(_guid(a, _clsidEnumerator), nullptr, _clsctxAll, _guid(a, _iidEnumerator), pEnum) != 0) {
      return null;
    }
    final en = pEnum.value;
    final pDev = a<Pointer<Void>>();
    final pVol = a<Pointer<Void>>();
    try {
      if (_vt<_GetDefaultC>(en, 4).asFunction<_GetDefaultDart>()(en, flow, role, pDev) != 0) return null;
      final dev = pDev.value;
      var id = '';
      final pId = a<Pointer<Utf16>>();
      if (_vt<_GetIdC>(dev, 5).asFunction<_GetIdDart>()(dev, pId) == 0) {
        id = pId.value.toDartString();
        _coTaskMemFree(pId.value.cast());
      }
      if (_vt<_ActivateC>(dev, 3).asFunction<_ActivateDart>()(
              dev, _guid(a, _iidEndpointVolume), _clsctxAll, nullptr, pVol) !=
          0) {
        return null;
      }
      return body(pVol.value, id);
    } finally {
      _release(pVol.value);
      _release(pDev.value);
      _release(en);
    }
  });
}

bool? _getMute(Pointer<Void> vol) => using((a) {
      final out = a<Int32>();
      if (_vt<_GetMuteC>(vol, 15).asFunction<_GetMuteDart>()(vol, out) != 0) return null;
      return out.value != 0;
    });

void _setMute(Pointer<Void> vol, bool mute) =>
    _vt<_SetMuteC>(vol, 14).asFunction<_SetMuteDart>()(vol, mute ? 1 : 0, nullptr);

/// Current mute state of the default endpoint (eRender or eCapture); null on failure.
bool? endpointMuted(int flow) => _withEndpoint<bool?>(flow, _eConsole, (v, _) => _getMute(v));

/// Toggle mute on the default endpoint; returns the new state (null on failure).
/// For the microphone, the default communications device gets the same state
/// when it is a different device (calls apps often use that one).
bool? toggleEndpointMute(int flow) {
  String? consoleId;
  final next = _withEndpoint<bool?>(flow, _eConsole, (v, id) {
    consoleId = id;
    final cur = _getMute(v);
    if (cur == null) return null;
    _setMute(v, !cur);
    return !cur;
  });
  if (next != null && flow == eCapture) {
    _withEndpoint(flow, _eCommunications, (v, id) {
      if (id != consoleId) _setMute(v, next);
      return true;
    });
  }
  return next;
}
