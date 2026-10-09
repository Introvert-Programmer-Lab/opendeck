import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/app_focus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../device/providers/device_provider.dart';
import '../controller/image_tools.dart';
import '../models/deck_action.dart';
import '../models/deck_model.dart';
import '../providers/project_provider.dart';
import 'icon_picker.dart';
import 'pickers.dart';

/// Text field that keeps its own controller per [identity] so typing doesn't jump.
class BoundField extends StatefulWidget {
  const BoundField({super.key, required this.identity, required this.value, required this.onChanged, this.label, this.hint, this.suffix});
  final Object identity;
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final Widget? suffix;

  @override
  State<BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<BoundField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(BoundField old) {
    super.didUpdateWidget(old);
    // Only differs while typing if the value was changed elsewhere.
    if (old.identity != widget.identity || _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon: widget.suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
    return widget.label == null ? field : FieldRow(label: widget.label!, child: field);
  }
}

class KeyInspector extends ConsumerWidget {
  const KeyInspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final sel = ref.watch(selectionProvider);
    final project = ref.watch(projectProvider);
    final notifier = ref.read(projectProvider.notifier);
    final page = sel.page.clamp(0, project.pages.length - 1);
    final sections = project.pages[page].sections;
    if (!sel.hasSlot || sel.section! >= sections.length || sel.slot! >= sections[sel.section!].keys.length) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(s.noKeySelected, divider: false),
        HelpText(s.selectKeyHint),
      ]);
    }
    final section = sections[sel.section!];
    final key = section.keys[sel.slot!];

    if (key == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(s.key, divider: false),
        HelpText(s.selectKeyHint),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(s.addKey),
          onPressed: () => notifier.setKey(page, sel.section!, sel.slot!,
              DeckKey(id: newId(), icon: KeyIcon.glyph(Icons.apps_rounded.codePoint), label: s.key)),
        ),
      ]);
    }

    void upd(DeckKey Function(DeckKey k) fn) => notifier.updateKey(page, sel.section!, sel.slot!, fn);
    final t = project.theme;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(s.key,
          divider: false,
          trailing: IconButton(
            tooltip: s.clearKey,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => notifier.setKey(page, sel.section!, sel.slot!, null),
          )),
      _IconEditor(
        icon: key.icon,
        bg: key.background ?? t.keyColor,
        fg: key.foreground ?? t.foreground,
        query: key.label,
        onChanged: (i) => upd((k) => k.copyWith(icon: i)),
        onPicked: (p) => upd((k) => applyPicked(k, p, s)),
      ),
      const SizedBox(height: 10),
      BoundField(identity: key.id, value: key.label, label: s.label, onChanged: (v) => upd((k) => k.copyWith(label: v))),
      FieldRow(
        label: s.showLabel,
        child: CompactSwitch(value: key.showLabel, onChanged: (v) => upd((k) => k.copyWith(showLabel: v))),
      ),
      SectionLabel(s.colors),
      FieldRow(
        label: s.keyColor,
        child: ColorField(value: key.background, fallback: t.keyColor, onChanged: (c) => upd((k) => k.copyWith(background: () => c))),
      ),
      FieldRow(
        label: s.iconColor,
        child: ColorField(value: key.foreground, fallback: t.foreground, onChanged: (c) => upd((k) => k.copyWith(foreground: () => c))),
      ),
      SectionLabel(s.action),
      _ActionEditor(
        identity: key.id,
        action: key.action,
        pageCount: project.pages.length,
        onChanged: (a) => upd((k) => k.copyWith(action: a)),
        onChooseApp: () async {
          final p = await showIconSourcePicker(context, initial: IconTab.installed);
          if (p != null) upd((k) => applyPicked(k, p, s));
        },
      ),
      if (key.hasAltState) ...[
        SectionLabel(s.onState),
        HelpText(s.onStateHint),
        const SizedBox(height: 6),
        _IconEditor(
          icon: key.altIcon.isNone ? key.icon : key.altIcon,
          bg: key.altBackground ?? key.background ?? t.keyColor,
          fg: key.altForeground ?? key.foreground ?? t.foreground,
          onChanged: (i) => upd((k) => k.copyWith(altIcon: i)),
          onPicked: (p) => upd((k) => k.copyWith(altIcon: p.icon)),
        ),
        const SizedBox(height: 10),
        BoundField(identity: '${key.id}alt', value: key.altLabel, label: s.label, onChanged: (v) => upd((k) => k.copyWith(altLabel: v))),
        FieldRow(
          label: s.keyColor,
          child: ColorField(
              value: key.altBackground, fallback: key.background ?? t.keyColor, onChanged: (c) => upd((k) => k.copyWith(altBackground: () => c))),
        ),
        FieldRow(
          label: s.iconColor,
          child: ColorField(
              value: key.altForeground, fallback: key.foreground ?? t.foreground, onChanged: (c) => upd((k) => k.copyWith(altForeground: () => c))),
        ),
      ],
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.play_arrow, size: 16),
        label: Text(s.test),
        onPressed: key.action.type == ActionType.none ? null : () => ref.read(deviceProvider.notifier).testAction(key.action),
      ),
    ]);
  }
}

