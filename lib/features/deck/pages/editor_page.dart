import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../device/providers/device_provider.dart';
import '../../device/widgets/device_sheet.dart';
import '../../settings/pages/settings_page.dart';
import '../../settings/widgets/deck_settings_panel.dart';
import '../controller/deck_renderer.dart';
import '../models/deck_model.dart';
import '../providers/project_provider.dart';
import '../widgets/deck_preview.dart';
import '../widgets/key_inspector.dart';
import '../widgets/page_inspector.dart';

const _kWide = 1000.0;
const _kTopBar = 48.0;
const _kStatusBar = 26.0;

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> with SingleTickerProviderStateMixin {
  bool _showOn = false;
  double? _zoom; // null = fit
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: ref.read(selectionProvider).hasSlot ? 0 : 1);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(deviceProvider).connected) {
      await showDeviceSheet(context);
      return;
    }
    try {
      final r = await ref.read(deviceProvider.notifier).sync();
      if (r != null) messenger.showSnackBar(SnackBar(content: Text('${s.synced} · ${s.deckSize(r.totalBytes, r.quality)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final wide = MediaQuery.sizeOf(context).width >= _kWide;

    // Selecting a key on the canvas brings its properties forward.
    ref.listen(selectionProvider, (prev, next) {
      if (next.hasSlot && (prev?.slot != next.slot || prev?.section != next.section || prev?.page != next.page)) {
        _tabs.animateTo(0);
      }
    });

    final inspector = Column(children: [
      SizedBox(
        height: 40,
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsetsDirectional.only(start: 4),
          tabs: [Tab(text: s.key), Tab(text: s.page), Tab(text: s.deck)],
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: const [
          _InspectorScroll(child: KeyInspector()),
          _InspectorScroll(child: PageInspector()),
          _InspectorScroll(child: DeckSettingsPanel()),
        ]),
      ),
    ]);

    final canvas = ColoredBox(
      color: AppTheme.canvas,
      child: Column(children: [
        _CanvasToolbar(
          showOn: _showOn,
          zoom: _zoom,
          onShowOn: (v) => setState(() => _showOn = v),
          onZoom: (z) => setState(() => _zoom = z),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => ref.read(selectionProvider.notifier).clearSlot(),
            child: Padding(padding: const EdgeInsets.all(24), child: DeckPreview(showOn: _showOn, zoom: _zoom)),
          ),
        ),
      ]),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _TopBar(onSync: _sync, compact: !wide),
          const Divider(),
          Expanded(
            child: wide
                ? Row(children: [
                    const SizedBox(width: 240, child: _PagesSidebar()),
                    const VerticalDivider(width: 1),
                    Expanded(child: canvas),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 340, child: ColoredBox(color: AppTheme.surface, child: inspector)),
                  ])
                : Column(children: [
                    const _PagesStrip(),
                    const Divider(),
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.42, child: canvas),
                    const Divider(),
                    Expanded(child: ColoredBox(color: AppTheme.surface, child: inspector)),
                  ]),
          ),
          const _StatusBar(),
        ]),
      ),
    );
  }
}

class _InspectorScroll extends StatelessWidget {
  const _InspectorScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Divider(),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
              child: child,
            ),
          ),
        ),
      ]);
}

// Top bar

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onSync, required this.compact});
  final VoidCallback onSync;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final dev = ref.watch(deviceProvider);
    final project = ref.watch(projectProvider);
    final pi = ref.watch(selectionProvider).page.clamp(0, project.pages.length - 1);
    final page = project.pages[pi];

    return Container(
      height: _kTopBar,
      color: AppTheme.ink,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
      child: Row(children: [
        const AppLogo(size: 22),
        const SizedBox(width: 10),
        Text(s.appName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        if (!compact) ...[
          const SizedBox(width: 16),
          Container(width: 1, height: 18, color: AppTheme.line),
          const SizedBox(width: 16),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: project.name, style: const TextStyle(color: AppTheme.muted)),
                const TextSpan(text: '  /  ', style: TextStyle(color: AppTheme.faint)),
                TextSpan(text: page.name.isEmpty ? '${s.page} ${pi + 1}' : page.name),
              ]),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
        const Spacer(),
        _DeviceButton(compact: compact),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: dev.syncing ? null : onSync,
          style: compact ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)) : null,
          icon: dev.syncing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: (dev.syncProgress ?? 0) == 0 ? null : dev.syncProgress,
                    color: AppTheme.muted,
                  ),
                )
              : const Icon(Icons.upload, size: 16),
          label: compact ? const SizedBox.shrink() : Text(dev.syncing ? s.syncing : s.syncToDeck),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: s.settings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
      ]),
    );
  }
}

