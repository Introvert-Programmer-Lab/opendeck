import 'package:flutter/material.dart';

import '../../../core/constants/icon_catalog.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Theme colors first, then a general spread.
const List<int> kSwatches = [
  0xFFCCFF00, 0xFF0A100E, 0xFFFBFFE9, 0xFF141D19, 0xFF1F2B25, 0xFF2E3A33, //
  0xFFB9FFFD, 0xFF022E39, 0xFF5CE1E6, 0xFF3D7BFF, 0xFF7B61FF, 0xFFE04DFF,
  0xFFFF5A4E, 0xFFFF8A3D, 0xFFFFC83D, 0xFF3DDC84, 0xFF00B894, 0xFFFFFFFF,
  0xFF000000, 0xFF8A968F,
];

/// A color swatch button that opens a picker. `value == null` means "default".
class ColorField extends StatelessWidget {
  const ColorField({super.key, required this.value, required this.onChanged, this.fallback, this.allowDefault = true});
  final int? value;
  final int? fallback;
  final bool allowDefault;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value ?? fallback ?? 0xFF000000;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rControl),
      onTap: () async {
        final r = await showDialog<_ColorResult>(
          context: context,
          builder: (_) => _ColorDialog(initial: shown, allowDefault: allowDefault),
        );
        if (r != null) onChanged(r.color);
      },
      child: Container(
        width: 40,
        height: 26,
        decoration: BoxDecoration(
          color: Color(shown),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: value == null ? AppTheme.line : AppTheme.cream.withValues(alpha: 0.5)),
        ),
        child: value == null ? const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.muted) : null,
      ),
    );
  }
}

class _ColorResult {
  const _ColorResult(this.color);
  final int? color;
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial, required this.allowDefault});
  final int initial;
  final bool allowDefault;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  late final _hex = TextEditingController(text: _toHex(widget.initial));

  static String _toHex(int c) => (c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(Color c) {
    setState(() => _hsv = HSVColor.fromColor(c));
    _hex.text = _toHex(c.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = _hsv.toColor();
    return AlertDialog(
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kSwatches)
              GestureDetector(
                onTap: () => _set(Color(c)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(c),
                    borderRadius: BorderRadius.circular(AppTheme.rControl),
                    border: Border.all(color: color.toARGB32() == c ? AppTheme.lime : AppTheme.line, width: color.toARGB32() == c ? 2 : 1),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _slider('H', _hsv.hue / 360, (v) => _set(_hsv.withHue(v * 360).toColor())),
          _slider('S', _hsv.saturation, (v) => _set(_hsv.withSaturation(v).toColor())),
          _slider('V', _hsv.value, (v) => _set(_hsv.withValue(v).toColor())),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppTheme.rControl), border: Border.all(color: AppTheme.line)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(prefixText: '#'),
                onSubmitted: (v) {
                  final n = int.tryParse(v.replaceAll('#', ''), radix: 16);
                  if (n != null) _set(Color(0xFF000000 | n));
                },
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        if (widget.allowDefault)
          TextButton(onPressed: () => Navigator.pop(context, const _ColorResult(null)), child: Text(s.defaultColor)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _ColorResult(color.toARGB32())), child: Text(s.ok)),
      ],
    );
  }

  Widget _slider(String label, double v, ValueChanged<double> onChanged) => Row(children: [
        SizedBox(width: 18, child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        Expanded(child: Slider(value: v.clamp(0, 1), onChanged: onChanged)),
      ]);
}

/// Grid of icons with search. Returns the chosen code point.
Future<int?> showIconPicker(BuildContext context) => showDialog<int>(context: context, builder: (_) => const _IconDialog());

class _IconDialog extends StatefulWidget {
  const _IconDialog();
  @override
  State<_IconDialog> createState() => _IconDialogState();
}

class _IconDialogState extends State<_IconDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = kIconCatalog.where((e) => _q.isEmpty || e.$2.contains(_q.toLowerCase())).toList();
    return AlertDialog(
      title: TextField(
        autofocus: true,
        decoration: InputDecoration(hintText: s.searchIcons, prefixIcon: const Icon(Icons.search_rounded)),
        onChanged: (v) => setState(() => _q = v.trim()),
      ),
      content: SizedBox(
        width: 420,
        height: 380,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 58, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: items.length,
          itemBuilder: (_, i) => Tooltip(
            message: items[i].$2.split(' ').first,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context, items[i].$1.codePoint),
              child: Ink(
                decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                child: Icon(items[i].$1, color: AppTheme.cream),
              ),
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel))],
    );
  }
}

/// Look up the IconData for a stored code point (falls back to a neutral glyph).
IconData iconFor(int codePoint) =>
    kIconCatalog.firstWhere((e) => e.$1.codePoint == codePoint, orElse: () => (Icons.circle_outlined, '')).$1;
