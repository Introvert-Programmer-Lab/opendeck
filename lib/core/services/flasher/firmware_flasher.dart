import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'board_detect.dart';
import 'boards.dart';
import 'esp_loader.dart';
import 'flash_log.dart';
import 'flash_port.dart';

export 'board_detect.dart' show Detection, Unsupported, ProbeFacts;
export 'boards.dart';

const kRepo = 'Introvert-Programmer-Lab/opendeck';

enum FlashStage { download, findBoard, bootloader, connect, identify, write, verify, restart, done }

enum FlashError { noBoard, portBusy, noBootloader, download, badImage, wrongBoard, noStock, failed }

class FlashProgress {
  const FlashProgress(this.stage, {this.fraction, this.detail = ''});
  final FlashStage stage;
  final double? fraction;
  final String detail;
}

class FlashFailure implements Exception {
  const FlashFailure(this.error, [this.detail = '']);
  final FlashError error;
  final String detail;
  @override
  String toString() => detail.isEmpty ? error.name : detail;
}

class FirmwareImage {
  const FirmwareImage(this.bytes, this.source);
  final Uint8List bytes;

  /// Where it came from: "bundled", "latest release" or a file path.
  final String source;
}

/// Finds the firmware for [board]: the copy bundled with the app if there is
/// one, otherwise the latest GitHub release.
Future<FirmwareImage> loadFirmware(BoardProfile board, {void Function(double? progress)? onProgress}) async {
  try {
    final data = await rootBundle.load('assets/firmware/${board.firmwareFile}');
    return FirmwareImage(_checked(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)), 'bundled');
  } on FlashFailure {
    rethrow;
  } catch (_) {
    // Not bundled in this build: fetch it.
  }
  final url = 'https://github.com/$kRepo/releases/latest/download/${board.firmwareFile}';
  final client = HttpClient()..userAgent = 'OpenDeck';
  try {
    final bytes = await _download(client, Uri.parse(url), onProgress);
    if (bytes == null) throw const FlashFailure(FlashError.download, 'No firmware in the latest release yet');
    final sum = await _download(client, Uri.parse('$url.sha256'), null);
    if (sum != null) {
      final want = ascii.decode(sum, allowInvalid: true).trim().split(RegExp(r'\s+')).first.toLowerCase();
      if (want.length == 64 && sha256.convert(bytes).toString() != want) {
        throw const FlashFailure(FlashError.download, 'The download is damaged (checksum mismatch)');
      }
    }
    return FirmwareImage(_checked(bytes), 'latest release');
  } on FlashFailure {
    rethrow;
  } on Object catch (e) {
    throw FlashFailure(FlashError.download, '$e');
  } finally {
    client.close(force: true);
  }
}

/// The board's factory firmware: bundled as `assets/firmware/stock/<board>.bin`
/// if a build includes it, otherwise downloaded from [BoardProfile.stockUrl].
/// Either way the SHA-256 must match before anything is flashed.
Future<FirmwareImage> loadStockFirmware(BoardProfile board, {void Function(double? progress)? onProgress}) async {
  if (!board.hasStockFirmware) throw const FlashFailure(FlashError.download, 'No factory firmware is known for this board');
  Uint8List? bytes;
  var source = 'bundled';
  try {
    final data = await rootBundle.load('assets/firmware/stock/${board.id}.bin');
    bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    source = board.stockUrl!;
    final client = HttpClient()..userAgent = 'OpenDeck';
    try {
      bytes = await _download(client, Uri.parse(board.stockUrl!), onProgress);
    } on Object catch (e) {
      throw FlashFailure(FlashError.download, '$e');
    } finally {
      client.close(force: true);
    }
    if (bytes == null) throw const FlashFailure(FlashError.download, 'The factory firmware is no longer at its download address');
  }
  if (sha256.convert(bytes).toString() != board.stockSha256) {
    throw const FlashFailure(FlashError.download, 'The factory firmware does not match its checksum');
  }
  return FirmwareImage(_checked(bytes), source);
}

Future<FirmwareImage> loadFirmwareFile(String path) async => FirmwareImage(_checked(await File(path).readAsBytes()), path);

Uint8List _checked(Uint8List image) {
  if (image.length < 0x10000 || imageChip(image) == null) throw const FlashFailure(FlashError.badImage);
  return image;
}

/// The chip a merged image is built for, from its bootloader's header: at 0x0
/// on the ESP32-S3, at 0x1000 on the ESP32. Null when it is neither.
ChipFamily? imageChip(Uint8List image) {
  int? chipId(int at) =>
      image.length > at + 14 && image[at] == 0xE9 ? image[at + 12] | (image[at + 13] << 8) : null;
  if (chipId(0) == 9) return ChipFamily.esp32s3;
  if (chipId(0x1000) == 0) return ChipFamily.esp32;
  return null;
}