class _DeviceButton extends ConsumerWidget {
  const _DeviceButton({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final dev = ref.watch(deviceProvider);
    final label = switch (dev.status) {
      LinkStatus.connected => dev.info?.name ?? dev.label,
      LinkStatus.connecting => s.connecting,
      LinkStatus.disconnected => s.notConnected,
    };
    return Tooltip(
      message: s.deckInfo,
      child: OutlinedButton(
        onPressed: () => showDeviceSheet(context),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dev.status == LinkStatus.connecting)
            const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5))
          else
            StatusDot(on: dev.connected),
          const SizedBox(width: 8),
          if (!compact) ...[
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
          ],
          Icon(dev.connected ? (dev.isUsb ? Icons.usb : Icons.wifi) : Icons.expand_more, size: 15, color: AppTheme.muted),
        ]),
      ),
    );
  }
}

// Canvas toolbar

class _CanvasToolbar extends ConsumerWidget {
  const _CanvasToolbar({required this.showOn, required this.zoom, required this.onShowOn, required this.onZoom});
  final bool showOn;
  final double? zoom;
  final ValueChanged<bool> onShowOn;
  final ValueChanged<double?> onZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final project = ref.watch(projectProvider);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    String zoomLabel(double? z) => z == null ? s.zoomFit : '${(z * 100).round()}%';

    return Container(
      height: 40,
      decoration: const BoxDecoration(color: AppTheme.ink, border: Border(bottom: BorderSide(color: AppTheme.line))),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      child: Row(children: [
        Segmented<bool>(
          value: isLandscape(project),
          options: [
            (false, Icons.stay_current_portrait, narrow ? null : s.portrait, s.portrait),
            (true, Icons.stay_current_landscape, narrow ? null : s.landscape, s.landscape),
          ],
          onChanged: (v) {
            ref.read(projectProvider.notifier).setRotation(rotationIsLandscape(project, 0) == v ? 0 : 1);
            ref.read(selectionProvider.notifier).clearSlot();
          },
        ),
        const SizedBox(width: 16),
        if (!narrow) ...[
          Text(s.previewOnState, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          const SizedBox(width: 6),
        ],
        Tooltip(message: s.previewOnState, child: CompactSwitch(value: showOn, onChanged: onShowOn)),
        const Spacer(),
        PopupMenuButton<double>(
          tooltip: '',
          initialValue: zoom ?? 0,
          onSelected: (v) => onZoom(v == 0 ? null : v),
          itemBuilder: (_) => [
            for (final z in const [0.0, 1.0, 1.5, 2.0]) PopupMenuItem(height: 34, value: z, child: Text(zoomLabel(z == 0 ? null : z))),
          ],
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.rControl), border: Border.all(color: AppTheme.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.zoom_in, size: 15),
              const SizedBox(width: 6),
              Text(zoomLabel(zoom), style: const TextStyle(fontSize: 12)),
              const Icon(Icons.expand_more, size: 15),
            ]),
          ),
        ),
      ]),
    );
  }
}

// Pages

/// Live miniature of a rendered page (re-rendered shortly after edits).
class _PageThumb extends ConsumerStatefulWidget {
  const _PageThumb({required this.index, required this.height});
  final int index;
  final double height;

  @override
  ConsumerState<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends ConsumerState<_PageThumb> {
  ui.Image? _img;
  Timer? _debounce;
  Object? _for;

  void _schedule(DeckProject p) {
    final key = (p, widget.index);
    if (_for == key) return;
    _for = key;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: _img == null ? 0 : 300), () async {
      if (widget.index >= p.pages.length) return;
      final img = await renderPage(p, widget.index);
      if (mounted) setState(() => _img = img);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(projectProvider);
    _schedule(p);
    final size = logicalSize(p);
    final w = widget.height * size.width / size.height;
    return Container(
      width: w,
      height: widget.height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: AppTheme.line), color: AppTheme.ink),
      clipBehavior: Clip.antiAlias,
      child: _img == null ? null : RawImage(image: _img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
    );
  }
}

class _PagesSidebar extends ConsumerWidget {
  const _PagesSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final project = ref.watch(projectProvider);
    final sel = ref.watch(selectionProvider);
    final n = ref.read(projectProvider.notifier);
    final landscape = isLandscape(project);

