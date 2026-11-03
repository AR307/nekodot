import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/secrets.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('manage actual saved Bot credentials through the native UI', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final c = NekodotClient();
    const botId = String.fromEnvironment('QA_SECOND_BOT');
    const mode = String.fromEnvironment('QA_SECRET_MODE');
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
      }
      expect(ready(), isTrue, reason: 'Native management journey timed out');
    }

    Future<void> tap(Finder f) async {
      await Scrollable.ensureVisible(tester.element(f), alignment: .4);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    late Json entry;
    await tester.runAsync(() async {
      final s = await c.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      );
      c.token = s['token'];
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    c.language = Platform.isWindows ? 'en' : 'zh';
    runApp(
      MaterialApp(
        theme: appTheme(
          Platform.isWindows ? Brightness.dark : Brightness.light,
        ),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: c),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await until(() => c.online && c.node.conversations.isNotEmpty);
    entry =
        objects(
          (await tester.runAsync(
            () => c.rpc('secrets.list', {'botId': botId}),
          ))!['credentials'],
        ).lastWhere(
          (v) =>
              v['enabled'] == true &&
              (mode == 'management-sync'
                  ? object(v['target'])['kind'] == 'vault'
                  : object(v['target'])['kind'] == 'file' &&
                        object(v['target'])['format'] == 'env'),
        );
    final conversationId =
        '${c.node.conversations.firstWhere((v) => v['kind'] == 'dm' && v['botId'] == botId)['conversationId']}';
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    await until(
      () => find.byTooltip(c.tr('详情', 'Details')).evaluate().isNotEmpty,
    );
    await tap(find.byTooltip(c.tr('详情', 'Details')).first);
    await until(
      () => find.byKey(const ValueKey('bot-secrets')).evaluate().isNotEmpty,
    );
    await tap(find.byKey(const ValueKey('bot-secrets')));
    final savedName = find.byKey(
      ValueKey('saved-secret-${entry['credentialId']}'),
    );
    await until(
      () =>
          find.byType(BotSecretsPage).evaluate().isNotEmpty &&
          find.byType(Scrollable).evaluate().isNotEmpty,
    );
    await tester.scrollUntilVisible(
      savedName,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    Finder row() =>
        find.ancestor(of: savedName, matching: find.byType(Panel)).first;
    await tap(
      find.descendant(
        of: row(),
        matching: find.widgetWithText(
          TextButton,
          c.tr('重新交付 / 替换', 'Re-deliver / replace'),
        ),
      ),
    );
    await until(() => find.byType(SecretCard).evaluate().isNotEmpty);
    await tap(
      find
          .descendant(
            of: find.byType(SecretCard),
            matching: find.byType(ListTile),
          )
          .first,
    );
    final field = find.byKey(
      ValueKey('secret-field-${objects(entry['fields']).first['name']}'),
    );
    await until(() => field.evaluate().isNotEmpty);
    final requestId = tester
        .widget<SecretCard>(find.byType(SecretCard))
        .content['requestId'];
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('secret-save')))
          .value,
      isFalse,
    );
    if (mode == 'management-sync') {
      final controller = tester.widget<TextField>(field).controller!;
      await tester.enterText(field, 'harmless-unsent-test-input');
      if (Platform.isAndroid) {
        debugPrint('QA background ready');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 4)),
        );
        await until(
          () =>
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed,
        );
        expect(controller.text, isEmpty);
        await tester.enterText(field, 'harmless-unsent-test-input');
      }
      final peer = NekodotClient();
      await tester.runAsync(() async {
        final session = await peer.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        peer.token = session['token'];
        await peer.bootstrap();
        await peer.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      await until(() => peer.online);
      await tester.runAsync(
        () => peer.rpc('secrets.cancel', {
          'botId': botId,
          'requestId': requestId,
        }),
      );
      await until(() => field.evaluate().isEmpty, seconds: 20);
      expect(controller.text, isEmpty);
      binding.reportData = {
        'actualServerMetadata': true,
        'secondClientCancellation': true,
        'managementFormSynchronized': true,
        'inputsCleared': true,
        if (Platform.isAndroid) 'backgroundInputCleared': true,
      };
      debugPrint('QA real management cross-client sync passed');
      peer.dispose();
      c.dispose();
      return;
    }
    if (Platform.isAndroid) {
      tester.testTextInput.unregister();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await tap(field);
      await until(() => tester.view.viewInsets.bottom > 0, seconds: 20);
      debugPrint('QA soft keyboard ready');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pump(const Duration(milliseconds: 300));
      tester.testTextInput.register();
    }
    await tester.enterText(field, 'nekodot-qa-key-20261103');
    await tap(find.byKey(const ValueKey('secret-save')));
    final controller = tester.widget<TextField>(field).controller!;
    await tap(find.byKey(const ValueKey('secret-submit')));
    await until(
      () => (c.node.messages[conversationId] ?? []).any(
        (m) =>
            m['kind'] == 'secret' &&
            m['content']['state'] == 'applied' &&
            m['content']['requestId'] == requestId,
      ),
    );
    expect(controller.text, isEmpty);
    await tester.pageBack();
    await until(
      () =>
          find.byType(BotSecretsPage).evaluate().isNotEmpty &&
          savedName.evaluate().isNotEmpty,
    );
    await tap(
      find.descendant(
        of: row(),
        matching: find.widgetWithText(TextButton, c.tr('停用', 'Disable')),
      ),
    );
    await until(
      () => find
          .descendant(
            of: row(),
            matching: find.textContaining(c.tr('已停用', 'Disabled')),
          )
          .evaluate()
          .isNotEmpty,
    );
    final list = (await tester.runAsync(
      () => c.rpc('secrets.list', {'botId': botId}),
    ))!;
    expect(
      objects(list['credentials']).firstWhere(
        (v) => v['credentialId'] == entry['credentialId'],
      )['enabled'],
      isFalse,
    );
    binding.reportData = {
      'actualServerMetadata': true,
      'replacedSameCredential': true,
      'disabled': true,
      'inputsCleared': true,
      'nativeUI': true,
    };
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('confidential-management-android');
    }
    debugPrint('QA real credential management passed');
    if (Platform.isWindows) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 60)),
      );
    }
    c.dispose();
  });
}