Future<Uint8List?> _download(HttpClient client, Uri url, void Function(double?)? onProgress) async {
  final req = await client.getUrl(url);
  final res = await req.close();
  if (res.statusCode == 404) {
    await res.drain<void>();
    return null;
  }
  if (res.statusCode != 200) {
    await res.drain<void>();
    throw HttpException('HTTP ${res.statusCode}', uri: url);
  }
  final total = res.contentLength;
  final out = BytesBuilder(copy: false);
  await for (final chunk in res) {
    out.add(chunk);
    onProgress?.call(total > 0 ? out.length / total : null);
  }
  return out.takeBytes();
}

/// Finds out which board is plugged in. On desktop the serial work runs in a
/// background isolate because the port calls block.
Future<Detection> detectBoard(void Function(FlashProgress) onProgress) => _offMain(runDetect, onProgress);

/// Writes [image] to the first board found. With a [board], refuses to write
/// unless the chip and flash match it.
Future<void> flashBoard(Uint8List image, BoardProfile? board, void Function(FlashProgress) onProgress) =>
    _offMain(_FlashJob(image, board).call, onProgress);

typedef UsbJob<T> = Future<T> Function(UsbBackend usb, void Function(FlashProgress) report);

class _FlashJob {
  _FlashJob(this.image, this.board);
  final Uint8List image;
  final BoardProfile? board;
  Future<void> call(UsbBackend usb, void Function(FlashProgress) report) => runFlash(usb, image, board, report);
}

Future<T> _offMain<T>(UsbJob<T> job, void Function(FlashProgress) onProgress) async {
  if (Platform.isAndroid) return job(AndroidUsbBackend(), onProgress);
  final progress = ReceivePort();
  progress.listen((m) {
    if (m is List && m.length == 3) {
      onProgress(FlashProgress(FlashStage.values[m[0] as int], fraction: m[1] as double?, detail: m[2] as String));
    }
  });
  try {
    return await runInIsolate(job, progress.sendPort, DesktopUsbBackend.new);
  } finally {
    progress.close();
  }
}

/// Runs [job] in a new isolate, reporting progress to [progress]. Kept apart
/// from the caller so the closure sent to the isolate captures only these
/// arguments: anything else in scope (UI state, providers) cannot be sent.
Future<T> runInIsolate<T>(UsbJob<T> job, SendPort progress, UsbBackend Function() backend) => Isolate.run(() {
      FlashLog.line('worker: started');
      return job(backend(), (p) {
        if (p.stage != FlashStage.write) FlashLog.line('stage: ${p.stage.name} ${p.detail}');
        progress.send([p.stage.index, p.fraction, p.detail]);
      });
    });

class _Session {
  _Session(this.port, this.fp, this.loader);
  final UsbPortInfo port;
  final FlashPort fp;
  final EspLoader loader;
}

/// Finds the board, gets it into the ROM bootloader and identifies the chip.
Future<_Session> _open(UsbBackend usb, void Function(FlashProgress) onProgress) async {
  onProgress(const FlashProgress(FlashStage.findBoard));
  var port = _pick(await usb.list());
  FlashLog.line('picked: ${port ?? 'none'}');
  if (port == null) throw const FlashFailure(FlashError.noBoard);

  if (!port.isUsbJtag && port.isEspressif) {
    // Running firmware with its own USB stack: ask it to restart into the
    // ROM bootloader, which then shows up as the USB-Serial/JTAG port.
    onProgress(FlashProgress(FlashStage.bootloader, detail: port.id));
    await _requestBootloader(usb, port);
    port = await _waitFor(usb, (p) => p.isUsbJtag, const Duration(seconds: 12));
    if (port == null) throw const FlashFailure(FlashError.noBootloader);
  }

  onProgress(FlashProgress(FlashStage.connect, detail: port.id));
  final FlashPort fp;
  try {
    fp = await usb.open(port);
  } on PortBusyException catch (e) {
    throw FlashFailure(FlashError.portBusy, e.toString());
  }
  final loader = EspLoader(fp, usbJtag: port.isEspressif);
  try {
    var synced = await loader.sync(attempts: 3);
    FlashLog.line('sync: ${synced ? 'ok' : 'no answer'}');
    for (var i = 0; i < 3 && !synced; i++) {
      FlashLog.line('reset into bootloader (${port.isEspressif ? 'USB-Serial/JTAG' : 'bridge'}), try ${i + 1}');
      port.isEspressif ? await loader.resetUsbJtag() : await loader.resetClassic();
      synced = await loader.sync();
      FlashLog.line('sync: ${synced ? 'ok' : 'no answer'}');
    }
    if (!synced) throw const FlashFailure(FlashError.noBootloader);
    return _Session(port, fp, loader);
  } on Object {
    await fp.close();
    rethrow;
  }
}