    return ColoredBox(
      color: AppTheme.surface,
      child: Column(children: [
        Container(
          height: 40,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 6, 0),
          child: Row(children: [
            Text(s.pages, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${project.pages.length}', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
            const Spacer(),
            IconButton(
              tooltip: s.addPage,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => ref.read(selectionProvider.notifier).page(n.addPage(s.newPage)),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            buildDefaultDragHandles: false,
            itemCount: project.pages.length,
            onReorderItem: (a, b) {
              n.movePage(a, b);
              ref.read(selectionProvider.notifier).page(b);
            },
            itemBuilder: (_, i) {
              final p = project.pages[i];
              final active = i == sel.page;
              return ReorderableDragStartListener(
                key: ValueKey(p.id),
                index: i,
                child: _PageRow(
                  index: i,
                  page: p,
                  active: active,
                  thumbHeight: landscape ? 36 : 54,
                  onTap: () => ref.read(selectionProvider.notifier).page(i),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _PageRow extends StatefulWidget {
  const _PageRow({required this.index, required this.page, required this.active, required this.thumbHeight, required this.onTap});
  final int index;
  final DeckPage page;
  final bool active;
  final double thumbHeight;
  final VoidCallback onTap;

  @override
  State<_PageRow> createState() => _PageRowState();
}

class _PageRowState extends State<_PageRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = widget.page;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 2, 8),
          decoration: BoxDecoration(
            color: widget.active ? AppTheme.hover : (_hover ? AppTheme.surfaceHigh : null),
            borderRadius: BorderRadius.circular(AppTheme.rControl),
          ),
          child: Row(children: [
            Container(width: 2, height: widget.thumbHeight, color: widget.active ? AppTheme.lime : Colors.transparent),
            const SizedBox(width: 8),
            _PageThumb(index: widget.index, height: widget.thumbHeight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.name.isEmpty ? '${s.page} ${widget.index + 1}' : p.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(s.keyCount(p.allKeys.length), style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ]),
            ),
            Opacity(opacity: _hover || widget.active ? 1 : 0, child: _PageMenu(index: widget.index)),
          ]),
        ),
      ),
    );
  }
}

class _PagesStrip extends ConsumerWidget {
  const _PagesStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final project = ref.watch(projectProvider);
    final sel = ref.watch(selectionProvider);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (var i = 0; i < project.pages.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: i == sel.page ? AppTheme.hover : null,
                  foregroundColor: i == sel.page ? AppTheme.cream : AppTheme.muted,
                ),
                onPressed: () => ref.read(selectionProvider.notifier).page(i),
                child: Text(project.pages[i].name.isEmpty ? '${s.page} ${i + 1}' : project.pages[i].name),
              ),
            ),
          IconButton(
            tooltip: s.addPage,
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => ref.read(selectionProvider.notifier).page(ref.read(projectProvider.notifier).addPage(s.newPage)),
          ),
        ],
      ),
    );
  }
}

class _PageMenu extends ConsumerWidget {
  const _PageMenu({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final n = ref.read(projectProvider.notifier);
    final count = ref.watch(projectProvider).pages.length;
    return PopupMenuButton<String>(
      tooltip: '',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (v) {
        if (v == 'dup') ref.read(selectionProvider.notifier).page(n.duplicatePage(index));
        if (v == 'del') {
          n.removePage(index);
          ref.read(selectionProvider.notifier).page((index - 1).clamp(0, count - 2));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(height: 34, value: 'dup', child: Text(s.duplicate)),
        if (count > 1) PopupMenuItem(height: 34, value: 'del', child: Text(s.delete, style: const TextStyle(color: AppTheme.danger))),
      ],
    );
  }
}

// Status bar

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final dev = ref.watch(deviceProvider);
    final project = ref.watch(projectProvider);
    final info = dev.info;
    final wide = MediaQuery.sizeOf(context).width >= _kWide;
    const style = TextStyle(fontSize: 11.5, color: AppTheme.muted);

    Widget item(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: child);
    Widget sep() => Container(width: 1, height: 12, color: AppTheme.line);

    final state = switch (dev.status) {
      LinkStatus.connected => s.connected,
      LinkStatus.connecting => s.connecting,
      LinkStatus.disconnected => s.offline,
    };

    final left = <Widget>[
      item(Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(on: dev.connected, size: 7),
        const SizedBox(width: 6),
        Text(state, style: style.copyWith(color: dev.connected ? AppTheme.cream : AppTheme.muted)),
      ])),
      if (dev.connected) ...[
        sep(),
        item(Text('${dev.isUsb ? 'USB' : 'Wi-Fi'} · ${dev.label}', style: style)),
      ],
      if (info != null && wide) ...[
        sep(),
        item(Text('${s.firmware} ${info.fw}', style: style)),
        sep(),
        item(Text(info.board, style: style)),
        sep(),
        item(Row(mainAxisSize: MainAxisSize.min, children: [
          Text(s.storage, style: style),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: info.fsTotal == 0 ? 0 : info.fsUsed / info.fsTotal, minHeight: 4),
            ),
          ),
          const SizedBox(width: 8),
          Text('${s.sizeKb(info.fsUsed)} / ${s.sizeMb(info.fsTotal)}', style: style),
        ])),
      ],
    ];

    return Container(
      height: _kStatusBar,
      decoration: const BoxDecoration(color: AppTheme.ink, border: Border(top: BorderSide(color: AppTheme.line))),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: left)),
        ),
        if (dev.lastSync != null && wide) ...[
          item(Text('${s.lastSync}: ${s.deckSize(dev.lastSync!.totalBytes, dev.lastSync!.quality)}', style: style)),
          sep(),
        ],
        item(Text(
            '${isLandscape(project) ? s.landscape : s.portrait} · \u2066${logicalSize(project).width.round()}×${logicalSize(project).height.round()}\u2069',
            style: style)),
      ]),
    );
  }
}
