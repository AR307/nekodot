import 'package:nekodot_native/data/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/ui/design.dart';

import 'product_test.dart' show JourneyClient, bot;

void main() {
  testWidgets(
    'reveal a password without changing it; switching mode hides it',
    (tester) async {
      final client = NekodotClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: AuthPage(client: client),
        ),
      );
      final field = find.byKey(const ValueKey('auth-password'));
      final reveal = find.byKey(const ValueKey('auth-reveal-password'));
      await tester.enterText(field, 'Only-a-test-password');
      final before = tester.widget<TextField>(field).controller!.value;
      await tester.ensureVisible(reveal);
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      expect(tester.widget<TextField>(field).controller!.value, before);
      expect(tester.getSize(reveal).height, greaterThanOrEqualTo(44));
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-switch-mode')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-switch-mode')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );

  for (final glass in [false, true]) {
    testWidgets(
      'avatar colors have 44px targets and keyboard selection ($glass)',
      (tester) async {
        tester.view.physicalSize = Size(glass ? 390 : 1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final client = JourneyClient();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light, glass: glass),
            home: BotEditor(client: client, existing: bot),
          ),
        );
        await tester.pumpAndSettle();
        final key = ValueKey('avatar-color-${avatarColors[1]}');
        final target = find.byKey(key);
        expect(tester.getSize(target), const Size(44, 44));
        bool focused() =>
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<InkResponse>()
                ?.key ==
            key;
        for (var n = 0; n < 40 && !focused(); n++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(focused(), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final state = tester
            .widgetList<Semantics>(
              find.descendant(of: target, matching: find.byType(Semantics)),
            )
            .singleWhere((s) => s.properties.label == avatarColors[1]);
        expect(state.properties.selected, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        client.dispose();
      },
    );
  }

  testWidgets('keyboard scrolls chat history, not the draft', (tester) async {
    final client = JourneyClient();
    client.node.messages['dm'] = [
      for (var i = 0; i < 40; i++)
        ChatMessage.fromJson({
          'messageId': 'fixture',
          'conversationId': 'dm',
          'createdAt': '2026-11-06T00:00:00Z',
          'seq': 0,
          ...{
            'messageId': 'reply-$i',
            'conversationId': 'dm',
            'author': {'type': 'bot', 'id': bot['botId']},
            'kind': 'text',
            'status': 'done',
            'content': {
              'text': 'Reply $i\n\nA separate paragraph for reading.',
            },
          },
        }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: ChatPage(client: client, conversationId: 'dm'),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('chat-input'));
    await tester.enterText(input, 'Unsent draft');
    Focus.of(tester.element(find.byKey(const ValueKey('chat-messages'))))
        .requestFocus();
    await tester.pump();
    final list = tester.widget<ScrollView>(
      find.byKey(const ValueKey('chat-messages')),
    );
    final position = list.controller!.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(position.minScrollExtent));
    final reading = position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(reading));
    await tester.tap(find.byKey(const ValueKey('chat-latest')));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(position.minScrollExtent, 1));
    expect(tester.widget<TextField>(input).controller!.text, 'Unsent draft');
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });
}
