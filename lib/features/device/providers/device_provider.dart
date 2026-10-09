import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/deck_client.dart';
import '../../../core/services/deck_transport.dart';
import '../../../core/services/flasher/flash_log.dart';
import '../../../core/services/host_actions.dart';
import '../../deck/controller/deck_compiler.dart';
import '../../deck/models/deck_action.dart';
import '../../deck/models/deck_model.dart';
import '../../deck/providers/project_provider.dart';
import '../../settings/providers/settings_provider.dart';

enum LinkStatus { disconnected, connecting, connected }

class DeviceState {
  const DeviceState({
    this.status = LinkStatus.disconnected,
    this.label = '',
    this.isUsb = false,
    this.info,
    this.syncProgress,
    this.syncStep = '',
    this.lastSync,
    this.error,
  });

  final LinkStatus status;
  final String label;
  final bool isUsb;
  final DeviceInfo? info;
  final double? syncProgress; // non-null while syncing
  final String syncStep;
  final CompiledDeck? lastSync;
  final String? error;

  bool get connected => status == LinkStatus.connected;
  bool get syncing => syncProgress != null;

  DeviceState copyWith({
    LinkStatus? status,
    String? label,
    bool? isUsb,
    DeviceInfo? Function()? info,
    double? Function()? syncProgress,
    String? syncStep,
    CompiledDeck? Function()? lastSync,
    String? Function()? error,
  }) =>
      DeviceState(
        status: status ?? this.status,
        label: label ?? this.label,
        isUsb: isUsb ?? this.isUsb,
        info: info != null ? info() : this.info,
        syncProgress: syncProgress != null ? syncProgress() : this.syncProgress,
        syncStep: syncStep ?? this.syncStep,
        lastSync: lastSync != null ? lastSync() : this.lastSync,
        error: error != null ? error() : this.error,
      );
}

final deviceProvider = NotifierProvider<DeviceController, DeviceState>(DeviceController.new);

class DeviceController extends Notifier<DeviceState> {
  DeckClient? _client;
  StreamSubscription? _events;
  Timer? _statePoll;
  final Map<ActionType, bool> _sentStates = {};
  Timer? _reconnect;
  bool _userDisconnected = false;
  bool _autoBusy = false;
  bool _suspended = false;

  @override
  DeviceState build() {
    ref.onDispose(() {
      _reconnect?.cancel();
      _teardown();
    });
    Future.microtask(_autoConnect);
    // Keep reconnecting, so unplugging, replugging and reboots need no action.
    _reconnect = Timer.periodic(const Duration(seconds: 4), (_) {
      if (state.status == LinkStatus.disconnected && !_userDisconnected && !_suspended && !state.syncing) _autoConnect();
    });
    return const DeviceState();
  }

  DeckClient? get client => _client;

  /// On desktop, reconnect to the last used port (or address) at startup.
  Future<void> _autoConnect() async {
    if (_autoBusy) return;
    _autoBusy = true;
    try {
      await _autoConnectOnce();
    } finally {
      _autoBusy = false;
    }
  }

  Future<void> _autoConnectOnce() async {
    await Future.delayed(const Duration(milliseconds: 300));
    // A sync reconnects on its own if its link drops.
    if (_suspended || state.syncing) return;
    final s = ref.read(settingsProvider);
    final ports = SerialDeckTransport.listPorts();
    final usb = ports.where((p) => p.name == s.lastPort).firstOrNull ?? ports.where((p) => p.isEspressif).firstOrNull ??
        ports.where((p) => p.isBridge).firstOrNull;
    if (usb != null) {
      await connectUsb(usb.name, quiet: true);
    } else if (s.lastHost != null) {
      await connectTcp(s.lastHost!, quiet: true);
    }
  }

  Future<void> connectUsb(String port, {bool quiet = false}) async {
    if (!quiet) _userDisconnected = false;
    await _connect(() => SerialDeckTransport.open(port), quiet: quiet);
    if (state.connected) await ref.read(settingsProvider.notifier).rememberPort(port);
  }

