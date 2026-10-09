import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/background_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../onboarding/pages/onboarding_page.dart';
import '../providers/settings_provider.dart';
import '../widgets/deck_settings_panel.dart';

/// App preferences. Deck settings also live in the editor's inspector ("Deck" tab).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: Text(s.settings, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
      ),
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 40), children: [
            SectionLabel(s.general, divider: false),
            FieldRow(
              label: s.language,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ar', label: Text('العربية', style: TextStyle(fontFamily: 'Alexandria'))),
                ],
                selected: {settings.locale.languageCode},
                onSelectionChanged: (v) => ref.read(settingsProvider.notifier).setLanguage(v.first),
              ),
            ),
            if (Platform.isWindows) const _StartWithWindowsRow(),
            HelpText(s.ar
                ? 'التطبيق يعمل في الخلفية من شريط المهام ليشغّل أزرار اللوحة فورًا. إغلاق النافذة يخفيها فقط.'
                : 'The app runs in the system tray so deck keys work instantly. Closing the window only hides it.'),
            FieldRow(
              label: s.firmware,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(s.setupBoard),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const OnboardingPage(closeWhenDone: true))),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const DeckSettingsPanel(),
            SectionLabel(s.about),
            const Align(alignment: AlignmentDirectional.centerStart, child: AppWordmark(height: 28)),
            const SizedBox(height: 12),
            HelpText(s.aboutText),
          ]),
        ),
      ),
    );
  }
}

class _StartWithWindowsRow extends StatefulWidget {
  const _StartWithWindowsRow();
  @override
  State<_StartWithWindowsRow> createState() => _StartWithWindowsRowState();
}

class _StartWithWindowsRowState extends State<_StartWithWindowsRow> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    BackgroundService.instance.startWithComputer().then((v) => mounted ? setState(() => _on = v) : null);
  }

  @override
  Widget build(BuildContext context) => FieldRow(
        label: S.of(context).ar ? 'التشغيل مع ويندوز' : 'Start with Windows',
        child: CompactSwitch(
          value: _on ?? false,
          onChanged: _on == null
              ? null
              : (v) async {
                  await BackgroundService.instance.setStartWithComputer(v);
                  final now = await BackgroundService.instance.startWithComputer();
                  if (mounted) setState(() => _on = now);
                },
        ),
      );
}
