import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.locale = const Locale('en'),
    this.lastPort,
    this.lastHost,
    this.loaded = false,
    this.onboarded = false,
  });
  final Locale locale;
  final String? lastPort; // last USB port, for auto-reconnect
  final String? lastHost; // last Wi-Fi address
  final bool loaded; // false until the saved values are read
  final bool onboarded; // first-run setup finished or skipped

  bool get arabic => locale.languageCode == 'ar';

  AppSettings copyWith({
    Locale? locale,
    String? Function()? lastPort,
    String? Function()? lastHost,
    bool? loaded,
    bool? onboarded,
  }) =>
      AppSettings(
        locale: locale ?? this.locale,
        lastPort: lastPort != null ? lastPort() : this.lastPort,
        lastHost: lastHost != null ? lastHost() : this.lastHost,
        loaded: loaded ?? this.loaded,
        onboarded: onboarded ?? this.onboarded,
      );
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _load();
    final sys = PlatformDispatcher.instance.locale.languageCode;
    return AppSettings(locale: Locale(sys == 'ar' ? 'ar' : 'en'));
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final lang = p.getString('lang');
    state = state.copyWith(
      locale: lang != null ? Locale(lang) : null,
      lastPort: () => p.getString('lastPort'),
      lastHost: () => p.getString('lastHost'),
      // Installs from before the setup screen existed already have a deck.
      onboarded: p.getBool('onboarded') ?? (p.getString('lastPort') != null || p.getString('lastHost') != null),
      loaded: true,
    );
  }

  Future<void> setOnboarded(bool v) async {
    state = state.copyWith(onboarded: v);
    (await SharedPreferences.getInstance()).setBool('onboarded', v);
  }

  Future<void> setLanguage(String code) async {
    state = state.copyWith(locale: Locale(code));
    (await SharedPreferences.getInstance()).setString('lang', code);
  }

  Future<void> rememberPort(String? port) async {
    state = state.copyWith(lastPort: () => port);
    final p = await SharedPreferences.getInstance();
    port == null ? p.remove('lastPort') : p.setString('lastPort', port);
  }

  Future<void> rememberHost(String? host) async {
    state = state.copyWith(lastHost: () => host);
    final p = await SharedPreferences.getInstance();
    host == null ? p.remove('lastHost') : p.setString('lastHost', host);
  }
}
