import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/icon_catalog.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/installed_apps.dart';
import '../../../core/theme/app_theme.dart';
import '../controller/icon_library.dart';
import '../controller/image_tools.dart';
import '../models/deck_action.dart';
import '../models/deck_model.dart';

/// What the user picked: always an icon; installed apps also bring a name and launch action.
class PickedIcon {
  const PickedIcon(this.icon, {this.label, this.action});
  final KeyIcon icon;
  final String? label;
  final DeckAction? action;
}

enum IconTab { installed, apps, brands, symbols }

bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<PickedIcon?> showIconSourcePicker(BuildContext context, {IconTab? initial, String query = ''}) =>
    showDialog<PickedIcon>(context: context, builder: (_) => _IconSourceDialog(initial: initial, query: query));

class _IconSourceDialog extends StatefulWidget {
  const _IconSourceDialog({this.initial, this.query = ''});
  final IconTab? initial;
  final String query;
  @override
  State<_IconSourceDialog> createState() => _IconSourceDialogState();
}

class _IconSourceDialogState extends State<_IconSourceDialog> with SingleTickerProviderStateMixin {
  late final List<IconTab> _tabs = [if (_desktop) IconTab.installed, IconTab.apps, IconTab.brands, IconTab.symbols];
  late final TabController _tc =
      TabController(length: _tabs.length, vsync: this, initialIndex: _tabs.indexOf(widget.initial ?? _tabs.first).clamp(0, _tabs.length - 1));
  late final _search = TextEditingController(text: widget.query);
  String _q = '';
  Timer? _debounce;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _q = widget.query;
    _tc.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tc.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _finish(Future<PickedIcon?> Function() make) async {
    setState(() => _busy = true);
    final r = await make();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String label(IconTab t) => switch (t) {
          IconTab.installed => s.ar ? 'تطبيقات الجهاز' : 'On this PC',
          IconTab.apps => s.ar ? 'أيقونات التطبيقات' : 'App icons',
          IconTab.brands => s.ar ? 'العلامات التجارية' : 'Brands',
          IconTab.symbols => s.ar ? 'رموز' : 'Symbols',
        };
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(hintText: s.searchIcons, prefixIcon: const Icon(Icons.search_rounded)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 180), () => setState(() => _q = v.trim()));
              },
            ),
          ),
          TabBar(
            controller: _tc,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.lime,
            labelColor: AppTheme.lime,
            unselectedLabelColor: AppTheme.muted,
            dividerColor: AppTheme.line,
            tabs: [for (final t in _tabs) Tab(text: label(t))],
          ),
          Expanded(
            child: Stack(children: [
              TabBarView(controller: _tc, children: [
                for (final t in _tabs)
                  switch (t) {
                    IconTab.installed => _InstalledGrid(query: _q, onPick: (a) => _finish(() async {
                          final raw = a.iconPath == null ? null : await File(a.iconPath!).readAsBytes();
                          final png = raw == null ? null : await prepareIcon(raw);
                          return PickedIcon(png == null ? const KeyIcon.none() : KeyIcon.image(png),
                              label: a.name, action: DeckAction(ActionType.openApp, {'path': a.launch}));
                        })),
                    IconTab.apps => _AppIconGrid(query: _q, onPick: (a) => _finish(() async {
                          final raw = await IconLibrary.instance.appPng(a);
                          final png = raw == null ? null : await prepareIcon(raw);
                          return png == null ? null : PickedIcon(KeyIcon.image(png), label: a.title);
                        })),
                    IconTab.brands => _BrandGrid(query: _q, onPick: (b) => _finish(() async {
                          final png = await IconLibrary.instance.brandPng(b);
                          return PickedIcon(KeyIcon.image(png), label: b.title);
                        })),
                    IconTab.symbols => _SymbolGrid(query: _q, onPick: (cp) => Navigator.pop(context, PickedIcon(KeyIcon.glyph(cp)))),
                  },
              ]),
              if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x88000000), child: Center(child: CircularProgressIndicator()))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: Text(
                  _tc.index < _tabs.length && _tabs[_tc.index] == IconTab.brands
                      ? 'Simple Icons (CC0)'
                      : (_tabs[_tc.index] == IconTab.apps ? 'Dashboard Icons, homarr-labs (Apache-2.0)' : ''),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
            ]),
          ),
        ]),
      ),
    );
  }
}

