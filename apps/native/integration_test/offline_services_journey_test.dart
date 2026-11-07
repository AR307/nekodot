import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Uses the real candidate and isolated Node/Relay/Hermes. The control endpoint
// exists only in the local acceptance harness, not in any product server.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('node offline and Node/Relay service recovery', (tester) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    const node = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final marker = 'SERVICES_${DateTime.now().millisecondsSinceEpoch}';
    final report = <String, dynamic>{'marker': marker};
    var stage = 'login';
    Future<void> until(bool Function() done, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue, reason: stage);
    }

    Future<void> control(String mode) async {
      await tester.runAsync(() async {
        final response = await http.get(
          Uri.parse(
            '${const String.fromEnvironment('QA_CONTROL_URL')}/?mode=$mode',
          ),
        );
        expect(response.statusCode, 200);
      });
    }

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
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/windows-$name.png',
        ).writeAsBytes(bytes);
        image.dispose();
      });
    }

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
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(node));
    final row = find.byKey(ValueKey('conversation-$dm'));
    await until(() => row.evaluate().isNotEmpty);
    await tester.tap(row);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(
      () =>
          input.evaluate().isNotEmpty &&
          c.node.messages[dm]?.isNotEmpty == true,
    );
    Future<void> send(String text) async {
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('发送'));
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    bool reply(String value) => (c.node.messages[dm] ?? []).any(
      (m) =>
          m.author.type == 'bot' &&
          m.kind == 'text' &&
          m.status == 'done' &&
          '${m.content['text']}'.contains(value),
    );
    stage = 'node offline';
    debugPrint('OFFLINE SERVICES: node offline');
    final ids = c.node.messages[dm]!.map((m) => m.messageId).toSet();
    await control('node-offline');
    await until(() => !c.node.online);
    expect(c.connection.ready, isTrue);
    expect(
      ids.every((id) => c.node.messages[dm]!.any((m) => m.messageId == id)),
      isTrue,
    );
    await send('只回复 ${marker}_NODE_ONLINE，不使用工具。');
    await tester.enterText(input, '保留草稿_$marker');
    await shot('node-offline');
    await control('node-online');
    await until(() => c.online && reply('${marker}_NODE_ONLINE'), seconds: 360);
    expect(tester.widget<TextField>(input).controller!.text, '保留草稿_$marker');
    report['nodeOfflineRetainsContentAndResumesDelivery'] = true;

    for (final service in ['node', 'relay']) {
      stage = '$service restart during real terminal';
      debugPrint('OFFLINE SERVICES: $stage');
      final file =
          '${const String.fromEnvironment('QA_WORK_DIR')}/${marker}_$service.txt';
      final text = '${marker}_RUN_${service.toUpperCase()}';
      final knownTools = (c.node.messages[dm] ?? [])
          .where((m) => m.kind == 'tool')
          .map((m) => m.messageId)
          .toSet();
      await send(
        '请真实调用 terminal 工具：等待 10 秒，然后向 $file 追加且只追加一行 $text，完成后只回复 $text。不要只描述。',
      );
      await until(
        () => (c.node.messages[dm] ?? []).any(
          (m) =>
              m.kind == 'tool' &&
              m.status == 'streaming' &&
              !knownTools.contains(m.messageId),
        ),
      );
      await control('$service-restart');
      await until(() => c.online && reply(text), seconds: 360);
      expect(
        (c.node.messages[dm] ?? [])
            .where(
              (m) =>
                  m.author.type == 'user' &&
                  '${m.content['text']}'.contains(file),
            )
            .length,
        1,
      );
      final lines = await tester.runAsync(() => File(file).readAsLines());
      expect(lines, [text]);
      report['${service}RestartSingleToolExecution'] = true;
      await shot('$service-restarted');
    }
    await tester.runAsync(() async {
      await File(
        '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/windows-services-journey.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    });
    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 18)));
}