/// Installed apps bring their name and launch command; brand/app icons suggest a
/// label only when the key has none yet.
DeckKey applyPicked(DeckKey k, PickedIcon p, S s) {
  final genericLabel = k.label.isEmpty || k.label == s.key;
  return k.copyWith(
    icon: p.icon,
    label: p.label != null && (p.action != null || genericLabel) ? p.label : k.label,
    action: p.action ?? k.action,
  );
}

class _IconEditor extends StatelessWidget {
  const _IconEditor({required this.icon, required this.bg, required this.fg, required this.onChanged, required this.onPicked, this.query = ''});
  final KeyIcon icon;
  final int bg, fg;
  final String query;
  final ValueChanged<KeyIcon> onChanged;
  final ValueChanged<PickedIcon> onPicked;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget preview;
    if (icon.image != null) {
      preview = ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(icon.image!, width: 36, height: 36, fit: BoxFit.cover));
    } else if (icon.codePoint != null) {
      preview = Icon(iconFor(icon.codePoint!), color: Color(fg), size: 30);
    } else {
      preview = const Icon(Icons.block, color: AppTheme.faint);
    }
    return Row(children: [
      Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Color(bg), borderRadius: BorderRadius.circular(AppTheme.rPanel), border: Border.all(color: AppTheme.line)),
        child: preview,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton(
            child: Text(s.pickIcon),
            onPressed: () async {
              final p = await showIconSourcePicker(context, query: query);
              if (p != null) onPicked(p);
            },
          ),
          OutlinedButton(
            child: Text(s.imageIcon),
            onPressed: () async {
              final raw = await pickImageBytes();
              if (raw == null) return;
              final small = await prepareIcon(raw);
              if (small != null) onChanged(KeyIcon.image(small));
            },
          ),
          if (!icon.isNone)
            TextButton(onPressed: () => onChanged(const KeyIcon.none()), child: Text(s.noIcon)),
        ]),
      ),
    ]);
  }
}

