import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/flasher/firmware_flasher.dart';
import '../../../core/services/flasher/flash_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../providers/flash_provider.dart';

bool get canFlashFirmware => Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isAndroid;

/// Install button, progress and errors for the one-click firmware install.
/// The board is identified first; nothing is written to a board that does
/// not match a supported one.
class FlashPanel extends ConsumerWidget {
  const FlashPanel({super.key});

  Future<void> _pickFile(WidgetRef ref) async {
    final f = await FilePicker.pickFile(
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const ['bin'],
    );
    if (f?.path != null) await ref.read(flashProvider.notifier).install(filePath: f!.path);
  }

  Future<void> _restoreStock(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.restoreStock),
        content: Text(s.restoreStockConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.restore)),
        ],
      ),
    );
    if (ok == true) await ref.read(flashProvider.notifier).install(stock: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final st = ref.watch(flashProvider);
    final ctl = ref.read(flashProvider.notifier);

    if (!canFlashFirmware) return HelpText(s.flashUnsupported);

    final progress = st.progress;
    final board = st.board;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.flashIntro, style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5)),
      if (Platform.isAndroid) HelpText(s.flashAndroidHint),
      const SizedBox(height: 16),
      if (board != null && (st.running || st.done)) ...[
        FieldRow(label: s.board, child: Text(board.title, style: const TextStyle(fontSize: 13))),
        if (!board.verified) HelpText(s.untestedBoard),
        const SizedBox(height: 8),
      ],
      if (st.running && progress != null) ...[
        Row(children: [
          Expanded(child: Text(s.flashStage(progress.stage.name), style: const TextStyle(fontWeight: FontWeight.w600))),
          if (progress.fraction != null && progress.stage == FlashStage.write)
            Text('${(progress.fraction! * 100).floor()}%', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(minHeight: 6, value: progress.fraction),
        ),
        if (progress.detail.isNotEmpty) HelpText(progress.detail),
      ] else if (st.done) ...[
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.lime, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(st.stock ? s.stockDone : s.flashDone, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ] else ...[
        if (st.needsChoice) _Choice(detection: st.detection!, stock: st.stock),
        if (st.failure != null)
          _Notice(
            title: s.flashError(st.failure!.error.name),
            children: [
              if (st.failure!.detail.isNotEmpty)
                SelectableText(st.failure!.detail, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              if (_replugHelps.contains(st.failure!.error)) _ReplugHint(s.flashReplugHint),
              if (st.failure!.error == FlashError.failed) HelpText(s.flashBootHint),
              HelpText('Log: ${FlashLog.path}'),
            ],
          ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: Text((st.failure != null || st.needsChoice) && !st.stock ? s.tryAgain : s.installFirmware),
            onPressed: () => ctl.install(),
          ),
          TextButton(onPressed: () => _pickFile(ref), child: Text(s.useFirmwareFile)),
          if (BoardProfile.all.any((b) => b.hasStockFirmware))
            TextButton(onPressed: () => _restoreStock(context, ref), child: Text(s.restoreStock)),
        ]),
      ],
    ]);
  }
}

/// After detection: pick between boards that look the same, or explain why
/// the board is not supported.
class _Choice extends ConsumerStatefulWidget {
  const _Choice({required this.detection, required this.stock});
  final Detection detection;
  final bool stock;

  @override
  ConsumerState<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends ConsumerState<_Choice> {
  bool _override = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final d = widget.detection;
    void install(BoardProfile b) => ref.read(flashProvider.notifier).install(board: b, stock: widget.stock);
    final facts = d.facts?.summary ?? const <String>[];

    if (d.supported) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.chooseBoard, style: const TextStyle(fontWeight: FontWeight.w600)),
          HelpText(s.chooseBoardHint),
          const SizedBox(height: 6),
          for (final b in d.boards) _BoardTile(board: b, onTap: () => install(b)),
        ]),
      );
    }

    return _Notice(title: s.boardUnsupported, children: [
      Text(s.unsupportedReason(d.unsupported?.name ?? ''), style: const TextStyle(fontSize: 13, height: 1.45)),
      if (d.detail.isNotEmpty) HelpText(d.detail),
      if (facts.isNotEmpty) HelpText('${s.whatWasFound}: ${facts.join(' · ')}'),
      const SizedBox(height: 4),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          title: Text(s.supportedBoards, style: const TextStyle(fontSize: 13)),
          children: [
            for (final b in BoardProfile.all)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(b.title, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.6)),
              ),
          ],
        ),
      ),
      // Same chip, USB link and flash as a supported board: let the user decide.
      if (d.family.isNotEmpty) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _override,
          onChanged: (v) => setState(() => _override = v ?? false),
          title: Text(s.boardOverride, style: const TextStyle(fontSize: 13)),
          subtitle: Text(s.boardOverrideWarning, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ),
        if (_override)
          for (final b in d.family) _BoardTile(board: b, onTap: () => install(b)),
      ],
    ]);
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.board, required this.onTap});
  final BoardProfile board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onPressed: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.installFor(board.title), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  '${board.width}x${board.height}',
                  board.touchKind,
                  ...board.aliases.take(2),
                ].join(' · '),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ]),
          ),
          const Icon(Icons.bolt_rounded, size: 18),
        ]),
      ),
    );
  }
}

/// Errors a board stuck in a bad USB state can cause; unplugging it resets it.
const _replugHelps = {FlashError.noBoard, FlashError.portBusy, FlashError.noBootloader, FlashError.failed};

class _ReplugHint extends StatelessWidget {
  const _ReplugHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.6)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.usb_rounded, color: AppTheme.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
          ),
        ]),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...children,
        ]),
      );
}
