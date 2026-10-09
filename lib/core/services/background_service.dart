import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the desktop app running in the system tray. It starts with the
/// computer and closing the window only hides it, so deck keys always run.
class BackgroundService with TrayListener, WindowListener {
  BackgroundService._();
  static final instance = BackgroundService._();

  static bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runName = 'OpenDeck';

  bool _quitting = false;

  Future<void> init({required bool startHidden}) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    if (startHidden) await windowManager.hide();

    trayManager.addListener(this);
    await trayManager.setIcon(Platform.isWindows ? 'assets/logo/tray.ico' : 'assets/logo/tray.png');
    await trayManager.setToolTip('OpenDeck');
    await _buildMenu();

    // Start with the computer by default on first run. The tray menu and settings can turn it off.
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('autostartInit') ?? false)) {
      await setStartWithComputer(true);
      await prefs.setBool('autostartInit', true);
    }
  }

  Future<void> _buildMenu() async {
    final auto = await startWithComputer();
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: 'Open OpenDeck'),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'autostart', label: 'Start with Windows', checked: auto),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    _quitting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // Start with the computer: Windows only for now (registry Run key).
  Future<bool> startWithComputer() async {
    if (!Platform.isWindows) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _runName]);
    return r.exitCode == 0;
  }

  Future<void> setStartWithComputer(bool on) async {
    if (!Platform.isWindows) return;
    try {
      if (on) {
        await Process.run('reg', ['add', _runKey, '/v', _runName, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" --background', '/f']);
      } else {
        await Process.run('reg', ['delete', _runKey, '/v', _runName, '/f']);
      }
    } catch (e) {
      debugPrint('autostart: $e');
    }
    await _buildMenu();
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    await windowManager.hide(); // keep running in the tray
  }

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open':
        await show();
      case 'autostart':
        await setStartWithComputer(!(await startWithComputer()));
      case 'quit':
        await quit();
    }
  }
}