class _ActionEditor extends StatelessWidget {
  const _ActionEditor({required this.identity, required this.action, required this.pageCount, required this.onChanged, this.onChooseApp});
  final VoidCallback? onChooseApp;
  final Object identity;
  final DeckAction action;
  final int pageCount;
  final ValueChanged<DeckAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    void setParam(String k, String v) => onChanged(action.copyWith(params: {...action.params, k: v}));
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    Widget switchIfOpen() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldRow(
            label: s.switchIfOpen,
            child: CompactSwitch(
              value: action.param('newWindow') != 'true',
              onChanged: (v) {
                final params = {...action.params}..remove('newWindow');
                if (!v) params['newWindow'] = 'true';
                onChanged(action.copyWith(params: params));
              },
            ),
          ),
          HelpText(s.switchIfOpenHint),
        ]);

    final fields = <Widget>[];
    switch (action.type) {
      case ActionType.openApp:
        if (onChooseApp != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
          fields.add(Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.apps, size: 16),
              label: Text(s.chooseAppOnPc),
              onPressed: onChooseApp,
            ),
          ));
        }
        fields.add(BoundField(
          identity: '$identity-path',
          value: action.param('path'),
          label: s.appPath,
          hint: s.appPathHint,
          onChanged: (v) => setParam('path', v),
          suffix: (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              ? IconButton(
                  tooltip: s.browse,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  onPressed: () async {
                    final p = (await FilePicker.pickFile())?.path;
                    if (p != null) setParam('path', p);
                  },
                )
              : null,
        ));
        fields.add(BoundField(identity: '$identity-args', value: action.param('args'), label: s.arguments, onChanged: (v) => setParam('args', v)));
        if (desktop) fields.add(switchIfOpen());
      case ActionType.openUrl:
        fields.add(BoundField(identity: '$identity-url', value: action.param('url'), label: s.url, hint: 'https://', onChanged: (v) => setParam('url', v)));
        // App links like discord: or spotify: can switch to the running app; web pages always open a tab.
        final scheme = schemeOf(action.param('url'));
        if (desktop && scheme != null && !webSchemes.contains(scheme)) fields.add(switchIfOpen());
      case ActionType.runCommand:
        fields.add(BoundField(identity: '$identity-cmd', value: action.param('command'), label: s.command, onChanged: (v) => setParam('command', v)));
      case ActionType.hotkey:
        fields.add(BoundField(
            identity: '$identity-keys', value: action.param('keys'), label: s.shortcut, hint: s.shortcutHint, onChanged: (v) => setParam('keys', v)));
      case ActionType.typeText:
        fields.add(BoundField(identity: '$identity-text', value: action.param('text'), label: s.text, onChanged: (v) => setParam('text', v)));
      case ActionType.media:
        fields.add(FieldRow(
          label: s.mediaOp,
          child: DropdownButtonFormField<String>(
            initialValue: MediaOp.values.any((o) => o.name == action.param('op')) ? action.param('op') : MediaOp.playPause.name,
            isExpanded: true,
            style: const TextStyle(fontSize: 13, color: AppTheme.cream),
            items: [for (final o in MediaOp.values) DropdownMenuItem(value: o.name, child: Text(s.mediaName(o.name)))],
            onChanged: (v) => setParam('op', v!),
          ),
        ));
      case ActionType.gotoPage:
        fields.add(FieldRow(
          label: s.pageNumber,
          child: DropdownButtonFormField<String>(
            initialValue: '${(int.tryParse(action.param('page')) ?? 0).clamp(0, pageCount - 1)}',
            isExpanded: true,
            style: const TextStyle(fontSize: 13, color: AppTheme.cream),
            items: [for (var i = 0; i < pageCount; i++) DropdownMenuItem(value: '$i', child: Text('${s.page} ${i + 1}'))],
            onChanged: (v) => setParam('page', v!),
          ),
        ));
      default:
        break;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FieldRow(
        label: s.actionType,
        child: DropdownButtonFormField<ActionType>(
          initialValue: action.type,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppTheme.cream),
          items: [for (final t in ActionType.values) DropdownMenuItem(value: t, child: Text(s.actionName(t.name)))],
          onChanged: (t) {
            if (t == null) return;
            final params = t == ActionType.media ? {'op': MediaOp.playPause.name} : <String, String>{};
            onChanged(DeckAction(t, params));
          },
        ),
      ),
      for (final f in fields) Padding(padding: const EdgeInsets.only(top: 4), child: f),
    ]);
  }
}
