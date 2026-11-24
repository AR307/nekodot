import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the session in memory, so the installed client's own login is never touched.
class MemoryVault extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

/// Signs in with Google and with GitHub from the login page of the real
/// client, through the system browser, against the local acceptance Relay in
/// .runtime/oauth-qa (its providers approve at once). Also pictures the login
/// page on a desktop and a phone, light and dark. Defines: RELAY_URL, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('sign in with Google and GitHub through the browser', (
    tester,
  ) async {
    final client = NekodotClient(vault: MemoryVault());
    expect(client.account.origin.host, '127.0.0.1');
    final out = Directory(
      Platform.isAndroid
          ? '${(await tester.runAsync(getExternalStorageDirectory))!.path}/oauth-evidence'
          : const String.fromEnvironment('TOUR_OUT'),
    );
    await tester.runAsync(() => out.create(recursive: true));
    final mode = ValueNotifier(ThemeMode.light);
    var glass = false;
    final notes = <String, Object?>{};

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<bool> until(bool Function() test, {int seconds = 60}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 200));
      }
      return test();
    }

    Future<void> shot(String name, {int settle = 600}) async {
      await run(Duration(milliseconds: settle));
      final view = tester.binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final size = tester.view.physicalSize;
      await tester.runAsync(() async {
        final ui.Image image = await layer.toImage(Offset.zero & size);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${out.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      // ignore: avoid_print
      print('TOUR $name.png');
    }

    Widget app() => ValueListenableBuilder(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light, glass: glass),
        darkTheme: appTheme(Brightness.dark, glass: glass),
        themeMode: value,
        builder: (context, child) =>
            glass ? Ambient(child: child!) : WindowChrome(child: child!),
        home: AuthPage(client: client),
      ),
    );

    Future<void> stage({required bool phone}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      glass = phone;
      tester.view.physicalSize = phone
          ? const Size(1080, 2340)
          : const Size(2560, 1600);
      tester.view.devicePixelRatio = phone ? 3 : 2;
      tester.view.padding = phone
          ? const FakeViewPadding(top: 108, bottom: 72)
          : FakeViewPadding.zero;
      await tester.pumpWidget(app());
      notes['offered'] = await until(
        () => find
            .byKey(const ValueKey('auth-oauth-github'))
            .evaluate()
            .isNotEmpty,
      );
    }

    // The login page, as people will see it.
    if (!Platform.isAndroid) {
      await stage(phone: false);
      await shot('desk-light');
      mode.value = ThemeMode.dark;
      await shot('desk-dark');
      mode.value = ThemeMode.light;
      await tester.tap(find.byKey(const ValueKey('auth-switch-mode')));
      await shot('desk-signup');
    }
    await stage(phone: true);
    await shot('phone-light');
    mode.value = ThemeMode.dark;
    await shot('phone-dark');
    mode.value = ThemeMode.light;

    // Real browser return: desktop loopback or Android's native deep link.
    await stage(phone: Platform.isAndroid);
    for (final (provider, email) in const [
      ('google', 'qa.google@example.test'),
      ('github', 'qa.github@example.test'),
    ]) {
      final started = DateTime.now();
      await tester.tap(find.byKey(ValueKey('auth-oauth-$provider')));
      await tester.pump(const Duration(milliseconds: 50));
      notes['$provider-waiting'] = find.text('等待授权…').evaluate().isNotEmpty;
      final signedIn = await until(
        () => client.account.me != null,
        seconds: 90,
      );
      notes[provider] = signedIn
          ? '${client.account.me!['user']['email']}'
          : 'not signed in';
      notes['$provider-seconds'] = DateTime.now().difference(started).inSeconds;
      expect(client.account.me?['user']['email'], email);
      await shot('after-$provider', settle: 300);
      await tester.runAsync(client.account.clear);
      await stage(phone: Platform.isAndroid);
    }

    tester.view.reset();
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode(notes)}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
