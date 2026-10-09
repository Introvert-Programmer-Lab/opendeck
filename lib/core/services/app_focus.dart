/// Decides which open windows belong to an "open app" target, so a key press
/// can switch to the app when it is already running (like clicking its
/// taskbar button) instead of starting it again.
class AppMatcher {
  const AppMatcher({this.aumid, this.exePath, this.exeName});

  /// Explicit AppUserModelID, as used in `shell:AppsFolder\<id>`.
  final String? aumid;

  /// Executable path, lower case with backslashes. Either a full path or, when
  /// it starts with a backslash, the trailing part of one.
  final String? exePath;

  /// Executable file name, lower case, e.g. `chrome.exe`.
  final String? exeName;

  /// Null when the target is not an app that can be switched to (a website,
  /// a folder, a document, a shortcut).
  static AppMatcher? forTarget(String target) {
    var t = target.trim();
    if (t.length > 1 && t.startsWith('"') && t.endsWith('"')) t = t.substring(1, t.length - 1);
    if (t.isEmpty) return null;
    final lower = t.toLowerCase().replaceAll('/', r'\');

    const apps = r'shell:appsfolder\';
    if (lower.startsWith(apps)) {
      final id = lower.substring(apps.length);
      if (id.isEmpty) return null;
      String? path;
      if (id.endsWith('.exe')) {
        // Desktop apps without their own ID: "{KnownFolderGuid}\Vendor\App\app.exe".
        final close = id.indexOf(r'}\');
        path = close >= 0 ? id.substring(close + 1) : (id.contains(r'\') ? id : null);
      }
      final name = id.endsWith('.exe') ? _baseName(id) : (id == 'microsoft.windows.explorer' ? 'explorer.exe' : null);
      return AppMatcher(aumid: id, exePath: path, exeName: name);
    }

    if (lower.contains('://')) return null;
    if (lower.endsWith('.exe')) {
      final hasDir = lower.contains(r'\');
      return AppMatcher(exePath: hasDir ? lower : null, exeName: _baseName(lower));
    }
    // A bare command like "chrome", "code" or "notepad".
    if (!lower.contains(r'\') && !lower.contains(':') && !lower.contains('.') && !lower.contains(' ')) {
      return AppMatcher(exeName: '$lower.exe');
    }
    return null;
  }

  /// For protocol links like `discord:` or `spotify:`, built from the handler's
  /// registered command line (`HKCR\<scheme>\shell\open\command`).
  static AppMatcher? forProtocolCommand(String command) {
    final args = _splitCommand(command);
    if (args.isEmpty) return null;
    // Squirrel installers (Discord, Slack, Teams classic) register Update.exe
    // and name the real app after --processStart.
    final ps = args.indexWhere((a) => a.toLowerCase() == '--processstart');
    if (ps >= 0 && ps + 1 < args.length) return AppMatcher(exeName: _baseName(args[ps + 1].toLowerCase()));
    final exe = args.first.toLowerCase().replaceAll('/', r'\');
    if (!exe.endsWith('.exe')) return null;
    if (_browsers.contains(_baseName(exe))) return null;
    return AppMatcher(exePath: exe, exeName: _baseName(exe));
  }

  bool matches({required String exePath, String? aumid}) {
    final path = exePath.toLowerCase();
    final id = aumid?.toLowerCase();
    if (this.aumid != null && id != null && id == this.aumid) return true;
    final want = this.exePath;
    if (want != null) return path == want || (want.startsWith(r'\') && path.endsWith(want));
    return exeName != null && _baseName(path) == exeName;
  }

  @override
  String toString() => 'AppMatcher(aumid: $aumid, exePath: $exePath, exeName: $exeName)';
}

const _browsers = {'chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe', 'opera.exe', 'iexplore.exe'};

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

List<String> _splitCommand(String s) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (final ch in s.split('')) {
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ' ' && !quoted) {
      if (cur.isNotEmpty) out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  if (cur.isNotEmpty) out.add(cur.toString());
  return out;
}

/// Link schemes that open in the browser, where a new tab is the expected result.
const webSchemes = {'http', 'https', 'file', 'mailto', 'ftp'};

/// `discord` for "discord:" or "discord://...", null when [url] has no scheme.
String? schemeOf(String url) {
  final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(url.trim());
  if (m == null || m.group(1)!.length < 2) return null; // "C:" is a drive letter
  return m.group(1)!.toLowerCase();
}