  Future<void> connectTcp(String host, {bool quiet = false}) async {
    if (!quiet) _userDisconnected = false;
    await _connect(() => TcpDeckTransport.connect(host), quiet: quiet);
    if (state.connected) await ref.read(settingsProvider.notifier).rememberHost(host);
  }

  Future<void> _connect(Future<DeckTransport> Function() open, {bool quiet = false}) async {
    await _teardown();
    state = state.copyWith(status: LinkStatus.connecting, error: () => null);
    try {
      final t = await open();
      final c = DeckClient(t);
      _client = c;
      // USB-Serial/JTAG may reset the board when the port opens; give it a moment to boot.
      DeviceInfo? info;
      for (var i = 0; i < 6 && info == null; i++) {
        try {
          info = await c.hello();
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }
      if (info == null) throw const SocketException('The deck did not answer');
      // Tell the deck whether this app runs actions (desktop) or only configures it (phone).
      // While a desktop app is connected it handles taps; otherwise the deck uses USB HID.
      try {
        await c.request({'t': 'host', 'exec': HostActions.instance.supported});
      } catch (_) {}
      state = state.copyWith(status: LinkStatus.connected, label: t.label, isUsb: t.isUsb, info: () => info);
      ref.read(projectProvider.notifier).setPanel(info.width, info.height);
      _events = c.events.listen(_onEvent);
      c.done.then((_) {
        if (_client == c) {
          _client = null;
          _statePoll?.cancel();
          state = state.copyWith(status: LinkStatus.disconnected, info: () => null);
        }
      });
      _sentStates.clear();
      _statePoll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _syncToggleStates());
      _syncToggleStates();
    } catch (e) {
      await _teardown();
      state = state.copyWith(status: LinkStatus.disconnected, error: () => quiet ? null : '$e');
    }
  }

  /// Releases the USB port and stops reconnecting, e.g. while flashing firmware.
  Future<void> suspend() async {
    _suspended = true;
    await _teardown();
    state = const DeviceState();
  }

  Future<void> resume() async {
    _suspended = false;
    _userDisconnected = false;
    await _autoConnect();
  }

  Future<void> disconnect() async {
    _userDisconnected = true;
    await _teardown();
    state = const DeviceState();
  }

  Future<void> _teardown() async {
    _statePoll?.cancel();
    _statePoll = null;
    await _events?.cancel();
    _events = null;
    final c = _client;
    _client = null;
    await c?.dispose();
  }

  Future<void> refreshInfo() async {
    final c = _client;
    if (c == null) return;
    try {
      final info = await c.hello();
      state = state.copyWith(info: () => info);
    } catch (_) {}
  }

  // Key events
  void _onEvent(Map<String, dynamic> e) {
    if (e['t'] == 'key') {
      final key = ref.read(projectProvider).keyById('${e['id']}');
      if (key == null) return;
      _runKey(key);
    } else if (e['t'] == 'page') {
      final info = state.info;
      if (info != null) state = state.copyWith(info: () => info);
    }
  }

  Future<void> _runKey(DeckKey key) async {
    final a = key.action;
    if (a.type == ActionType.none || a.type.runsOnDevice) return;
    await HostActions.instance.run(a);
    if (a.type.isToggle) {
      _sentStates.remove(a.type);
      await _syncToggleStates();
    }
  }

  /// Test an action from the editor without touching the deck.
  Future<void> testAction(DeckAction a) async {
    if (a.type.runsOnDevice) {
      final c = _client;
      if (c == null) return;
      switch (a.type) {
        case ActionType.gotoPage:
          await c.gotoPage(int.tryParse(a.param('page')) ?? 0);
        case ActionType.brightnessUp:
          await c.setBrightness(255);
        case ActionType.brightnessDown:
          await c.setBrightness(60);
        default:
          break;
      }
      return;
    }
    await HostActions.instance.run(a);
    if (a.type.isToggle) {
      _sentStates.remove(a.type);
      await _syncToggleStates();
    }
  }

