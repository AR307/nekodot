import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_activity.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/connection_notice.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Native UI, actual isolated Node/Relay/Hermes and model. No event injection.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('the Dot asks in the chat while it works and delivers the file', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    final reducedMotion = ValueNotifier(false);
    final phone = Platform.isAndroid;
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    const work = String.fromEnvironment('QA_WORK_DIR');
    final suffix = phone ? 'android' : 'windows';
    var converted = false;
    addTearDown(c.dispose);
    addTearDown(reducedMotion.dispose);

    Future<void> frames([int ms = 400]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready, String label) async {
      final end = DateTime.now().add(const Duration(minutes: 10));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(150);
      }
      expect(ready(), isTrue, reason: label);
      debugPrint('ACTIVITY verified $label');
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.hitTestable().first);
      await frames();
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await frames(500);
      expect(tester.takeException(), isNull);
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('activity-$suffix-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/activity-$suffix-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Activity QA');
      await windowManager.show();
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
    }
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => c.online && c.node.bots.isNotEmpty,
      'real services connected',
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: Listenable.merge([c.prefs, reducedMotion]),
        builder: (_, child) => MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [nativeRoutes],
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reducedMotion.value),
            child: ConnectionNotice(
              client: c,
              child: phone
                  ? Ambient(child: child!)
                  : WindowChrome(child: child!),
            ),
          ),
          home: HomePage(client: c),
        ),
      ),
    );
    await frames(1000);
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    final input = find.byKey(const ValueKey('chat-input'));
    final dock = find.byKey(const ValueKey('dot-activity'));
    final box = find.byKey(const ValueKey('composer-card'));
    final original = c.node.tasks.keys.toSet();
    Future<void> send(String text) async {
      await tester.enterText(input, text);
      await frames(150);
      await tap(find.byTooltip(c.tr('发送', 'Send')));
    }

    // The Dot reads the material itself, asks in the chat, and continues on
    // the answer in the same work; nothing is handed to another session.
    final start = c.node.seq;
    await send(
      '帮我做一个三页周汇报 PPTX，素材是 $work/activity-input.txt，内容用中文。'
      '先读取素材、整理内容，再通过原生 clarify 确认我想用正式商务风还是轻松图文风。'
      '现在先不要替我选风格，也不要在读素材之前提前问；读取后再问我。'
      '我选好以后继续完成真实 PPTX，保存在 $work/weekly-$suffix.pptx，然后交付文件和简短总结。'
      '不要改写素材，不要装大型依赖。',
    );
    ChatMessage? question() => c.node.messages[dm]!
        .where(
          (m) =>
              m.seq > start && m.kind == 'question' && m.status == 'streaming',
        )
        .lastOrNull;
    await until(() => question() != null, 'the Dot asked in the chat');
    final asked = question()!;
    final read = c.node.messages[dm]!.where(
      (m) => m.seq > start && m.seq < asked.seq && m.kind == 'tool',
    );
    expect(read, isNotEmpty, reason: 'it read the material before asking');
    expect(c.node.tasks.keys.toSet().difference(original), isEmpty);
    expect(
      '${asked.content['question']}',
      isNot(
        matches(RegExp(r'子代理|手下|任务编号|subagent|worker', caseSensitive: false)),
      ),
    );
    await frames();
    final latest = find.byKey(const ValueKey('chat-latest'));
    Future<void> showLatest() async {
      if (latest.hitTestable().evaluate().isNotEmpty) await tap(latest);
    }

    await showLatest();
    expect(find.byType(ControlCard), findsWidgets);
    expect(find.text('${asked.content['question']}'), findsOneWidget);
    expect(dock, findsOneWidget);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    final initialY = tester.getRect(dock).top;
    await shot('main-question');
    await tap(dock);
    expect(find.byKey(const ValueKey('chat-controls')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 450),
    );
    await frames();
    expect(tester.getRect(dock).top, closeTo(initialY, 1));
    await shot('history');
    await tester.enterText(input, '保留这段未发送草稿\n第二行');
    await frames();
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await frames();
    final row = tester.widget<ThinkingRow>(find.byType(ThinkingRow));
    expect(row.line, c.tr('等你回答', 'Needs your answer'));
    expect(row.moving, isFalse);
    await tap(find.byKey(const ValueKey('chat-flowchart')));
    await shot('flow');
    await tap(find.byKey(const ValueKey('flow-close')));
    expect(tester.widget<TextField>(input).controller!.text, '保留这段未发送草稿\n第二行');
    final composer = tester.state<ChatComposerState>(find.byType(ChatComposer));
    composer.quote('${asked.content['question']}');
    await frames();
    expect(find.byKey(const ValueKey('composer-quote')), findsOneWidget);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('quoted');
    await tap(find.byTooltip(c.tr('取消', 'Cancel')).last);
    expect(find.byKey(const ValueKey('composer-quote')), findsNothing);
    if (phone) {
      tester.testTextInput.unregister();
      await tester.tap(input);
      await frames(1000);
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
      await shot('keyboard');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(500);
      tester.testTextInput.register();
    }
    await c.prefs.update(locale: 'en', appearance: 'dark');
    await showLatest();
    await shot('dark-en');
    reducedMotion.value = true;
    await shot('reduced-motion');
    await c.connection.disconnect();
    await frames(1000);
    expect(
      find.descendant(of: dock, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    await shot('offline');
    await c.connection.connect();
    await until(() => c.online, 'reconnected');
    await until(() => question() != null, 'same question restored');
    expect(question()!.messageId, asked.messageId);
    if (const bool.fromEnvironment('QA_ACTIVITY_OBSERVE_ONLY')) {
      final result = {
        'questionId': asked.messageId,
        'platform': suffix,
        'pending': true,
      };
      if (!phone) {
        await File('$evidence/activity-pending.json')
            .writeAsString(jsonEncode(result));
      }
      binding.reportData = {...?binding.reportData, ...result};
      debugPrint('ACTIVITY pending ${jsonEncode(result)}');
      return;
    }
    await showLatest();
    final choices = (asked.content['choices'] as List).cast<String>();
    final selected = choices.indexWhere(
      (s) => s.contains('正式') || s.contains('商务'),
    );
    expect(selected, greaterThanOrEqualTo(0));
    await tap(find.byKey(ValueKey('choice-${asked.messageId}-$selected')));
    ChatMessage? delivered() => c.node.messages[dm]!
        .where(
          (m) =>
              m.seq > asked.seq &&
              m.author.type == 'bot' &&
              m.kind == 'text' &&
              m.status == 'done' &&
              (m.content['files'] as List?)?.isNotEmpty == true,
        )
        .lastOrNull;
    await until(
      () =>
          delivered() != null &&
          (c.node.activities[dm]?.state ?? 'idle') == 'idle',
      'the same work continued and the Dot delivered the file',
    );
    final report = delivered()!;
    expect(c.node.tasks.keys.toSet().difference(original), isEmpty);
    expect(
      c.node.messages[dm]!.where((m) => m.taskRole == 'execution'),
      isEmpty,
    );
    await tester.enterText(input, '');
    await showLatest();
    await shot('results');
    final record = {
      'platform': suffix,
      'question': asked.content['question'],
      'reportMessageId': report.messageId,
      'fileIds': report.content['files'],
    };
    if (!phone) {
      await File('$evidence/activity-$suffix-results.json')
          .writeAsString(jsonEncode(record));
    }
    binding.reportData = {...?binding.reportData, ...record};
    debugPrint('ACTIVITY PASS ${jsonEncode(record)}');
  });
}
