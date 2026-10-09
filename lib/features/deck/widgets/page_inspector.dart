import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../controller/deck_renderer.dart';
import '../controller/image_tools.dart';
import '../models/deck_model.dart';
import '../providers/project_provider.dart';
import 'key_inspector.dart';
import 'pickers.dart';

/// A section of a layout preset: rows x cols.
typedef _Grid = (int rows, int cols);

/// Ready-made layouts, described for a portrait deck (sections stacked top to bottom).
const List<List<_Grid>> _portraitPresets = [
  [(2, 3), (2, 3)],
  [(3, 3)],
  [(4, 3)],
  [(3, 2)],
  [(5, 4)],
  [(2, 2), (2, 3)],
  [(1, 1), (2, 3)],
];

/// The same presets for a landscape deck: sections sit side by side, so each
/// grid is transposed (portrait 3 cols x 4 rows -> landscape 4 cols x 3 rows).
List<List<_Grid>> _presetsFor(bool landscape) =>
    landscape ? [for (final p in _portraitPresets) [for (final (r, c) in p) (c, r)]] : _portraitPresets;

String _presetName(List<_Grid> secs) => secs.map((g) => '${g.$2}×${g.$1}').join(' + ');

class PageInspector extends ConsumerWidget {
  const PageInspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final project = ref.watch(projectProvider);
    final n = ref.read(projectProvider.notifier);
    final pi = ref.watch(selectionProvider).page.clamp(0, project.pages.length - 1);
    final page = project.pages[pi];
    final landscape = isLandscape(project);

    void applyPreset(List<_Grid> secs) {
      // Keep existing keys in order, flowing them into the new grid.
      final keys = page.allKeys.toList();
      var i = 0;
      final sections = <DeckSection>[];
      for (var si = 0; si < secs.length; si++) {
        final (r, c) = secs[si];
        final old = si < page.sections.length ? page.sections[si] : null;
        sections.add(DeckSection(
          title: old?.title ?? '',
          rows: r,
          cols: c,
          // share of the stacking direction: height in portrait, width in landscape
          flex: landscape ? c : r,
          keys: List.generate(r * c, (_) => i < keys.length ? keys[i++] : null),
        ));
      }
      n.updatePage(pi, (p) => p.copyWith(sections: sections));
      ref.read(selectionProvider.notifier).clearSlot();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(s.page, divider: false),
      BoundField(identity: page.id, value: page.name, label: s.pageName, onChanged: (v) => n.updatePage(pi, (p) => p.copyWith(name: v))),
      SectionLabel(s.layout),
      LayoutBuilder(builder: (context, c) {
        const gap = 6.0;
        final cols = landscape ? 3 : 4;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final secs in _presetsFor(landscape))
            SizedBox(width: w, child: _PresetTile(sections: secs, landscape: landscape, onTap: () => applyPreset(secs))),
        ]);
      }),
      HelpText(s.presetsHint),
      SectionLabel(s.sections,
          trailing: IconButton(
            tooltip: s.addSection,
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => n.addSection(pi),
          )),
      for (var si = 0; si < page.sections.length; si++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SectionEditor(page: pi, index: si, section: page.sections[si], count: page.sections.length),
        ),
      SectionLabel(s.background),
      FieldRow(
        label: s.background,
        child: ColorField(value: page.background, fallback: project.theme.background, onChanged: (c) => n.updatePage(pi, (p) => p.copyWith(background: () => c))),
      ),
      FieldRow(
        label: s.backgroundImage,
        child: Row(children: [
          if (page.backgroundImage != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(page.backgroundImage!, width: landscape ? 42 : 28, height: landscape ? 28 : 42, fit: BoxFit.cover),
              ),
            ),
          OutlinedButton(
            child: Text(page.backgroundImage == null ? s.chooseImage : s.backgroundImage),
            onPressed: () async {
              final raw = await pickImageBytes();
              if (raw == null) return;
              final size = logicalSize(project);
              final bg = await prepareBackground(raw, size.width.round(), size.height.round());
              if (bg != null) n.updatePage(pi, (p) => p.copyWith(backgroundImage: () => bg));
            },
          ),
          if (page.backgroundImage != null)
            IconButton(
              tooltip: s.remove,
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => n.updatePage(pi, (p) => p.copyWith(backgroundImage: () => null)),
            ),
        ]),
      ),
      if (page.backgroundImage != null)
        FieldRow(
          label: s.dim,
          child: Slider(value: page.backgroundDim, onChanged: (v) => n.updatePage(pi, (p) => p.copyWith(backgroundDim: v))),
        ),
      const SizedBox(height: 12),
      HelpText(s.swipeHint),
    ]);
  }
}

