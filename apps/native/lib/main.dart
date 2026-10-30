import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/client.dart';
import 'features/auth.dart';
import 'features/home.dart';
import 'platform/desktop.dart';
import 'platform/notifications.dart';
import 'ui/design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await DesktopHost.initialize();
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  // Built once: a fresh theme on every client update would restart the theme
  // animation each time.
  final lightTheme = appTheme(Brightness.light);
  final darkTheme = appTheme(Brightness.dark);
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
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: switch (widget.client.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) => AnnotatedRegion(
        value: Theme.of(context).appBarTheme.systemOverlayStyle!,
        child: Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
      ),
      home: loading
          ? const Scaffold(body: Center(child: CatAvatar(size: 72)))
          : error.isNotEmpty
          ? Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: ErrorNotice(error)),
              ),
            )
          : widget.client.token == null
          ? AuthPage(client: widget.client)
          : HomePage(client: widget.client),
    ),
  );
}
