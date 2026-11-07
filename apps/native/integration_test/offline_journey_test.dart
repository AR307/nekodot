import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/flowchart.dart';
import 'package:nekodot_native/features/statistics.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Candidate UI and real services. Only the loopback fault proxy is interrupted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline reading, ordered sending, lost receipt and restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final vault = MemoryVault(), capture = GlobalKey();
    var c = NekodotClient(vault: vault);
    final report = <String, dynamic>{'platform': Platform.operatingSystem};
    const node = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final marker =
        'OFFLINE_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
    final filename =
        '${const String.fromEnvironment('QA_WORK_DIR')}/$marker.txt';
    Future<void> until(bool Function() done, {int seconds = 150}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue);
    }

    Future<void> tap(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty);
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> fault(String mode) async {
      await tester.runAsync(() async {
        final response = await http.get(
          Uri.parse(
            '${const String.fromEnvironment('RELAY_URL')}/__fault?mode=$mode',
          ),
        );
        expect(response.statusCode, 200);
      });
    }

    Future<String> evidence() async => Platform.isAndroid
        ? '${(await getExternalStorageDirectory())!.path}/offline-evidence'
        : const String.fromEnvironment('QA_EVIDENCE_DIR');
    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final dir = await evidence();
        await Directory(dir).create(recursive: true);
        await File('$dir/${Platform.operatingSystem}-$name.png')
            .writeAsBytes(bytes);
        image.dispose();
      });
    }

    final input = find.byKey(const ValueKey('chat-input'));
    Future<void> openChat() async {
      if (input.evaluate().isNotEmpty) return;
      await until(() => find.byType(HomePage).evaluate().isNotEmpty);
      c.workspace['conversation:$node'] = dm;
      Navigator.of(tester.element(find.byType(HomePage))).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(client: c, conversationId: dm),
        ),
      );
      await until(() => input.evaluate().isNotEmpty);
    }

    Future<void> send(String text) async {
      debugPrint('OFFLINE: focusing composer');
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(input, text);
      debugPrint('OFFLINE: entered submission');
      await tester.pump(const Duration(milliseconds: 400));
      if (text.startsWith('/')) {
        final state = tester.state<ChatComposerState>(
          find.byType(ChatComposer),
        );
        await until(() => !state.loadingCommands);
      }
      await tap(find.byTooltip('发送'));
      debugPrint('OFFLINE: tapped send');
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    bool replied(String text) => (c.node.messages[dm] ?? []).any(
      (m) =>
          m.author.type == 'bot' &&
          m.status == 'done' &&
          '${m.content['text']}'.contains(text),
    );
    await fault('online');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      const String.fromEnvironment('QA_EMAIL'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(node));
    await until(() => c.online && c.node.bots.isNotEmpty);
    final bot =
        c.node.conversations.firstWhere(
              (v) => v['conversationId'] == dm,
            )['botId']
            as String;
    await tester.runAsync(() async {
      await c.rpc('commands.list', {'botId': bot});
      await c.rpc('sessions.list', {'botId': bot});
      await c.rpc('routines.list', {'botId': bot});
      await c.rpc('hermes.settings.get', {'botId': bot});
      await c.flushContent();
    });
    await openChat();
    await until(() => c.node.messages[dm]?.isNotEmpty == true);
    await until(
      () =>
          c.node.activities[dm]?.state == 'idle' ||
          c.node.activities[dm] == null,
    );
    if (!const bool.fromEnvironment('QA_OFFLINE_EXTENDED_ONLY')) {
      debugPrint('OFFLINE: reading, submissions and client reconstruction');
      final original = (c.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      await tester.enterText(input, '中文草稿，未点击发送');
      final controller = tester.widget<TextField>(input).controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await fault('offline');
      await until(() => !c.connection.ready);
      await until(() => find.text('无法连接').evaluate().isNotEmpty);
      expect(tester.widget<TextField>(input).controller, same(controller));
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(
        original.every(
          (id) => c.node.messages[dm]!.any((m) => m.messageId == id),
        ),
        isTrue,
      );
      await shot('offline-draft');
      report['draftSelectionAndMessagesKept'] = true;
      final state = tester.state<ChatComposerState>(find.byType(ChatComposer));
      await tester.runAsync(() async {
        final file = File(
          '${(await getTemporaryDirectory()).path}/$marker.txt',
        );
        await file.writeAsString('OFFLINE_ATTACHMENT_CONTENT');
        await state.attachFile(path: file.path);
      });
      await send(
        '请真实使用 terminal 工具，在 $filename 追加一行 $marker（只追加一次），然后读取确认。回复 $marker。不要用描述代替工具执行。附件不是图片，不需要打开。',
      );
      await send('/queue 只回复 ${marker}_SECOND，不使用工具。');
      final count = c.deliveries.items
          .where((i) => i['params']['conversationId'] == dm)
          .length;
      expect(count, 2);
      await send('CANCEL_$marker');
      final cancelled = c.deliveries.items.last['id'] as String;
      await tester.runAsync(() => c.deliveries.cancel(cancelled));
      await tester.enterText(input, '保留草稿_$marker');
      await shot('offline-queue');
      await fault('online');
      await tester.runAsync(() => c.connection.connect());
      await until(() => replied('${marker}_SECOND'), seconds: 480);
      await until(
        () => c.deliveries.items.every(
          (i) => i['params']['conversationId'] != dm,
        ),
        seconds: 60,
      );
      expect(replied(marker), isTrue);
      expect(tester.widget<TextField>(input).controller!.text, '保留草稿_$marker');
      expect(
        (c.node.messages[dm] ?? []).where(
          (m) =>
              m.author.type == 'user' &&
              '${m.content['text']}'.contains('CANCEL_$marker'),
        ),
        isEmpty,
      );
      report['offlineSendAttachmentAndCancel'] = true;
      report['toolFile'] = filename;
      await shot('reconnected-reply');
      await fault('lost-ack');
      await send('只回复 ${marker}_ACK，不使用工具。');
      await until(() => !c.connection.ready);
      await fault('online');
      await tester.runAsync(() => c.connection.connect());
      await until(() => replied('${marker}_ACK'), seconds: 360);
      final receiptMessages = (c.node.messages[dm] ?? [])
          .where(
            (m) =>
                m.author.type == 'user' &&
                '${m.content['text']}'.contains('${marker}_ACK'),
          )
          .toList();
      expect(receiptMessages.length, 1);
      report['lostReceiptOneMessage'] = true;
      await fault('offline');
      await until(() => !c.connection.ready);
      await send('只回复 ${marker}_RESTART，不使用工具。');
      await tester.enterText(input, '重启草稿_$marker');
      await tester.runAsync(() => c.flushContent());
      final savedIds = c.node.messages[dm]!.map((m) => m.messageId).toSet();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      c = NekodotClient(vault: vault);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: NekodotApp(client: c),
        ),
      );
      await openChat();
      await until(() => c.node.messages[dm]?.isNotEmpty == true);
      expect(tester.widget<TextField>(input).controller!.text, '重启草稿_$marker');
      expect(
        savedIds.every(
          (id) => c.node.messages[dm]!.any((m) => m.messageId == id),
        ),
        isTrue,
      );
      expect(
        c.deliveries.items.any(
          (i) => '${i['params']['text']}'.contains('${marker}_RESTART'),
        ),
        isTrue,
      );
      await shot('restart-offline');
      report['offlineRestartRestoresContentDraftAndPending'] = true;
      await fault('online');
      await tester.runAsync(() => c.connection.connect());
      await until(() => replied('${marker}_RESTART'), seconds: 360);
      expect(tester.widget<TextField>(input).controller!.text, '重启草稿_$marker');
      await shot('restart-recovered');
      report['restartPendingSentOnce'] = true;
    }
    debugPrint('OFFLINE: cached files, settings and Flowchart');
    final settings = (await tester.runAsync(
      () => c.rpc('hermes.settings.get', {'botId': bot}),
    ))!;
    final editable = objects(settings['fields'])
        .firstWhere((f) => f['editable'] == true && f['sensitive'] != true);
    final uploaded = (c.node.messages[dm] ?? []).firstWhere(
      (m) =>
          m.author.type == 'user' &&
          '${m.content['text']}'.contains('OFFLINE_') &&
          (m.content['files'] as List?)?.isNotEmpty == true,
    );
    final fileId = (uploaded.content['files'] as List).first as String;
    final attachment = await tester.runAsync(() => downloadFile(c, fileId));
    expect(utf8.decode(attachment!), 'OFFLINE_ATTACHMENT_CONTENT');
    await tester.runAsync(() => c.loadFlow(dm));
    final flow = c.node.flows[dm];
    await fault('offline');
    await until(() => !c.connection.ready);
    expect(await tester.runAsync(() => downloadFile(c, fileId)), attachment);
    expect(
      (await tester.runAsync(
        () => c.rpc('hermes.settings.get', {'botId': bot}),
      ))!['fields'],
      settings['fields'],
    );
    Json? saved;
    final saving = c
        .continueAction('hermes.settings.set', {
          'botId': bot,
          'key': editable['key'],
          'value': editable['value'],
        })
        .then((value) => saved = value);
    await tester.pump(const Duration(milliseconds: 500));
    Navigator.of(tester.element(find.byType(ChatPage).last)).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: FlowchartPanel(
            client: c,
            conversationId: dm,
            onClose: () => Navigator.pop(context),
            onMessage: (_) async {},
          ),
        ),
      ),
    );
    await until(() => find.byType(FlowchartPanel).evaluate().isNotEmpty);
    expect(c.node.flows[dm]?.flowId, flow?.flowId);
    await shot('offline-flow');
    Navigator.of(tester.element(find.byType(FlowchartPanel))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await fault('online');
    await tester.runAsync(() => c.connection.connect());
    await until(() => saved != null);
    await saving;
    expect(saved!['saved'], isTrue);
    report['cachedFileFlowSettingsAndSaveRecovery'] = true;
    debugPrint('OFFLINE: ordered session commands');
    final oldSession = (await tester.runAsync(
      () => c.rpc('sessions.list', {'botId': bot}),
    ))!['currentSessionId'];
    await fault('offline');
    await until(() => !c.connection.ready);
    await send('/new $marker-session');
    await send('只回复 ${marker}_NEW_SESSION，不使用工具。');
    await fault('online');
    await tester.runAsync(() => c.connection.connect());
    await until(() => replied('${marker}_NEW_SESSION'), seconds: 360);
    await send('/resume $oldSession');
    await until(
      () => c.deliveries.items
          .where((i) => i['params']['conversationId'] == dm)
          .isEmpty,
    );
    report['orderedSessionChangeAndMessage'] = true;
    debugPrint('OFFLINE: opening group');
    const group = String.fromEnvironment('QA_GROUP');
    final nav = Navigator.of(tester.element(find.byType(ChatPage).last));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(client: c, conversationId: group),
      ),
    );
    await until(
      () => find
          .byWidgetPredicate(
            (widget) =>
                widget is ChatComposer && widget.conversationId == group,
          )
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('OFFLINE: interrupting group connection');
    await fault('offline');
    await until(() => !c.connection.ready);
    debugPrint('OFFLINE: submitting group message');
    await send(
      '@coreblue @coreorange 依次只回复 ${marker}_GROUP 和你自己的名字，不调用工具，不继续接力。',
    );
    debugPrint('OFFLINE: restoring group connection');
    await fault('online');
    await tester.runAsync(() => c.connection.connect());
    await until(
      () =>
          (c.node.messages[group] ?? [])
              .where(
                (m) =>
                    m.author.type == 'bot' &&
                    m.status == 'done' &&
                    '${m.content['text']}'.contains('${marker}_GROUP'),
              )
              .length >=
          2,
      seconds: 480,
    );
    await tester.runAsync(() => c.loadFlow(group));
    await shot('group-recovered');
    report['groupOfflineSendAndRelay'] = true;
    nav.pop();
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('OFFLINE: statistics');
    Navigator.of(
      tester.element(find.byType(ChatPage).last),
    ).push(MaterialPageRoute<void>(builder: (_) => StatisticsPage(client: c)));
    await until(() => c.views.keys.any((key) => key.contains('usage.query')));
    await fault('offline');
    await until(() => !c.connection.ready);
    await tap(find.byKey(const ValueKey('usage-refresh')));
    await shot('offline-statistics');
    report['statisticsRetainedDuringOfflineRefresh'] = true;
    await fault('online');
    report['marker'] = marker;
    await tester.runAsync(() async {
      final dir = await evidence();
      final suffix = const bool.fromEnvironment('QA_OFFLINE_EXTENDED_ONLY')
          ? 'extended-journey'
          : 'journey';
      await File('$dir/${Platform.operatingSystem}-$suffix.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    });
    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 25)));
}
