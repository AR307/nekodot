import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/flow.dart';
import 'package:nekodot_native/features/flowchart.dart';
import 'package:nekodot_native/ui/design.dart';

class FlowClient extends NekodotClient {
  FlowClient() {
    selectedNodeId = 'node';
    ready = true;
    node.online = true;
    node.bots = [
      {
        'botId': 'bot',
        'displayName': 'Flow Dot',
        'avatar': {'shape': 'dot', 'color': '#E8603C'},
      },
    ];
    node.conversations = [
      {'conversationId': 'chat', 'kind': 'dm', 'botId': 'bot'},
    ];
    node.flows['chat'] = FlowSnapshot.fromJson({
      'flowId': 'run',
      'conversationId': 'chat',
      'sessionId': 'session',
      'state': 'waiting',
      'seq': 1,
      'queuedBotIds': [],
      'steps': [
        for (final (i, kind) in ['bot', 'thinking', 'code', 'approval'].indexed)
          {
            'stepId': '$i',
            'runId': 'run',
            'sessionId': 'session',
            'botId': 'bot',
            'kind': kind,
            'state': i < 2 ? 'done' : 'waiting',
            'after': [if (i > 0) '${i - 1}'],
            if (kind == 'code') 'tool': 'execute_code',
            if (kind == 'approval') 'messageId': 'card',
          },
      ],
    });
  }
  @override
  Future<void> loadFlow(String conversationId) async {
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'native plan completion folds actions but leaves previous steps inspectable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = FlowClient();
      Json item(
        String id,
        String kind,
        String state, {
        String? parent,
        String? title,
      }) => {
        'stepId': id,
        'runId': 'run',
        'sessionId': 'session',
        'botId': 'bot',
        'kind': kind,
        'state': state,
        'after': <String>[],
        'parentStepId': ?parent,
        'title': ?title,
      };
      void update(bool completed) {
        client.node.flows['chat'] = FlowSnapshot.fromJson({
          'flowId': 'plan-run',
          'conversationId': 'chat',
          'state': 'running',
          'seq': completed ? 2 : 1,
          'queuedBotIds': [],
          'steps': [
            item('bot', 'bot', 'running'),
            item(
              'plan1',
              'plan',
              completed ? 'done' : 'running',
              title: 'Read data',
            ),
            item(
              'plan2',
              'plan',
              completed ? 'running' : 'pending',
              title: 'Write report',
            ),
            item('read', 'read', 'done', parent: 'plan1'),
            if (completed) item('write', 'write', 'running', parent: 'plan2'),
          ],
        });
        client.notifyListeners();
      }

      update(false);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: FlowchartPanel(
              client: client,
              conversationId: 'chat',
              onClose: () {},
              onMessage: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flow'), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-step-read')), findsOneWidget);
      update(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flow-step-read')), findsNothing);
      expect(find.byKey(const ValueKey('flow-step-write')), findsOneWidget);
      await tester.tap(find.text('Read data'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flow-step-read')), findsOneWidget);
      update(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flow-step-read')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    },
  );
  for (final width in [340.0, 390.0]) {
    testWidgets('waiting execution remains inspectable at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = FlowClient();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              disableAnimations: true,
            ),
            child: FlowchartPanel(
              client: client,
              conversationId: 'chat',
              onClose: () {},
              onMessage: (id) async {
                selected = id;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('等待授权'), findsOneWidget);
      await tester.tap(find.text('等待授权'));
      expect(selected, 'card');
      client.node.online = false;
      client.notifyListeners();
      await tester.pump();
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.text('执行代码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }
}
