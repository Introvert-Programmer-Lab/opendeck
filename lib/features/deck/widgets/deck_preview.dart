import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../controller/deck_renderer.dart';
import '../models/deck_model.dart';
import '../providers/project_provider.dart';

/// Shows the page exactly as the board will (same renderer as the sync), in a
/// device bezel, with selection and drag-to-swap on top.
class DeckPreview extends ConsumerStatefulWidget {
  const DeckPreview({super.key, this.showOn = false, this.zoom});
  final bool showOn; // preview toggle keys in their "on" state
  final double? zoom; // null = fit to the available space

  @override
  ConsumerState<DeckPreview> createState() => _DeckPreviewState();
}

class _DeckPreviewState extends ConsumerState<DeckPreview> {
  ui.Image? _image;
  int _seq = 0;
  Object? _renderedFor;

  void _render(DeckProject project, int page) {
    final key = (project, page, widget.showOn);
    if (_renderedFor == key) return;
    _renderedFor = key;
    final seq = ++_seq;
    final alt = widget.showOn ? project.pages[page].allKeys.where((k) => k.hasAltState).map((k) => k.id).toSet() : <String>{};
    renderPage(project, page, altIds: alt).then((img) {
      if (!mounted || seq != _seq) return;
      setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final sel = ref.watch(selectionProvider);
    final pageIndex = sel.page.clamp(0, project.pages.length - 1);
    _render(project, pageIndex);
    final layout = layoutPage(project, project.pages[pageIndex]);
    final lsize = layout.size;

    return LayoutBuilder(builder: (context, c) {
      const bezel = 12.0;
      final fit = (((c.maxHeight - bezel * 2) / lsize.height) < ((c.maxWidth - bezel * 2) / lsize.width)
              ? (c.maxHeight - bezel * 2) / lsize.height
              : (c.maxWidth - bezel * 2) / lsize.width)
          .clamp(0.3, 3.0)
          .toDouble();
      final s = widget.zoom ?? fit;
      final w = lsize.width * s, h = lsize.height * s;

      final device = Container(
        padding: const EdgeInsets.all(bezel),
        decoration: BoxDecoration(
          color: const Color(0xFF030504),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.lineStrong),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(
                child: _image == null
                    ? const ColoredBox(color: AppTheme.ink)
                    : RawImage(image: _image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              ),
              for (final slot in layout.slots)
                Positioned(
                  left: slot.rect.left * s,
                  top: slot.rect.top * s,
                  width: slot.rect.width * s,
                  height: slot.rect.height * s,
                  child: _SlotOverlay(
                    slot: slot,
                    page: pageIndex,
                    radius: project.theme.cornerRadius * s,
                    selected: sel.section == slot.section && sel.slot == slot.index,
                  ),
                ),
            ]),
          ),
        ),
      );
      if (widget.zoom == null) return Center(child: device);
      return Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Padding(padding: const EdgeInsets.all(24), child: device)),
        ),
      );
    });
  }
}

class _SlotOverlay extends ConsumerStatefulWidget {
  const _SlotOverlay({required this.slot, required this.page, required this.radius, required this.selected});
  final SlotRect slot;
  final int page;
  final double radius;
  final bool selected;

  @override
  ConsumerState<_SlotOverlay> createState() => _SlotOverlayState();
}

class _SlotOverlayState extends ConsumerState<_SlotOverlay> {
  bool _hover = false;
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final empty = slot.key == null;
    final br = BorderRadius.circular(widget.radius);

    final Widget box = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ref.read(selectionProvider.notifier).slot(slot.section, slot.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: br,
            color: _dragOver ? AppTheme.lime.withValues(alpha: 0.12) : (empty && _hover ? const Color(0x0DFFFFFF) : null),
            border: widget.selected
                ? Border.all(color: AppTheme.lime, width: 2)
                : empty
                    ? Border.all(color: AppTheme.cream.withValues(alpha: _hover ? 0.28 : 0.1), width: 1)
                    : (_hover ? Border.all(color: AppTheme.cream.withValues(alpha: 0.35), width: 1) : null),
          ),
          child: empty
              ? Center(child: Icon(Icons.add, size: 16, color: AppTheme.cream.withValues(alpha: _hover ? 0.55 : 0.18)))
              : null,
        ),
      ),
    );

    final target = DragTarget<(int, int)>(
      onWillAcceptWithDetails: (d) {
        final ok = d.data != (slot.section, slot.index);
        if (ok) setState(() => _dragOver = true);
        return ok;
      },
      onLeave: (_) => setState(() => _dragOver = false),
      onAcceptWithDetails: (d) {
        setState(() => _dragOver = false);
        ref.read(projectProvider.notifier).swapSlots(widget.page, d.data, (slot.section, slot.index));
        ref.read(selectionProvider.notifier).slot(slot.section, slot.index);
      },
      builder: (context, _, _) => box,
    );

    if (empty) return target;
    return Draggable<(int, int)>(
      data: (slot.section, slot.index),
      feedback: Opacity(
        opacity: 0.85,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(AppTheme.rPanel),
            border: Border.all(color: AppTheme.lime, width: 1.5),
          ),
          child: const Icon(Icons.open_with, size: 18, color: AppTheme.cream),
        ),
      ),
      childWhenDragging: Container(
        decoration: BoxDecoration(borderRadius: br, color: Colors.black54),
      ),
      child: target,
    );
  }
}
