import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../deck/controller/deck_renderer.dart';
import '../../deck/providers/project_provider.dart';
import '../../deck/widgets/pickers.dart';
import '../../device/providers/device_provider.dart';

/// Deck-wide settings: display, image quality, look, project actions.
/// Shown in the inspector's "Deck" tab.
class DeckSettingsPanel extends ConsumerWidget {
  const DeckSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final project = ref.watch(projectProvider);
    final pn = ref.read(projectProvider.notifier);
    final dev = ref.watch(deviceProvider);
    final t = project.theme;
    void theme(fn) => pn.update((p) => p.copyWith(theme: fn(p.theme)));

    Widget dropdown<T>(T value, List<(T, String)> items, ValueChanged<T> onChanged) => DropdownButtonFormField<T>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppTheme.cream),
          items: [for (final (v, label) in items) DropdownMenuItem(value: v, child: Text(label))],
          onChanged: (v) => v == null ? null : onChanged(v),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(s.display, divider: false),
      FieldRow(
        label: s.orientation,
        child: dropdown<int>(project.rotation, [
          for (final r in [0, 1, 2, 3])
            (
              r,
              rotationIsLandscape(project, r)
                  ? (r < 2 ? s.landscape : s.landscapeFlipped)
                  : (r < 2 ? s.portrait : s.portraitFlipped)
            ),
        ], (v) {
          pn.setRotation(v);
          ref.read(selectionProvider.notifier).clearSlot();
        }),
      ),
      FieldRow(
        label: s.brightness,
        child: Row(children: [
          Expanded(
            child: Slider(
              value: project.brightness.toDouble().clamp(10, 255),
              min: 10,
              max: 255,
              onChanged: (v) => pn.update((p) => p.copyWith(brightness: v.round())),
              onChangeEnd: (v) => ref.read(deviceProvider.notifier).setBrightness(v.round()),
            ),
          ),
          SizedBox(width: 36, child: Text('${(project.brightness / 2.55).round()}%', style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
        ]),
      ),
      if (dev.info != null) ...[
        FieldRow(
          label: s.invertColors,
          child: CompactSwitch(
            value: dev.info!.lcd & 1 == 1,
            onChanged: (v) => ref.read(deviceProvider.notifier).setLcdVariant((dev.info!.lcd & ~1) | (v ? 1 : 0)),
          ),
        ),
        HelpText(s.invertColorsHint),
      ],
      SectionLabel(s.imageQuality),
      FieldRow(
        label: s.imageQuality,
        child: Row(children: [
          Expanded(
            child: Slider(
              value: project.jpegQuality.toDouble(),
              min: 30,
              max: 95,
              divisions: 13,
              onChanged: (v) => pn.update((p) => p.copyWith(jpegQuality: v.round())),
            ),
          ),
          SizedBox(width: 36, child: Text('${project.jpegQuality}', style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
        ]),
      ),
      FieldRow(
        label: s.autoQuality,
        child: CompactSwitch(value: project.autoQuality, onChanged: (v) => pn.update((p) => p.copyWith(autoQuality: v))),
      ),
      HelpText(s.qualityHint),
      if (dev.lastSync != null)
        FieldRow(label: s.lastSync, child: Text(s.deckSize(dev.lastSync!.totalBytes, dev.lastSync!.quality), style: const TextStyle(fontSize: 12))),
      SectionLabel(s.appearance),
      FieldRow(label: s.accent, child: ColorField(value: t.accent, allowDefault: false, onChanged: (c) => theme((x) => x.copyWith(accent: c)))),
      FieldRow(label: s.pageBackground, child: ColorField(value: t.background, allowDefault: false, onChanged: (c) => theme((x) => x.copyWith(background: c)))),
      FieldRow(label: s.keys, child: ColorField(value: t.keyColor, allowDefault: false, onChanged: (c) => theme((x) => x.copyWith(keyColor: c)))),
      FieldRow(label: s.text2, child: ColorField(value: t.foreground, allowDefault: false, onChanged: (c) => theme((x) => x.copyWith(foreground: c)))),
      FieldRow(
        label: s.corners,
        child: Slider(value: t.cornerRadius, min: 0, max: 32, onChanged: (v) => theme((x) => x.copyWith(cornerRadius: v.roundToDouble()))),
      ),
      FieldRow(label: s.spacing, child: Slider(value: t.gap, min: 2, max: 20, onChanged: (v) => theme((x) => x.copyWith(gap: v.roundToDouble())))),
      FieldRow(
        label: s.labelSize,
        child: Slider(value: t.labelSize, min: 8, max: 16, onChanged: (v) => theme((x) => x.copyWith(labelSize: v.roundToDouble()))),
      ),
      FieldRow(label: s.showHeader, child: CompactSwitch(value: t.showHeader, onChanged: (v) => theme((x) => x.copyWith(showHeader: v)))),
      SectionLabel(s.project),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (dev.connected)
          OutlinedButton(
            child: Text(s.pullFromDeck),
            onPressed: () async {
              final ok = await ref.read(deviceProvider.notifier).pullProject();
              if (context.mounted && ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.pullDone)));
            },
          ),
        OutlinedButton(
          child: Text(s.resetDefault),
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(s.resetDefault),
                content: Text(s.resetConfirm),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.ok)),
                ],
              ),
            );
            if (yes == true) {
              await pn.resetToDefault();
              ref.read(selectionProvider.notifier).page(0);
            }
          },
        ),
      ]),
      const SizedBox(height: 16),
    ]);
  }
}