/// Preset thumbnail drawn in the deck's real orientation.
class _PresetTile extends StatefulWidget {
  const _PresetTile({required this.sections, required this.landscape, required this.onTap});
  final List<_Grid> sections;
  final bool landscape;
  final VoidCallback onTap;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: BoxDecoration(
            color: _hover ? AppTheme.hover : AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            border: Border.all(color: _hover ? AppTheme.lineStrong : AppTheme.line),
          ),
          child: Column(children: [
            AspectRatio(
              aspectRatio: widget.landscape ? 3 / 2 : 2 / 3,
              child: CustomPaint(painter: _PresetPainter(widget.sections, widget.landscape)),
            ),
            const SizedBox(height: 6),
            Text(
              _presetName(widget.sections),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PresetPainter extends CustomPainter {
  _PresetPainter(this.sections, this.landscape);
  final List<_Grid> sections;
  final bool landscape;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    canvas.drawRRect(frame, Paint()..color = AppTheme.ink);
    final cell = Paint()..color = AppTheme.muted.withValues(alpha: 0.4);
    const pad = 3.0, gap = 1.6;
    final area = Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad);
    final weights = [for (final (r, c) in sections) landscape ? c : r];
    final total = weights.fold<int>(0, (a, b) => a + b);
    var cursor = landscape ? area.left : area.top;
    for (var i = 0; i < sections.length; i++) {
      final (rows, cols) = sections[i];
      final extent = (landscape ? area.width : area.height) * weights[i] / total;
      final last = i == sections.length - 1;
      final box = landscape
          ? Rect.fromLTWH(cursor, area.top, extent - (last ? 0 : 2.5), area.height)
          : Rect.fromLTWH(area.left, cursor, area.width, extent - (last ? 0 : 2.5));
      cursor += extent;
      final cw = (box.width - gap * (cols - 1)) / cols, ch = (box.height - gap * (rows - 1)) / rows;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(box.left + c * (cw + gap), box.top + r * (ch + gap), cw, ch), const Radius.circular(1.5)),
            cell,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PresetPainter old) => old.landscape != landscape || old.sections != sections;
}

class _SectionEditor extends ConsumerWidget {
  const _SectionEditor({required this.page, required this.index, required this.section, required this.count});
  final int page, index, count;
  final DeckSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final n = ref.read(projectProvider.notifier);
    void upd(DeckSection Function(DeckSection s) fn) => n.updateSection(page, index, fn);

    Widget stepper(int v, int min, int max, ValueChanged<int> set) => Container(
          height: 30,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _StepButton(icon: Icons.remove, onTap: v > min ? () => set(v - 1) : null),
            SizedBox(width: 26, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            _StepButton(icon: Icons.add, onTap: v < max ? () => set(v + 1) : null),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(AppTheme.rPanel),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(s.sectionN(index + 1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: '',
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (v) {
              if (v == 'up') n.moveSection(page, index, -1);
              if (v == 'down') n.moveSection(page, index, 1);
              if (v == 'del') n.removeSection(page, index);
              ref.read(selectionProvider.notifier).clearSlot();
            },
            itemBuilder: (_) => [
              if (index > 0) PopupMenuItem(height: 36, value: 'up', child: Text(s.moveUp)),
              if (index < count - 1) PopupMenuItem(height: 36, value: 'down', child: Text(s.moveDown)),
              if (count > 1) PopupMenuItem(height: 36, value: 'del', child: Text(s.delete, style: const TextStyle(color: AppTheme.danger))),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Column(children: [
            BoundField(identity: '$page-$index', value: section.title, label: s.sectionTitle, onChanged: (v) => upd((x) => x.copyWith(title: v))),
            FieldRow(label: s.columns, child: stepper(section.cols, 1, 6, (v) => upd((x) => x.copyWith(cols: v)))),
            FieldRow(label: s.rows, child: stepper(section.rows, 1, 6, (v) => upd((x) => x.copyWith(rows: v)))),
            FieldRow(label: s.size, child: stepper(section.flex, 1, 8, (v) => upd((x) => x.copyWith(flex: v)))),
          ]),
        ),
      ]),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rControl),
        child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 14, color: onTap == null ? AppTheme.faint : AppTheme.cream)),
      );
}
