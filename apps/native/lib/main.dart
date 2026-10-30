import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/client.dart';
import 'features/auth.dart';
import 'features/home.dart';
import 'platform/desktop.dart';
import 'platform/notifications.dart';
import 'ui/design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 800),
        minimumSize: Size(390, 600),
        title: 'nekodot',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(NekodotApp(client: NekodotClient()));
}

class NekodotApp extends StatefulWidget {
  final NekodotClient client;
  const NekodotApp({super.key, required this.client});
  @override
  State<NekodotApp> createState() => _NekodotAppState();
}

class _NekodotAppState extends State<NekodotApp> with WidgetsBindingObserver {
  final navigation = GlobalKey<NavigatorState>();
  late final notifications = NativeNotifications(widget.client);
  bool loading = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client
        .initialize()
        .catchError((Object e) {
          error = '$e';
        })
        .whenComplete(() {
          if (mounted) {
            setState(() => loading = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final context = navigation.currentContext;
              if (context != null) notifications.initialize(context);
            });
          }
        });
    if (Platform.isWindows) DesktopHost.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.client.resume();
      notifications.register();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.client.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notifications.dispose();
    widget.client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.client,
    builder: (_, child) => MaterialApp(
      title: 'nekodot',
      navigatorKey: navigation,
      navigatorObservers: [nativeRoutes],
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: switch (widget.client.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : error.isNotEmpty
          ? Scaffold(body: Center(child: ErrorNotice(error)))
          : widget.client.token == null
          ? AuthPage(client: widget.client)
          : HomePage(client: widget.client),
    ),
  );
}
