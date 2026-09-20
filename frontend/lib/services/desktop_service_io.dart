import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopService with WindowListener, TrayListener {
  DesktopService._();
  static final DesktopService instance = DesktopService._();

  SharedPreferences? _preferences;
  bool _initialized = false;

  bool get supported => Platform.isWindows || Platform.isMacOS;

  Future<void> initialize(SharedPreferences preferences) async {
    if (!supported || _initialized) return;
    _initialized = true;
    _preferences = preferences;

    await windowManager.ensureInitialized();
    final width = preferences.getDouble('window_width') ?? 1280;
    final height = preferences.getDouble('window_height') ?? 800;
    final left = preferences.getDouble('window_left');
    final top = preferences.getDouble('window_top');
    final options = WindowOptions(
      size: Size(width.clamp(900, 3840), height.clamp(600, 2160)),
      minimumSize: const Size(900, 600),
      center: left == null || top == null,
      title: '赛智荐',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (left != null && top != null) {
        await windowManager.setPosition(Offset(left, top));
      }
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);

    final info = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: '赛智荐',
      appPath: Platform.resolvedExecutable,
      packageName: info.packageName,
    );

    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png',
    );
    await trayManager.setToolTip('赛智荐');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '打开主窗口'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: '退出程序'),
        ],
      ),
    );
  }

  Future<bool> isLaunchAtStartupEnabled() async {
    if (!supported) return false;
    if (Platform.isMacOS) return File(_macLaunchAgentPath).exists();
    return launchAtStartup.isEnabled();
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    if (!supported) return;
    if (Platform.isMacOS) {
      await _setMacLaunchAtStartup(enabled);
      return;
    }
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  String get _macLaunchAgentPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Library/LaunchAgents/com.saizhijian.app.plist';
  }

  Future<void> _setMacLaunchAtStartup(bool enabled) async {
    final file = File(_macLaunchAgentPath);
    if (!enabled) {
      if (await file.exists()) {
        await Process.run('launchctl', ['unload', '-w', file.path]);
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    final executable = _xmlEscape(Platform.resolvedExecutable);
    await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.saizhijian.app</string>
  <key>ProgramArguments</key><array><string>$executable</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''');
    await Process.run('launchctl', ['load', '-w', file.path]);
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<void> _showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') _showWindow();
    if (menuItem.key == 'exit_app') windowManager.destroy();
  }

  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    await _preferences?.setDouble('window_width', size.width);
    await _preferences?.setDouble('window_height', size.height);
  }

  @override
  void onWindowMoved() async {
    final position = await windowManager.getPosition();
    await _preferences?.setDouble('window_left', position.dx);
    await _preferences?.setDouble('window_top', position.dy);
  }
}
