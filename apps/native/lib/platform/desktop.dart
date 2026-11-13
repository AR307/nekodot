import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/symbols.dart';

class DesktopHost with WindowListener {
  static bool get supported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static final instance = DesktopHost();
  static final focused = ValueNotifier<bool>(true);
  static TrayIcon? icon;
  // Native handles own the menu callbacks; keep them alive with the tray.
  static Menu? _menu;
  static final _menuItems = <MenuItem>[];

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
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
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
    tray.icon = ImageAsset.fromAsset(
      Platform.isWindows ? 'assets/nekodot.ico' : 'assets/nekodot.png',
    );
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
        await DesktopHost.quit();
      }
    });
    menu.addItem(quit);
    _menu = menu;
    _menuItems.addAll([show, quit]);
    tray.setContextMenu(menu);
    tray.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    tray.setVisible(true);
    tray.addListener((event) {
      if (event is TrayIconClickedEvent) {
        windowManager.show();
        windowManager.focus();
      }
    });
  }

  static Future<void> reveal() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Stops what this app owns (the local node); returning false keeps the app open.
  static Future<bool> Function()? beforeQuit;

  static Future<void> quit({Future<void> Function()? afterStop}) async {
    if (beforeQuit != null && !await beforeQuit!()) return;
    if (afterStop != null) await afterStop();
    icon?.dispose();
    icon = null;
    _menu?.dispose();
    _menu = null;
    for (final item in _menuItems) {
      item.dispose();
    }
    _menuItems.clear();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onWindowFocus() => focused.value = true;

  @override
  void onWindowBlur() => focused.value = false;

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

/// Drags the window from empty header space. Nothing outside the desktop shell.
class WindowDrag extends StatelessWidget {
  const WindowDrag({super.key});
  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChromeScope>() == null ||
          context.dependOnInheritedWidgetOfExactType<WindowSheetScope>() != null
      ? const SizedBox.expand()
      : const DragToMoveArea(child: SizedBox.expand());
}

/// Inside a sheet floating over the window: its header is not the window's,
/// so it neither drags the window nor leaves room for the window controls.
class WindowSheetScope extends InheritedWidget {
  const WindowSheetScope({super.key, required super.child});
  @override
  bool updateShouldNotify(WindowSheetScope oldWidget) => false;
}

class _ChromeScope extends InheritedWidget {
  const _ChromeScope({required super.child});
  @override
  bool updateShouldNotify(_ChromeScope oldWidget) => false;
}

/// Window frame drawn into the page: three quiet controls at the top right.
class WindowChrome extends StatelessWidget {
  final Widget child;
  const WindowChrome({super.key, required this.child});
  static const _width = 108.0;

  /// Room a header leaves at its right edge for the controls.
  static double reserved(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChromeScope>() == null ||
          context.dependOnInheritedWidgetOfExactType<WindowSheetScope>() != null
      ? 0
      : _width;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).hintColor;
    Widget control(IconData icon, VoidCallback onTap, double size) => InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 30,
        child: Icon(icon, size: size, color: color),
      ),
    );
    return _ChromeScope(
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            right: 0,
            top: 0,
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  control(Symbols.remove, windowManager.minimize, 15),
                  control(Symbols.crop_square, () async {
                    await windowManager.isMaximized()
                        ? await windowManager.unmaximize()
                        : await windowManager.maximize();
                  }, 14),
                  control(Symbols.close, windowManager.close, 15),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
