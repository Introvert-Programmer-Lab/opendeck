// Step log for firmware installs, written to disk line by line so the last
// line survives even if the process dies in native code. Works from any
// isolate (no platform channels).
import 'dart:io';

class FlashLog {
  static RandomAccessFile? _file;
  static bool _failed = false;

  /// %LOCALAPPDATA%\OpenDeck\flash.log on Windows, ~/.opendeck/flash.log elsewhere.
  static String get path {
    final env = Platform.environment;
    final base = Platform.isWindows
        ? (env['LOCALAPPDATA'] ?? env['APPDATA'] ?? Directory.systemTemp.path)
        : '${env['HOME'] ?? Directory.systemTemp.path}/.opendeck';
    return Platform.isWindows ? '$base\\OpenDeck\\flash.log' : '$base/flash.log';
  }

  static void line(String message) {
    if (_failed || Platform.isAndroid) return;
    try {
      if (_file == null) {
        final f = File(path);
        f.parent.createSync(recursive: true);
        // Keep the file small: start over once it passes 1 MB.
        final mode = f.existsSync() && f.lengthSync() > 1 << 20 ? FileMode.writeOnly : FileMode.writeOnlyAppend;
        _file = f.openSync(mode: mode);
      }
      _file!
        ..writeStringSync('${DateTime.now().toIso8601String()} $message\n')
        ..flushSync();
    } catch (_) {
      _failed = true; // logging must never break the install
    }
  }
}