  /// Mirror mic/speaker mute on the deck's toggle keys.
  Future<void> _syncToggleStates() async {
    final c = _client;
    if (c == null || state.syncing || !HostActions.instance.supported) return;
    final project = ref.read(projectProvider);
    final keysByType = <ActionType, Set<String>>{};
    for (final p in project.pages) {
      for (final k in p.allKeys) {
        if (k.action.type.isToggle) keysByType.putIfAbsent(k.action.type, () => {}).add(k.id);
      }
    }
    for (final entry in keysByType.entries) {
      final on = entry.key == ActionType.micMute
          ? await HostActions.instance.micMuted()
          : await HostActions.instance.speakerMuted();
      if (on == null || _sentStates[entry.key] == on) continue;
      _sentStates[entry.key] = on;
      for (final id in entry.value) {
        try {
          await c.setKeyState(id, on);
        } catch (_) {}
      }
    }
  }

  // Sync
  Future<CompiledDeck?> sync() async {
    if (_client == null || state.syncing) return null;
    state = state.copyWith(syncProgress: () => 0, syncStep: 'render', error: () => null);
    try {
      CompiledDeck? compiled;
      for (var attempt = 0;; attempt++) {
        final c = _client;
        if (c == null) throw DeckException('link closed', link: true);
        try {
          final info = await c.hello();
          // Staging needs room for the new deck while the old one still exists.
          final budget = ((info.fsTotal - info.fsUsed) * 0.9).floor();
          compiled ??= await compileDeck(ref.read(projectProvider),
              budgetBytes: budget, onStep: (s) => state = state.copyWith(syncStep: s));
          state = state.copyWith(syncStep: 'upload', syncProgress: () => 0);
          await c.uploadDeck(compiled.files, onProgress: (p) => state = state.copyWith(syncProgress: () => p));
          break;
        } catch (e) {
          // A dropped or stuck link: reconnect, as Disconnect and Connect would, and
          // upload again from the start (the deck discards a half-finished upload).
          if (attempt > 0 || !_isLinkError(e)) rethrow;
          FlashLog.line('deck link: sync failed ($e), reconnecting');
          if (!await _relink()) rethrow;
        }
      }
      _sentStates.clear();
      state = state.copyWith(syncProgress: () => null, lastSync: () => compiled);
      await refreshInfo();
      unawaited(_syncToggleStates());
      return compiled;
    } catch (e) {
      state = state.copyWith(syncProgress: () => null, error: () => '$e');
      rethrow;
    }
  }

  static bool _isLinkError(Object e) =>
      e is SocketException || e is TimeoutException || (e is DeckException && e.link);

  /// Closes the current link and opens it again. True when the deck answers.
  Future<bool> _relink() async {
    final label = state.label;
    final usb = state.isUsb;
    if (label.isEmpty) return false;
    await _teardown();
    // Give the system a moment to release the port before opening it again.
    await Future.delayed(const Duration(milliseconds: 500));
    await _connect(() => usb ? SerialDeckTransport.open(label) : TcpDeckTransport.connect(label), quiet: true);
    return state.connected;
  }

  /// Pull the project stored on the deck (written by another copy of the app).
  Future<bool> pullProject() async {
    final c = _client;
    if (c == null) return false;
    final bytes = await c.getFile('project.json');
    if (bytes == null) return false;
    ref.read(projectProvider.notifier).replace(DeckProject.fromJson(jsonDecode(utf8.decode(bytes))));
    return true;
  }

  Future<void> setWifi(String ssid, String pass) async {
    await _client?.setWifi(ssid, pass);
    unawaited(Future.delayed(const Duration(seconds: 8), refreshInfo));
  }

  /// Switches the panel variant (color inversion). The deck restarts and the
  /// app reconnects.
  Future<void> setLcdVariant(int v) async {
    try {
      await _client?.request({'t': 'lcd', 'v': v});
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> setBrightness(int v) async {
    try {
      await _client?.setBrightness(v);
    } catch (e) {
      debugPrint('$e');
    }
  }
}
