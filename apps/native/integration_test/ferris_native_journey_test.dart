import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

// Real isolated Relay, Node, Hermes and model only. Never changes system login.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Ferris improvements on native screens and a real chat', (
    tester,
  ) async {
    final c = NekodotClient();
    expect(c.account.origin.host, anyOf('127.0.0.1', 'localhost'));
    if (Platform.isWindows) {
      await DesktopHost.initialize();
      tester.view.physicalSize = const Size(2560, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    final page = ValueNotifier<Widget>(AuthPage(client: c));
    final dark = ValueNotifier(false);
    addTearDown(c.dispose);
    addTearDown(page.dispose);
    addTearDown(dark.dispose);
    runApp(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, value, _) => MaterialApp(
          theme: appTheme(value ? Brightness.dark : Brightness.light),
          navigatorObservers: [nativeRoutes],
          builder: (context, child) => Platform.isWindows
              ? WindowChrome(child: child!)
              : Ambient(child: child!),
          home: ValueListenableBuilder<Widget>(
            valueListenable: page,
            builder: (context, value, _) => value,
          ),
        ),
      ),
    );
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> until(bool Function() ready, String stage) async {
      final end = DateTime.now().add(const Duration(minutes: 3));
      while (!ready() && DateTime.now().isBefore(end)) {
        await settle();
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<void> tap(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty, 'Control present');
      await tester.ensureVisible(finder.first);
      await settle();
      await tester.tap(finder.first);
      await settle();
    }

    bool converted = false;
    Future<void> shot(String suffix) async {
      await settle();
      final name = 'ferris-${Platform.operatingSystem}-$suffix';
      if (Platform.isAndroid) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(name);
      } else {
        final output = Directory(
          const String.fromEnvironment('QA_EVIDENCE_DIR'),
        );
        await output.create(recursive: true);
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    await settle();
    final password = find.byKey(const ValueKey('auth-password'));
    await tester.enterText(password, 'Visible-test-only');
    await tap(find.byKey(const ValueKey('auth-reveal-password')));
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await shot('password-reveal');
    await tap(find.byKey(const ValueKey('auth-switch-mode')));
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tap(find.byKey(const ValueKey('auth-send-code')));
    expect(find.text('请输入有效的邮箱'), findsOneWidget);

    // Use the real login endpoint, without replacing the user's OS-stored token.
    final login = await c.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.account.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    await until(() => c.online && c.node.bots.isNotEmpty, 'Real Node online');
    page.value = HomePage(client: c);
    await settle();
    const conversation = String.fromEnvironment('QA_CONVERSATION');
    await tap(find.byKey(const ValueKey('conversation-$conversation')));
    await tap(find.byTooltip('详情'));
    await tap(find.byTooltip('编辑'));
    await until(
      () => find.byType(BotEditor).evaluate().isNotEmpty,
      'Bot editor',
    );
    final swatch = find.byKey(ValueKey('avatar-color-${avatarColors[1]}'));
    await tap(swatch);
    expect(tester.getSize(swatch), const Size(44, 44));
    await shot('avatar-picker');
    final model = find.byKey(const ValueKey('model-choice'));
    await tester.ensureVisible(model);
    await until(
      () => tester.widget<OutlinedButton>(model).onPressed != null,
      'Native model catalog',
    );
    await tap(model);
    final query = find.byKey(const ValueKey('model-search'));
    await until(() => query.evaluate().isNotEmpty, 'Model dialog');
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>()
          ?.key,
      const ValueKey('model-search'),
    );
    await tester.enterText(query, 'gpt-6.1-sol');
    expect(
      find.byKey(const ValueKey('model-option-gpt-6.1-sol')),
      findsOneWidget,
    );
    await shot('model-focus');
    if (Platform.isWindows) {
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await settle();
        final focus = FocusManager.instance.primaryFocus?.context;
        expect(focus?.findAncestorWidgetOfExactType<AlertDialog>(), isNotNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
    } else {
      await tap(find.widgetWithText(TextButton, '取消'));
    }
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pageBack(); // Discard the unsaved avatar edit.
    await settle();
    if (Platform.isAndroid) {
      await tester.pageBack();
      await settle();
    }
    final input = find.byKey(const ValueKey('chat-input'));
    final before = (c.node.messages[conversation] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await tap(input);
    await tester.enterText(
      input,
      '请用 terminal 实际计算 17*23，然后回复 24 行编号清单，'
      '每行写“第 N 项：计算结果为 391”。最后一行写 FERRIS_NATIVE_OK。'
      '不修改任何文件，也不要调用其他工具。',
    );
    await tap(find.byTooltip('发送'));
    await until(
      () => (c.node.messages[conversation] ?? []).any(
        (m) =>
            !before.contains(m.messageId) &&
            m.author.type == 'bot' &&
            m.kind == 'text' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains('FERRIS_NATIVE_OK'),
      ),
      'Real model reply',
    );
    await settle();
    expect(
      (c.node.messages[conversation] ?? []).any(
        (m) => !before.contains(m.messageId) && m.kind == 'tool',
      ),
      isTrue,
    );
    final list = find.byKey(const ValueKey('chat-messages'));
    final position = tester.widget<ListView>(list).controller!.position;
    expect(position.pixels, closeTo(0, 1));
    await shot('live-chat');
    await tester.enterText(input, 'Unsent draft');
    Focus.of(tester.element(list)).requestFocus();
    await settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await settle();
    expect(position.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await settle();
    expect(position.pixels, closeTo(0, 1));
    expect(tester.widget<TextField>(input).controller!.text, 'Unsent draft');
    dark.value = true;
    await shot('dark-chat');
    expect(tester.takeException(), isNull);
  });
}
