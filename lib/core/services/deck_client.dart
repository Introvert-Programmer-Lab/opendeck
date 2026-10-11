import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'deck_transport.dart';

class DeckException implements Exception {
  DeckException(this.message, {this.link = false});
  final String message;

  /// The link failed (closed or stopped answering), as opposed to the deck
  /// refusing a request.
  final bool link;
  @override
  String toString() => 'DeckException: $message';
}

class DeviceInfo {
  const DeviceInfo({
    required this.fw,
    this.id = '',
    this.lcd = 0,
    this.touch = '',
    required this.board,
    required this.name,
    required this.width,
    required this.height,
    required this.fsTotal,
    required this.fsUsed,
    required this.psramFree,
    required this.pages,
    required this.page,
    required this.wifiAp,
    required this.wifiConnected,
    required this.wifiSsid,
    required this.wifiIp,
  });

  final String fw, board, name;

  /// Board ID of the firmware build (e.g. "esp32-8048s043c"). Empty on older firmware.
  final String id;

  /// Panel variant the firmware uses; bit 0 flips color inversion.
  final int lcd;

  /// "resistive" or "capacitive". Empty on older firmware.
  final String touch;
  final int width, height, fsTotal, fsUsed, psramFree, pages, page;
  final bool wifiAp, wifiConnected;
  final String wifiSsid, wifiIp;

  int get fsFree => fsTotal - fsUsed;

  factory DeviceInfo.fromJson(Map<String, dynamic> j) {
    int i(String k, [int d = 0]) => (j[k] as num?)?.toInt() ?? d;
    final w = (j['wifi'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DeviceInfo(
      fw: '${j['fw'] ?? ''}',
      id: '${j['id'] ?? ''}',
      lcd: i('lcd'),
      touch: '${j['touch'] ?? ''}',
      board: '${j['board'] ?? ''}',
      name: '${j['name'] ?? 'OpenDeck'}',
      width: i('w', 320),
      height: i('h', 480),
      fsTotal: i('fs_total'),
      fsUsed: i('fs_used'),
      psramFree: i('psram_free'),
      pages: i('pages'),
      page: i('page'),
      wifiAp: w['ap'] == true,
      wifiConnected: w['connected'] == true,
      wifiSsid: '${w['ssid'] ?? ''}',
      wifiIp: '${w['ip'] ?? ''}',
    );
  }
}

/// Request/response client for the deck's line-delimited JSON protocol.
/// One request is in flight at a time; unsolicited lines go to [events].
class DeckClient {
  DeckClient(this.transport) {
    _sub = transport.lines.listen(_onLine, onDone: _onDone, onError: (_) => _onDone());
    _ping = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_closed || _busy) return;
      request({'t': 'ping'}, timeout: const Duration(seconds: 3)).catchError((_) => <String, dynamic>{});
    });
  }

  static const _chunk = 3072;

  final DeckTransport transport;
  DeviceInfo? info;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<void>();
  late final StreamSubscription<String> _sub;
  late final Timer _ping;
  Future<void> _queue = Future.value();
  Completer<Map<String, dynamic>>? _pending;
  String? _pendingType;
  bool _closed = false;
  bool _busy = false; // long operations (upload) suppress pings

  Stream<Map<String, dynamic>> get events => _events.stream;
  Future<void> get done => _done.future;

  void _onLine(String line) {
    final i = line.indexOf('{');
    if (i < 0) return;
    Map<String, dynamic> msg;
    try {
      final v = jsonDecode(line.substring(i));
      if (v is! Map) return;
      msg = v.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final t = msg['t'];
    final p = _pending;
    final isReply = t == 'ok' || t == 'err' || t == 'pong' || (t == 'hello' && _pendingType == 'hello');
    if (isReply && p != null && !p.isCompleted) {
      _pending = null;
      _pendingType = null;
      p.complete(msg);
      return;
    }
    if (t == 'hello') info = DeviceInfo.fromJson(msg);
    if (!_events.isClosed) _events.add(msg);
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _ping.cancel();
    final p = _pending;
    if (p != null && !p.isCompleted) p.completeError(DeckException('link closed', link: true));
    _pending = null;
    if (!_done.isCompleted) _done.complete();
    _events.close();
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> cmd,
      {Duration timeout = const Duration(seconds: 5)}) {
    final result = _queue.then((_) => _send(cmd, timeout));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> cmd, Duration timeout) async {
    if (_closed) throw DeckException('link closed', link: true);
    final c = Completer<Map<String, dynamic>>();
    _pending = c;
    _pendingType = cmd['t'] as String?;
    await transport.send(jsonEncode(cmd));
    final reply = await c.future.timeout(timeout, onTimeout: () {
      if (identical(_pending, c)) {
        _pending = null;
        _pendingType = null;
      }
      throw DeckException('timeout waiting for reply to ${cmd['t']}', link: true);
    });
    if (reply['t'] == 'err') throw DeckException('${reply['m'] ?? 'error'}');
    return reply;
  }

  Future<DeviceInfo> hello() async {
    final r = await request({'t': 'hello'});
    return info = DeviceInfo.fromJson(r);
  }

  Future<void> uploadDeck(Map<String, Uint8List> files, {void Function(double progress)? onProgress}) async {
    final names = files.keys.where((n) => n != 'deck.json').toList();
    if (files.containsKey('deck.json')) names.add('deck.json');
    final total = files.values.fold<int>(0, (a, b) => a + b.length);
    var sent = 0;
    _busy = true;
    try {
      await request({'t': 'begin'}, timeout: const Duration(seconds: 15));
      onProgress?.call(0);
      for (final name in names) {
        final data = files[name]!;
        await request({'t': 'put', 'f': name, 'n': data.length});
        for (var off = 0; off < data.length; off += _chunk) {
          final end = off + _chunk > data.length ? data.length : off + _chunk;
          await request({'t': 'data', 'd': base64Encode(Uint8List.sublistView(data, off, end))});
          sent += end - off;
          onProgress?.call(total == 0 ? 1 : sent / total);
        }
      }
      await request({'t': 'commit'}, timeout: const Duration(seconds: 15));
      onProgress?.call(1);
    } finally {
      _busy = false;
    }
  }

  Future<void> setKeyState(String id, bool on) => request({'t': 'state', 'id': id, 'on': on});
  Future<void> setBrightness(int v) => request({'t': 'bright', 'v': v});
  Future<void> gotoPage(int n) => request({'t': 'page', 'n': n});
  Future<void> setWifi(String ssid, String pass) => request({'t': 'wifi', 'ssid': ssid, 'pass': pass});
  Future<void> setName(String name) => request({'t': 'name', 'v': name});
  Future<void> showInfo(bool on) => request({'t': 'info', 'on': on});
  Future<void> resetDeck() => request({'t': 'reset'});
  Future<void> reboot() => request({'t': 'reboot'});

  /// Shows the 3-point touch calibration on the board (resistive panels).
  Future<void> calibrateTouch() => request({'t': 'calibrate'});

  Future<Uint8List?> getFile(String name) async {
    final out = BytesBuilder(copy: false);
    try {
      var total = -1;
      while (total < 0 || out.length < total) {
        final r = await request({'t': 'get', 'f': name, 'o': out.length});
        total = (r['n'] as num?)?.toInt() ?? 0;
        final chunk = base64Decode('${r['d'] ?? ''}');
        if (chunk.isEmpty) break;
        out.add(chunk);
      }
      return out.takeBytes();
    } on DeckException {
      return null;
    }
  }

  Future<void> dispose() async {
    _ping.cancel();
    await _sub.cancel();
    await transport.close();
    _onDone();
  }
}
