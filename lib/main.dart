import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/background_service.dart';
import 'core/theme/app_theme.dart';
import 'features/deck/pages/editor_page.dart';
import 'features/device/providers/device_provider.dart';
import 'features/onboarding/pages/onboarding_page.dart';
import 'features/settings/providers/settings_provider.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.instance.init(startHidden: args.contains('--background'));
  runApp(const ProviderScope(child: OpenDeckApp()));
}

class OpenDeckApp extends ConsumerWidget {
  const OpenDeckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final locale = settings.locale;
    // Keep the device link alive for the whole app (it runs actions on key taps).
    ref.watch(deviceProvider);
    return MaterialApp(
      title: 'OpenDeck',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(locale),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: !settings.loaded
          ? const ColoredBox(color: AppTheme.ink)
          : settings.onboarded
              ? const EditorPage()
              : const OnboardingPage(),
    );
  }
}
