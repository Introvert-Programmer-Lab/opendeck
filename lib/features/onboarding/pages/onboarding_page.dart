import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../device/providers/device_provider.dart';
import '../../device/widgets/device_sheet.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/flash_provider.dart';
import '../widgets/flash_panel.dart';

enum _Step { welcome, flash, connect }

/// First-run setup: install the firmware on a new board, then connect to it.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.closeWhenDone = false});

  /// Opened from settings: pop the route instead of flipping the first-run flag.
  final bool closeWhenDone;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  _Step _step = _Step.welcome;

  void _finish() {
    if (widget.closeWhenDone) {
      Navigator.of(context).pop();
    } else {
      ref.read(settingsProvider.notifier).setOnboarded(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    ref.listen(flashProvider, (prev, next) {
      if (next.done && !next.stock && !(prev?.done ?? false)) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted && _step == _Step.flash) setState(() => _step = _Step.connect);
        });
      }
    });

    final body = switch (_step) {
      _Step.welcome => _Welcome(
          onNewBoard: () => setState(() => _step = _Step.flash),
          onHaveBoard: () => setState(() => _step = _Step.connect),
        ),
      _Step.flash => _Section(title: s.installFirmware, child: const FlashPanel()),
      _Step.connect => _Section(title: s.connectTitle, child: _Connect(onDone: _finish)),
    };
    final running = ref.watch(flashProvider).running;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Align(alignment: AlignmentDirectional.centerStart, child: AppWordmark(height: 30)),
                const SizedBox(height: 28),
                Panel(padding: const EdgeInsets.all(20), child: body),
                const SizedBox(height: 12),
                Row(children: [
                  if (_step != _Step.welcome)
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: Text(s.back),
                      onPressed: running
                          ? null
                          : () {
                              ref.read(flashProvider.notifier).reset();
                              setState(() => _step = _Step.welcome);
                            },
                    ),
                  const Spacer(),
                  if (_step != _Step.connect) TextButton(onPressed: running ? null : _finish, child: Text(s.skipForNow)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ]);
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onNewBoard, required this.onHaveBoard});
  final VoidCallback onNewBoard, onHaveBoard;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.setupTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(s.setupIntro, style: const TextStyle(color: AppTheme.muted, height: 1.5)),
      const SizedBox(height: 20),
      _Choice(icon: Icons.bolt_rounded, title: s.newBoard, subtitle: s.newBoardHint, primary: true, onTap: onNewBoard),
      const SizedBox(height: 10),
      _Choice(icon: Icons.link_rounded, title: s.haveBoard, subtitle: s.haveBoardHint, onTap: onHaveBoard),
    ]);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.subtitle, required this.onTap, this.primary = false});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.rPanel),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rPanel),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rPanel),
              border: Border.all(color: primary ? AppTheme.lime.withValues(alpha: 0.5) : AppTheme.line),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primary ? AppTheme.lime : AppTheme.hover,
                  borderRadius: BorderRadius.circular(AppTheme.rControl),
                ),
                child: Icon(icon, size: 20, color: primary ? AppTheme.ink : AppTheme.cream),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ]),
              ),
              Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            ]),
          ),
        ),
      );
}

class _Connect extends ConsumerWidget {
  const _Connect({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final dev = ref.watch(deviceProvider);
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(desktop ? s.connectUsbHint : s.connectWifiHint, style: const TextStyle(color: AppTheme.muted, height: 1.5)),
      const SizedBox(height: 16),
      Row(children: [
        if (dev.connected)
          const Icon(Icons.check_circle_rounded, color: AppTheme.lime, size: 20)
        else
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            dev.connected ? '${s.connected}: ${dev.info?.name ?? dev.label}' : s.waitingForDeck,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        OutlinedButton(onPressed: () => showDeviceSheet(context), child: Text(s.connectionOptions)),
        const Spacer(),
        FilledButton(onPressed: onDone, child: Text(s.startDesigning)),
      ]),
    ]);
  }
}
