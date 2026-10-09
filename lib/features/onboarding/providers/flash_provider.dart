import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/flasher/firmware_flasher.dart';
import '../../../core/services/flasher/flash_log.dart';
import '../../device/providers/device_provider.dart';

class FlashState {
  const FlashState({
    this.running = false,
    this.progress,
    this.failure,
    this.done = false,
    this.stock = false,
    this.detection,
    this.board,
  });
  final bool running;
  final FlashProgress? progress;
  final FlashFailure? failure;
  final bool done;

  /// The job writes (or wrote) the manufacturer's factory firmware.
  final bool stock;

  /// What the last detection found. Kept while the user picks a board.
  final Detection? detection;

  /// The board being (or last) installed.
  final BoardProfile? board;

  /// Detection finished without settling on one board: the user decides.
  bool get needsChoice => !running && !done && failure == null && detection != null && !detection!.identified;
}

final flashProvider = NotifierProvider<FlashController, FlashState>(FlashController.new);

class FlashController extends Notifier<FlashState> {
  @override
  FlashState build() => const FlashState();

  /// Installs firmware on the plugged-in board. Without a [board] or
  /// [filePath], first identifies the board and stops there unless exactly one
  /// supported board matches. With [stock], writes the factory firmware.
  Future<void> install({BoardProfile? board, String? filePath, bool stock = false}) async {
    if (state.running) return;
    final device = ref.read(deviceProvider.notifier);
    // Board ID reported by OpenDeck firmware already on the board, if connected.
    final runningId = ref.read(deviceProvider).info?.id ?? '';
    var detection = state.detection;
    void report(FlashProgress p) =>
        state = FlashState(running: true, progress: p, stock: stock, detection: detection, board: board);

    report(const FlashProgress(FlashStage.findBoard));
    FlashLog.line('install: start (board=${board?.id ?? 'detect'}, file=${filePath != null}, stock=$stock)');
    // The app's own link would hold the USB port the flasher needs.
    await device.suspend();
    FlashLog.line('install: deck link closed');
    try {
      if (board == null && filePath == null) {
        final found = await detectBoard(report);
        detection = found;
        FlashLog.line('install: detected ${found.boards.map((b) => b.id).join(', ')} ${found.unsupported?.name ?? ''} ${found.facts?.summary.join(' | ') ?? ''}');
        final known = found.boards.where((b) => b.id == runningId).firstOrNull;
        if (!found.identified && known == null) {
          state = FlashState(detection: found, stock: stock);
          return;
        }
        board = known ?? found.boards.single;
      }
      if (stock && (board == null || !board.hasStockFirmware)) {
        throw const FlashFailure(FlashError.noStock);
      }

      void onDownload(double? f) => report(FlashProgress(FlashStage.download, fraction: f));
      report(const FlashProgress(FlashStage.download));
      final fw = filePath != null
          ? await loadFirmwareFile(filePath)
          : stock
              ? await loadStockFirmware(board!, onProgress: onDownload)
              : await loadFirmware(board!, onProgress: onDownload);
      await flashBoard(fw.bytes, filePath != null ? null : board, report);
      FlashLog.line('install: done');
      state = FlashState(done: true, stock: stock, board: board, progress: const FlashProgress(FlashStage.done, fraction: 1));
    } on FlashFailure catch (e) {
      FlashLog.line('install: failed ${e.error.name} ${e.detail}');
      state = FlashState(failure: e, stock: stock, board: board);
    } on Object catch (e) {
      FlashLog.line('install: error $e');
      state = FlashState(failure: FlashFailure(FlashError.failed, '$e'), stock: stock, board: board);
    } finally {
      await device.resume();
    }
  }

  void reset() {
    if (!state.running) state = const FlashState();
  }
}
