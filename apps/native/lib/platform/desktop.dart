import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopHost with WindowListener {
  static final instance = DesktopHost();
  static TrayIcon? icon;
  static Future<void> initialize() async {
    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(
          prefs.getDouble('window-width') ?? 1180,
          prefs.getDouble('window-height') ?? 800,
        ),
        minimumSize: const Size(390, 600),
        title: 'nekodot',
      ),
    );
    if (prefs.getBool('window-maximized') == true) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
    windowManager.addListener(instance);
    final tray = TrayIcon.create()!;
    icon = tray;
    tray.icon = ImageAsset.fromAsset('assets/nekodot.ico');
    tray.setTooltip('nekodot');
    final menu = Menu.create()!;
    final show = MenuItem.createWithLabelAndType(
      '打开 / Open nekodot',
      MenuItemType.normal,
    )!;
    show.addListener((event) {
      if (event is MenuItemClickedEvent) {
        windowManager.show();
        windowManager.focus();
      }
    });
    menu.addItem(show);
    menu.addSeparator();
    final quit = MenuItem.createWithLabelAndType(
      '退出 / Quit',
      MenuItemType.normal,
    )!;
    quit.addListener((event) async {
      if (event is MenuItemClickedEvent) {
        tray.dispose();
        await windowManager.destroy();
      }
    });
    menu.addItem(quit);
    tray.setContextMenu(menu);
    tray.setVisible(true);
    tray.addListener((event) {
      if (event is TrayIconClickedEvent) {
        windowManager.show();
        windowManager.focus();
      }
    });
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onWindowResized() async {
    if (await windowManager.isMaximized() ||
        await windowManager.isMinimized()) {
      return;
    }
    final size = await windowManager.getSize(),
        prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window-width', size.width);
    await prefs.setDouble('window-height', size.height);
  }

  @override
  void onWindowMaximize() async {
    await (await SharedPreferences.getInstance()).setBool(
      'window-maximized',
      true,
    );
  }

  @override
  void onWindowUnmaximize() async {
    await (await SharedPreferences.getInstance()).setBool(
      'window-maximized',
      false,
    );
  }
}
