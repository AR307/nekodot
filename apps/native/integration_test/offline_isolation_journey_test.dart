import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline logout stops delivery and isolates another real account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'dark',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    const node = String.fromEnvironment('QA_NODE'),
        dm = String.fromEnvironment('QA_CONVERSATION');
    final marker = 'UNSENT_LOGOUT_${DateTime.now().millisecondsSinceEpoch}';
    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue);
    }

    Future<void> login(String email, String password) async {
      await until(
        () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        password,
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await until(() => c.connection.ready);
    }

    Future<void> fault(String mode) async {
      await tester.runAsync(
        () => http.get(
          Uri.parse(
            '${const String.fromEnvironment('RELAY_URL')}/__fault?mode=$mode',
          ),
        ),
      );
    }

    await fault('online');
    await tester.pumpWidget(NekodotApp(client: c));
    await login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tester.runAsync(() => c.selectNode(node));
    await until(
      () => find.byKey(ValueKey('conversation-$dm')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(ValueKey('conversation-$dm')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await fault('offline');
    await until(() => !c.connection.ready);
    await tester.enterText(input, marker);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('发送'));
    await until(() => c.deliveries.items.isNotEmpty);
    final oldDirectory = c.store!.directory;
    Navigator.of(tester.element(input))
        .push(MaterialPageRoute<void>(builder: (_) => SettingsPage(client: c)));
    await until(() => find.text('退出账号').evaluate().isNotEmpty);
    await tester.ensureVisible(find.text('退出账号'));
    await tester.tap(find.text('退出账号'));
    await until(
      () => c.account.token == null && c.nodes.isEmpty && c.store == null,
    );
    expect(c.deliveries.items, isEmpty);
    final oldQueue = await tester.runAsync(
      () => File('${oldDirectory.path}/deliveries.json').readAsString(),
    );
    expect(jsonDecode(oldQueue!)['items'], isEmpty);
    await fault('online');
    await login(
      const String.fromEnvironment('QA_OTHER_EMAIL'),
      const String.fromEnvironment('QA_OTHER_PASSWORD'),
    );
    await until(
      () =>
          c.account.me?['user']?['email'] ==
          const String.fromEnvironment('QA_OTHER_EMAIL'),
    );
    expect(c.node.bots, isEmpty);
    expect(c.drafts, isEmpty);
    expect(c.views, isEmpty);
    expect(c.deliveries.items, isEmpty);
    expect(c.store!.directory.path, isNot(oldDirectory.path));
    await tester.runAsync(c.logout);
    await login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tester.runAsync(() => c.selectNode(node));
    await until(
      () => find.byKey(ValueKey('conversation-$dm')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(ValueKey('conversation-$dm')));
    await until(() => c.node.messages[dm]?.isNotEmpty == true);
    expect(c.deliveries.items, isEmpty);
    expect(
      (c.node.messages[dm] ?? []).where(
        (m) => '${m.content['text']}'.contains(marker),
      ),
      isEmpty,
    );
    final result = {
      'realAccountsIsolated': true,
      'offlineLogoutCancelledDelivery': true,
      'oldHistoryRetainedOnReturn': c.node.messages[dm]!.isNotEmpty,
    };
    binding.reportData = result;
    await tester.runAsync(
      () => File(
        '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/windows-isolation-journey.json',
      ).writeAsString(jsonEncode(result)),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