Widget _tile({required Widget child, required String tooltip, required VoidCallback onTap, String? caption}) => Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rControl),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(AppTheme.rControl), border: Border.all(color: AppTheme.line)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 40, height: 40, child: Center(child: child)),
            if (caption != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ),
          ]),
        ),
      ),
    );

const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 92, mainAxisSpacing: 8, crossAxisSpacing: 8);

class _BrandGrid extends StatelessWidget {
  const _BrandGrid({required this.query, required this.onPick});
  final String query;
  final ValueChanged<BrandIcon> onPick;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: IconLibrary.instance.searchBrands(query),
        builder: (_, snap) {
          final items = snap.data ?? const <BrandIcon>[];
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: _gridDelegate,
            itemCount: items.length,
            itemBuilder: (_, i) => _tile(
              tooltip: items[i].title,
              caption: items[i].title,
              onTap: () => onPick(items[i]),
              child: SvgPicture.string(items[i].svg(), width: 34, height: 34),
            ),
          );
        },
      );
}

class _AppIconGrid extends StatelessWidget {
  const _AppIconGrid({required this.query, required this.onPick});
  final String query;
  final ValueChanged<AppIcon> onPick;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: IconLibrary.instance.searchApps(query),
        builder: (_, snap) {
          final items = snap.data ?? const <AppIcon>[];
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: _gridDelegate,
            itemCount: items.length,
            itemBuilder: (_, i) => _tile(
              tooltip: items[i].title,
              caption: items[i].title,
              onTap: () => onPick(items[i]),
              child: Image.network(items[i].pngUrl, width: 36, height: 36, cacheWidth: 72,
                  errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined, color: AppTheme.muted)),
            ),
          );
        },
      );
}

class _InstalledGrid extends StatefulWidget {
  const _InstalledGrid({required this.query, required this.onPick});
  final String query;
  final ValueChanged<InstalledApp> onPick;
  @override
  State<_InstalledGrid> createState() => _InstalledGridState();
}

class _InstalledGridState extends State<_InstalledGrid> {
  late Future<List<InstalledApp>> _apps = InstalledApps.scan();

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _apps,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final q = widget.query.toLowerCase();
          final items = snap.data!.where((a) => q.isEmpty || a.name.toLowerCase().contains(q)).toList();
          return Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'Rescan',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => setState(() => _apps = InstalledApps.scan(refresh: true)),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: _gridDelegate,
                itemCount: items.length,
                itemBuilder: (_, i) => _tile(
                  tooltip: items[i].name,
                  caption: items[i].name,
                  onTap: () => widget.onPick(items[i]),
                  child: items[i].iconPath != null
                      ? Image.file(File(items[i].iconPath!), width: 36, height: 36, cacheWidth: 72)
                      : const Icon(Icons.apps_rounded, color: AppTheme.muted),
                ),
              ),
            ),
          ]);
        },
      );
}

class _SymbolGrid extends StatelessWidget {
  const _SymbolGrid({required this.query, required this.onPick});
  final String query;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final items = kIconCatalog.where((e) => query.isEmpty || e.$2.contains(query.toLowerCase())).toList();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60, mainAxisSpacing: 6, crossAxisSpacing: 6),
      itemCount: items.length,
      itemBuilder: (_, i) => Tooltip(
        message: items[i].$2.split(' ').first,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          onTap: () => onPick(items[i].$1.codePoint),
          child: Ink(
            decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(AppTheme.rControl)),
            child: Icon(items[i].$1, color: AppTheme.cream),
          ),
        ),
      ),
    );
  }
}
