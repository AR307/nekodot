import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_timeline.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('existing real history survives mobile back and reopen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    Future<void> until(bool Function() done) async {
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue);
    }

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final dir = Directory(
          '${(await getExternalStorageDirectory())!.path}/core-evidence',
        );
        await dir.create(recursive: true);
        await File('${dir.path}/$name.png').writeAsBytes(bytes);
        image.dispose();
      });
    }

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
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(
      () => c.selectNode(const String.fromEnvironment('QA_NODE')),
    );
    await until(() => c.online && c.node.conversations.isNotEmpty);
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final row = find.byKey(const ValueKey('conversation-$dm'));
    await until(() => row.evaluate().isNotEmpty);
    await tester.tap(row);
    await until(
      () =>
          find.byType(ChatTimeline).evaluate().isNotEmpty &&
          (c.node.messages[dm]?.isNotEmpty ?? false),
    );
    await tester.pump(const Duration(seconds: 1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 600),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final timeline = tester.widget<ChatTimeline>(find.byType(ChatTimeline));
    final before = timeline.scroll.offset;
    debugPrint(
      'HISTORY before=$before min=${timeline.scroll.position.minScrollExtent} max=${timeline.scroll.position.maxScrollExtent} since=${timeline.since}',
    );
    expect(
      before - timeline.scroll.position.minScrollExtent,
      greaterThan(LatestScrollController.near),
    );
    await shot('android-history-before');
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint(
      'HISTORY saved=${c.node.viewports[dm]} cached=${c.node.messages.containsKey(dm)}',
    );
    expect(c.node.messages.containsKey(dm), isFalse);
    expect(c.node.viewports[dm]?.offset, closeTo(before, 1));
    await until(() => row.evaluate().isNotEmpty);
    await tester.tap(row);
    await until(
      () =>
          find.byType(ChatTimeline).evaluate().isNotEmpty &&
          (c.node.messages[dm]?.isNotEmpty ?? false),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    final after = tester
        .widget<ChatTimeline>(find.byType(ChatTimeline))
        .scroll
        .offset;
    debugPrint('HISTORY restored=$after');
    await shot('android-history-after');
    expect(after, closeTo(before, 1));
  });
}