/// Identifies the plugged-in board without writing anything.
Future<Detection> runDetect(UsbBackend usb, void Function(FlashProgress) onProgress) async {
  final s = await _open(usb, onProgress);
  try {
    try {
      await s.loader.connect();
    } on FlashException catch (e) {
      return Detection(unsupported: Unsupported.chip, detail: e.message);
    }
    final size = await s.loader.flashSize();
    await s.loader.changeBaud(460800);
    onProgress(const FlashProgress(FlashStage.identify));
    final link = s.port.isEspressif ? UsbLink.native : UsbLink.bridge;
    return decide(await probeBoard(s.loader, link, size));
  } on FlashException catch (e) {
    throw FlashFailure(FlashError.failed, e.message);
  } on TimeoutException {
    throw const FlashFailure(FlashError.failed, 'The board stopped answering. Check the cable and try again.');
  } finally {
    await s.fp.close();
  }
}

/// The whole flash job, independent of how the USB port is reached.
Future<void> runFlash(UsbBackend usb, Uint8List image, BoardProfile? board, void Function(FlashProgress) onProgress) async {
  final s = await _open(usb, onProgress);
  final loader = s.loader;
  try {
    await loader.connect();
    // Last check before anything is erased: the image, the chip and the flash
    // must all be what the chosen board has.
    final size = await loader.flashSize();
    if (imageChip(image) != loader.chip) {
      throw const FlashFailure(FlashError.wrongBoard, 'This firmware is built for a different chip than the one on the board.');
    }
    if (board != null && board.chip != loader.chip) {
      throw FlashFailure(FlashError.wrongBoard, 'The plugged-in board is not a ${board.name}.');
    }
    final need = board?.flashSize ?? image.length;
    if (size != 0 && size < need) {
      throw FlashFailure(FlashError.wrongBoard, 'The board has ${size >> 20} MB of flash; this firmware needs ${need >> 20} MB.');
    }
    await loader.setFlashSize(size != 0 ? size : (board?.flashSize ?? 4 << 20));
    await loader.changeBaud(460800);

    final segments = splitImage(image);
    final total = segments.fold<int>(0, (a, s) => a + s.data.length);
    var done = 0;
    onProgress(const FlashProgress(FlashStage.write, fraction: 0));
    for (final seg in segments) {
      await loader.writeSegment(seg,
          onBlock: (n) => onProgress(FlashProgress(FlashStage.write, fraction: (done + n) / total)));
      done += seg.data.length;
    }
    onProgress(const FlashProgress(FlashStage.verify));
    for (final seg in segments) {
      await loader.verifySegment(seg);
    }
    onProgress(const FlashProgress(FlashStage.restart));
    await loader.hardReset();
  } on FlashException catch (e) {
    throw FlashFailure(FlashError.failed, e.message);
  } on TimeoutException {
    throw const FlashFailure(FlashError.failed, 'The board stopped answering. Check the cable and try again.');
  } finally {
    await s.fp.close();
  }
  onProgress(const FlashProgress(FlashStage.done, fraction: 1));
}

/// Prefers the USB-Serial/JTAG port, then the OpenDeck firmware, then any
/// other Espressif device, then common USB-UART bridges.
UsbPortInfo? _pick(List<UsbPortInfo> ports) {
  const bridges = {0x1A86, 0x10C4, 0x0403}; // WCH, Silicon Labs, FTDI
  for (final test in <bool Function(UsbPortInfo)>[
    (p) => p.isUsbJtag,
    (p) => p.isOpenDeck,
    (p) => p.isEspressif,
    (p) => bridges.contains(p.vid),
  ]) {
    for (final p in ports) {
      if (test(p)) return p;
    }
  }
  return null;
}

Future<void> _requestBootloader(UsbBackend usb, UsbPortInfo port) async {
  try {
    final fp = await usb.open(port);
    try {
      if (port.isOpenDeck) {
        await fp.write(Uint8List.fromList(utf8.encode('{"t":"dfu"}\n')));
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } finally {
      await fp.close();
    }
  } catch (_) {
    // The port may vanish mid-write when the board restarts. That is the goal.
  }
  await Future.delayed(const Duration(milliseconds: 1500));
  final still = (await usb.list()).any((p) => p.id == port.id && p.pid == port.pid);
  if (!still) return;
  // Other firmware (Arduino, older OpenDeck): the "1200 baud touch" restarts into the bootloader.
  try {
    final fp = await usb.open(port, baud: 1200);
    await Future.delayed(const Duration(milliseconds: 100));
    await fp.close();
  } catch (_) {}
}

Future<UsbPortInfo?> _waitFor(UsbBackend usb, bool Function(UsbPortInfo) test, Duration timeout) async {
  final until = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(until)) {
    for (final p in await usb.list()) {
      if (test(p)) return p;
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return null;
}
