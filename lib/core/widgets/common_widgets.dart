import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28, this.color = AppTheme.lime});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/logo/opendeck_mark.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// Logo mark next to the "OpenDeck" name.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.height = 28});
  final double height;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
        AppLogo(size: height),
        SizedBox(width: height * 0.4),
        Text('OpenDeck',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontFamily: AppTheme.displayFont, fontSize: height * 0.62, fontWeight: FontWeight.w600, color: AppTheme.cream)),
      ]);
}

/// Group header inside panels and inspectors: sentence case, semibold, with a
/// hairline above it (omit with [divider] for the first group).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.divider = true});
  final String text;
  final Widget? trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (divider) ...[const SizedBox(height: 16), const Divider(), const SizedBox(height: 12)] else const SizedBox(height: 12),
        SizedBox(
          height: 28,
          child: Row(children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.cream))),
            ?trailing,
          ]),
        ),
        const SizedBox(height: 6),
      ]);
}

/// Bordered surface for grouping content outside the inspector.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rPanel),
          border: Border.all(color: AppTheme.line),
        ),
        padding: padding,
        child: child,
      );
}

/// Connection state dot.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.size = 8});
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppTheme.lime : AppTheme.faint),
      );
}

/// Property-grid row: fixed label column, control column.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.label, required this.child, this.labelWidth = 112});
  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Row(children: [
            SizedBox(
              width: labelWidth,
              child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.3)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: child)),
          ]),
        ),
      );
}

/// Smaller switch for dense property rows.
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: FittedBox(fit: BoxFit.contain, child: Switch(value: value, onChanged: onChanged)),
      );
}

/// Muted helper text under controls.
class HelpText extends StatelessWidget {
  const HelpText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
      );
}

/// Compact segmented control (28 px) for toolbars.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T value, IconData? icon, String? label, String tooltip)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, icon, label, tip) in options)
            Tooltip(
              message: tip,
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: v == value ? AppTheme.hover : null,
                      borderRadius: BorderRadius.circular(4),
                      border: v == value ? Border.all(color: AppTheme.lineStrong) : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) Icon(icon, size: 14, color: v == value ? AppTheme.cream : AppTheme.muted),
                      if (icon != null && label != null) const SizedBox(width: 6),
                      if (label != null)
                        Text(label, style: TextStyle(fontSize: 12, color: v == value ? AppTheme.cream : AppTheme.muted, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}
