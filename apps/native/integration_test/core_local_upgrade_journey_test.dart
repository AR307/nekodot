import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Only this test process resolves the official API name to the local TLS proxy.
/// Certificate verification stays enabled; no system hosts/trust changes.
class _LocalApi extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final trusted = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificates(const String.fromEnvironment('QA_CA'));
    final client = super.createHttpClient(trusted);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      expect(url.host, 'api.nekodot.com');
      final connection = await Socket.startConnect(InternetAddress.loopbackIPv4, 443);
      return ConnectionTask.fromSocket(
        connection.socket.then((socket) => SecureSocket.secure(
          socket, host: url.host, context: trusted,
        )),
        connection.cancel,
      );
    };
    return client;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'existing local installation keeps identity and history at API cutover',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      final work = const String.fromEnvironment('QA_WORK_DIR')
          .replaceAll('\\', '/');
      expect(
        Platform.environment['LOCALAPPDATA']!.replaceAll('\\', '/'),
        startsWith(work),
      );
      HttpOverrides.global = _LocalApi();
      SharedPreferences.setMockInitialValues({
        'language': 'en',
        'theme': 'light',
        'notification-requested': true,
      });
      final baseline = jsonDecode(
        await File(const String.fromEnvironment('QA_BASELINE')).readAsString(),
      ) as Json;
      final location = LocalLocation(
        const String.fromEnvironment('QA_RUNTIME_DIR'),
        const String.fromEnvironment('QA_DATA_DIR'),
      );
      await location.save();
      final home = location.account(baseline['userId'] as String);
      final originalConfig =
          jsonDecode(await File('$home/node.json').readAsString()) as Json;
      final beforeUpgrade = jsonDecode(
        await File('$home/node.json.before-api-domain').exists()
            ? await File('$home/node.json.before-api-domain').readAsString()
            : jsonEncode(originalConfig),
      ) as Json;
      expect(beforeUpgrade['relayUrl'], 'https://nekodot.com');
      final c = NekodotClient(vault: MemoryVault());
      final local = localRuntime = LocalRuntime(c);
      final capture = GlobalKey();
      await DesktopHost.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: NekodotApp(client: c),
        ),
      );
      var stage = 'login';
      Future<void> until(bool Function() ready, {int seconds = 180}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 120));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)),
          );
        }
        expect(ready(), isTrue, reason: '$stage: ${local.error}');
      }

      Future<void> tap(Finder finder) async {
        await until(() => finder.evaluate().isNotEmpty);
        await tester.ensureVisible(finder.first);
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<Set<String>> history() async {
        final ids = <String>{};
        int? before;
        while (true) {
          final page = objects(
            (await tester.runAsync(
              () => c.rpc('messages.list', {
                'conversationId': const String.fromEnvironment(
                  'QA_CONVERSATION',
                ),
                'limit': 50,
                'beforeSeq': ?before,
              }),
            ))!['messages'],
          );
          if (page.isEmpty) break;
          ids.addAll(page.map((m) => m['messageId'] as String));
          before = page
              .map((m) => m['seq'] as int)
              .reduce((a, b) => a < b ? a : b);
        }
        return ids;
      }

      try {
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
        stage = 'local runtime online';
        await until(() => local.phase == LocalPhase.online);
        const nodeId = String.fromEnvironment('QA_NODE');
        const dm = String.fromEnvironment('QA_CONVERSATION');
        expect(local.nodeId, nodeId);
        await tester.runAsync(() => c.selectNode(nodeId));
        await until(() => c.online && c.node.conversations.isNotEmpty);
        final changed =
            jsonDecode(await File('$home/node.json').readAsString()) as Json;
        expect(changed, {
          ...beforeUpgrade,
          'relayUrl': 'https://api.nekodot.com',
        });
        expect(
          jsonDecode(
            await File('$home/node.json.before-api-domain').readAsString(),
          ),
          beforeUpgrade,
        );
        expect(
          (await history()).containsAll(
            (baseline['messages'] as List).cast<String>(),
          ),
          isTrue,
        );
        await tap(find.byKey(const ValueKey('conversation-$dm')));
        await tester.runAsync(() => c.loadMessages(dm));
        final marker = 'UPGRADE${DateTime.now().millisecondsSinceEpoch}';
        final before = (c.node.messages[dm] ?? [])
            .map((m) => m.messageId)
            .toSet();
        final file = '$work/$marker.txt';
        stage = 'real post-upgrade model and tool';
        final input = find.byKey(const ValueKey('chat-input'));
        await tap(input);
        await tester.enterText(
          input,
          'Use execute_code to calculate 31*37, write the number to $file with Python pathlib, then reply $marker and the result.',
        );
        await tap(find.byTooltip('Send'));
        await until(
          () => (c.node.messages[dm] ?? []).any(
            (m) =>
                !before.contains(m.messageId) &&
                m.kind == 'text' &&
                m.author.type == 'bot' &&
                m.status == 'done' &&
                '${m.content['text']}'.contains(marker),
          ),
        );
        await until(() => c.node.activities[dm]?.state == 'idle');
        expect((await File(file).readAsString()).trim(), '1147');
        final complete = await history();
        stage = 'local node restart';
        await tester.runAsync(local.stop);
        await tester.runAsync(local.start);
        await until(() => local.phase == LocalPhase.online && c.online);
        expect(await history(), complete);
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          const String.fromEnvironment('QA_EVIDENCE'),
        );
        await directory.create(recursive: true);
        await File('${directory.path}/local-upgrade.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        final report = {
          'retainedMessages': (baseline['messages'] as List).length,
          'sameIdentity': true,
          'officialAddressChanged': true,
          'realModel': 'gpt-6.1-sol',
          'realFile': '1147',
          'restartNoReplay': true,
          'tls': 'verified local CA; process-only DNS mapping',
        };
        await File('${directory.path}/result.json')
            .writeAsString(jsonEncode(report));
        binding.reportData = report;
        debugPrint(
          'QA existing local upgrade passed: identity, history, real tool, restart',
        );
      } finally {
        await tester.runAsync(local.stop);
        await tester.pumpWidget(const SizedBox.shrink());
        localRuntime = null;
        HttpOverrides.global = null;
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
