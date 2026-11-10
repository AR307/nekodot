import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/tasks.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/task_details.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:window_manager/window_manager.dart';

// Replaces the removed manual-session-switch journey. All services and model calls are real.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'independent requirements keep reception, input, details and direction usable',
    (tester) async {
      if (Platform.isWindows) await DesktopHost.initialize();
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final c = NekodotClient()..prefs.language = 'en';
      const id = String.fromEnvironment('QA_CONVERSATION');
      const work = String.fromEnvironment('QA_WORK_DIR');
      const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final original = <String>{};
      final observed = <String, Map<String, dynamic>>{};
      var androidSurfaceReady = false;
      Future<void> until(
        bool Function() ready,
        String label, {
        int seconds = 420,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
        }
        expect(ready(), isTrue, reason: label);
        debugPrint('TASK_QA: $label');
      }

      Future<void> tap(Finder f) async {
        if (f.evaluate().isEmpty &&
            find.byType(TaskDetailsPage).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            f,
            -350,
            scrollable: find
                .descendant(
                  of: find.byType(TaskDetailsPage),
                  matching: find.byType(Scrollable),
                )
                .last,
            maxScrolls: 30,
          );
        }
        await until(() => f.evaluate().isNotEmpty, 'control $f', seconds: 30);
        await Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> shot(String stage) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (Platform.isAndroid) {
          if (!androidSurfaceReady) {
            await binding.convertFlutterSurfaceToImage();
            androidSurfaceReady = true;
            await tester.pump();
          }
          await binding.takeScreenshot('tasks-android-$stage');
        } else {
          await tester.runAsync(() async {
            final view = tester.binding.renderViews.first;
            final image = await (view.debugLayer! as OffsetLayer).toImage(
              Offset.zero & view.flutterView.physicalSize,
            );
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$evidence/tasks-windows-$stage.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      await tester.runAsync(() async {
        final login = await c.account.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        c.account.token = login['token'] as String;
        await c.bootstrap();
        await c.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      addTearDown(c.dispose);
      await until(
        () => c.online && c.node.conversations.isNotEmpty,
        'real Node connected',
      );
      original.addAll(c.node.tasks.keys);
      c.workspace['conversation:${c.selectedNodeId}'] = id;
      runApp(
        ListenableBuilder(
          listenable: c.prefs,
          builder: (_, child) => MaterialApp(
            theme: appTheme(
              c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            ),
            navigatorObservers: [nativeRoutes],
            builder: (_, child) => Ambient(child: child!),
            home: HomePage(client: c),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final input = find.byKey(const ValueKey('chat-input'));
      await until(
        () => input.evaluate().isNotEmpty,
        'restored conversation opened',
        seconds: 30,
      );
      Future<void> send(String text) async {
        await tester.enterText(input, text);
        await tap(find.byTooltip('Send'));
        await until(
          () => tester.widget<TextField>(input).controller!.text.isEmpty,
          'composer submitted',
        );
      }

      Future<void> displayReview(DotTask task) async {
        final quoteKey = 'taskQuote:${c.selectedNodeId}:$id';
        c.workspace.remove(quoteKey);
        c.destinations.add({
          'nodeId': c.selectedNodeId,
          'conversationId': id,
          'taskId': task.taskId,
        });
        await until(
          () => find.byType(TaskDetailsPage).evaluate().isNotEmpty,
          'task notification opens its details',
        );
        expect(c.workspace[quoteKey], isNull);
        await shot('notification-details');
        await tester.runAsync(
          () => c.prefs.update(locale: 'zh', appearance: 'dark'),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await shot('details-dark-zh');
        await tap(find.byTooltip('引用'));
        await until(
          () => input.evaluate().isNotEmpty,
          'notification quote returns to composer',
        );
        expect(c.workspace[quoteKey]?['taskId'], task.taskId);
        await tester.enterText(input, '未发送的中文草稿 $stamp');
        await shot('draft-dark-zh');
        final control = Uri.parse(const String.fromEnvironment('RELAY_URL'))
            .replace(port: 25494, path: '/', query: 'mode=node-offline');
        await tester.runAsync(() => http.get(control));
        try {
          await until(
            () => !c.online,
            'isolated Node disconnected',
            seconds: 30,
          );
          expect(
            tester.widget<TextField>(input).controller!.text,
            '未发送的中文草稿 $stamp',
          );
          await tester.runAsync(c.flushContent);
          final cached = NekodotClient()..account.token = c.account.token;
          await tester.runAsync(() async {
            await cached.openContent(c.account.me!['user']['userId'] as String);
            cached.node.retainMessages(id);
            await cached.loadMessages(id);
          });
          expect(cached.node.tasks[task.taskId]?.executionId, task.executionId);
          expect(
            cached.node.messages[id]!.any((m) => m.taskId == task.taskId),
            isTrue,
          );
          expect(cached.drafts['${c.selectedNodeId}:$id'], '未发送的中文草稿 $stamp');
          cached.dispose();
          await shot('offline-preserved');
          pushPage(
            tester.element(input),
            TaskDetailsPage(client: c, task: task),
          );
          await tester.pump(const Duration(milliseconds: 500));
          await shot('offline-details');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
        } finally {
          await tester.runAsync(
            () => http.get(control.replace(query: 'mode=node-online')),
          );
        }
        await until(() => c.online, 'actual Node reconnected', seconds: 45);
        expect(
          tester.widget<TextField>(input).controller!.text,
          '未发送的中文草稿 $stamp',
        );
        await tester.runAsync(
          () => c.prefs.update(locale: 'en', appearance: 'light'),
        );
        c.workspace.remove(quoteKey);
        await tester.enterText(input, '');
        await shot('reconnected-light');
      }

      if (const bool.fromEnvironment('QA_TASK_LAYOUT_ONLY')) {
        final task = c.node.tasks.values.lastWhere(
          (t) =>
              t.source == 'group' &&
              t.botIds.length > 1 &&
              t.reportMessageId != null,
        );
        c.destinations.add({
          'nodeId': c.selectedNodeId,
          'conversationId': task.conversationId,
          'taskId': task.taskId,
        });
        await until(
          () => find.byType(TaskDetailsPage).evaluate().isNotEmpty,
          'group requirement opened',
        );
        await shot('group-details');
        await tap(find.byTooltip('Flow'));
        await until(
          () => c.node.flow(task.conversationId, task.taskId) != null,
          'group native Flowchart received',
        );
        await shot('group-flow');
        await tap(find.byKey(const ValueKey('flow-close')));
        await tester.pageBack();
        await until(
          () => input.evaluate().isNotEmpty,
          'group composer after back',
        );
        await tester.enterText(input, '未发送的群聊草稿 · 长标题阅读检查');
        await tester.runAsync(
          () => c.prefs.update(locale: 'zh', appearance: 'dark'),
        );
        if (Platform.isWindows) {
          final size = await tester.runAsync(windowManager.getSize);
          await tester.runAsync(
            () => windowManager.setSize(const Size(430, 740)),
          );
          await tester.pump(const Duration(milliseconds: 700));
          if (input.evaluate().isEmpty) {
            final group = c.node.groups.firstWhere(
              (g) => c.node.conversations.any(
                (v) =>
                    v['conversationId'] == task.conversationId &&
                    v['groupId'] == g['groupId'],
              ),
            );
            await tap(find.text(group['name'] as String));
          }
          await shot('group-narrow-dark');
          await tester.runAsync(() => windowManager.setSize(size!));
          await tester.pump(const Duration(milliseconds: 700));
        } else {
          tester.testTextInput.unregister();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(input);
          await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
          // Gboard's floating handwriting mode has no bottom inset; its actual
          // shown state is checked with Android's input-method service.
          await tester.pump(const Duration(seconds: 2));
          await shot('group-keyboard-dark');
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          tester.testTextInput.register();
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
          ]);
          await until(
            () {
              final size = MediaQuery.sizeOf(tester.element(input));
              return size.width > size.height;
            },
            'Android landscape applied',
            seconds: 15,
          );
          await shot('group-landscape-dark');
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
          await until(
            () {
              final size = MediaQuery.sizeOf(tester.element(input));
              return size.width < size.height;
            },
            'Android portrait restored',
            seconds: 15,
          );
        }
        expect(
          tester.widget<TextField>(input).controller!.text,
          '未发送的群聊草稿 · 长标题阅读检查',
        );
        await tester.runAsync(
          () => c.prefs.update(locale: 'en', appearance: 'light'),
        );
        await shot('group-light');
        await tester.enterText(input, '');
        return;
      }

      if (const bool.fromEnvironment('QA_TASK_UI_ONLY')) {
        final pendingTask = c.node.tasks.values
            .where(
              (t) =>
                  t.conversationId == id &&
                  t.title.startsWith('Cards ') &&
                  t.active,
            )
            .lastOrNull;
        if (pendingTask != null) {
          pushPage(
            tester.element(input),
            TaskDetailsPage(client: c, task: pendingTask),
          );
          await tester.pump(const Duration(milliseconds: 500));
          final handled = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 4));
          while (DateTime.now().isBefore(deadline) &&
              c.node.tasks[pendingTask.taskId]!.reportMessageId == null) {
            final approval = (c.node.messages[id] ?? [])
                .where(
                  (m) =>
                      m.taskId == pendingTask.taskId &&
                      m.kind == 'approval' &&
                      m.status == 'streaming' &&
                      !handled.contains(m.messageId),
                )
                .firstOrNull;
            if (approval != null) {
              await tap(find.byKey(ValueKey('choice-${approval.messageId}-0')));
              handled.add(approval.messageId);
            }
            await tester.pump(const Duration(milliseconds: 200));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 300)),
            );
          }
          expect(c.node.tasks[pendingTask.taskId]!.reportMessageId, isNotNull);
          await shot('cards-resumed');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.enterText(
          input,
          List.filled(12, 'Long input before the next draft').join('\n'),
        );
        await shot('input-long');
        await tester.enterText(input, '');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(input, 'Unsent draft after sending');
        await shot('input-short');
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText).last)
            .renderEditable;
        debugPrint(
          'INPUT_GEOMETRY size=${editable.size} scroll=${editable.offset.pixels} caret=${editable.getLocalRectForCaret(const TextPosition(offset: 5))}',
        );
        await tester.pump(const Duration(seconds: 1));
        await shot('input-settled');
        expect(editable.offset.pixels, 0);
        debugPrint(
          'INPUT_SETTLED size=${editable.size} scroll=${editable.offset.pixels} caret=${editable.getLocalRectForCaret(const TextPosition(offset: 5))}',
        );
        final latest = c.node.tasks.values
            .where((t) => t.conversationId == id && t.reportMessageId != null)
            .last;
        await displayReview(latest);
        return;
      }

      List<DotTask> created() => c.node.tasks.values
          .where((t) => t.conversationId == id && !original.contains(t.taskId))
          .toList();
      await send(
        'I have two independent requirements, do both concurrently. Requirement A: use real tools to read $work/input.txt, then run foreground code that sleeps 40 seconds and writes that marker and TASK_A_$stamp to $work/task-native-A.txt. Requirement B: calculate the sum of squares of 1 through 100 using real code, sleep 90 seconds, and write the numeric result and TASK_B_$stamp to $work/task-native-B.txt. Do not just give example code; execute these harmless tasks. Start both, then let me keep talking while they work. Include A and B in their respective short titles.',
      );
      await until(() => created().length == 2, 'two requirements created');
      await until(
        () =>
            created().where((t) => t.active && t.state != 'queued').length == 2,
        'both native executions started',
      );
      expect(find.byKey(const ValueKey('chat-sessions')), findsNothing);
      expect(find.byTooltip('Stop'), findsNothing);
      await tester.enterText(input, 'Unsent draft $stamp');
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Unsent draft $stamp',
      );
      await shot('parallel');
      await send(
        'While those are running, answer this directly: 2+3 equals what? Include CHAT_DURING_$stamp. Do not create a task and do not wait for the files.',
      );
      await until(
        () => (c.node.messages[id] ?? []).any(
          (m) =>
              m.author.type == 'bot' &&
              m.status == 'done' &&
              m.taskRole != 'execution' &&
              (m.content['text'] ?? '').toString().contains(
                'CHAT_DURING_$stamp',
              ),
        ),
        'main Dot answered during work',
      );
      expect(created(), hasLength(2));
      final b = created().firstWhere((t) => t.title.contains('B'));
      await tap(find.byKey(ValueKey('task-${b.taskId}')));
      await until(
        () => find.byType(TaskDetailsPage).evaluate().isNotEmpty,
        'requirement details opened',
      );
      await tap(find.byTooltip('Flow'));
      await until(
        () =>
            find.byKey(const ValueKey('flowchart-panel')).evaluate().isNotEmpty,
        'task Flowchart opened',
      );
      await until(
        () => c.node.flow(id, b.taskId)?.taskId == b.taskId,
        'actual task Flowchart received',
        seconds: 30,
      );
      await shot('task-flow');
      await tap(find.byKey(const ValueKey('flow-close')));
      await tap(find.byTooltip('Quote'));
      await until(
        () => input.evaluate().isNotEmpty,
        'quote returned to same composer',
      );
      await send(
        'Keep this requirement. Add STEER_B_$stamp to its final report. Do not repeat any completed tools, do not interrupt A, and do not create another requirement.',
      );
      await until(
        () =>
            created().length == 2 &&
            created().every((t) => t.reportMessageId != null),
        'both real results reported',
      );
      for (final task in created()) {
        final result = await tester.runAsync(
          () =>
              c.rpc('tasks.get', {'conversationId': id, 'taskId': task.taskId}),
        );
        observed[task.taskId] = result!;
      }
      final bResult = jsonEncode(observed[b.taskId]);
      expect(bResult, contains('338350'));
      expect(bResult, contains('STEER_B_$stamp'));
      await shot('reported');
      if (const bool.fromEnvironment('QA_TASK_CARDS')) {
        final botId = created().first.botId;
        final known = c.node.tasks.keys.toSet();
        final spec = {
          'service': 'Task QA key',
          'purpose': 'Task interaction $stamp',
          'fields': [
            {'name': 'QA_KEY', 'label': 'API key', 'kind': 'password'},
          ],
          'target': {
            'kind': 'file',
            'path': '$work/task-ui-secret.env',
            'format': 'env',
          },
        };
        await tester.runAsync(
          () =>
              c.rpc('bots.update', {'botId': botId, 'approvalMode': 'manual'}),
        );
        try {
          await send(
            'Create one independent requirement titled Cards $stamp. Its executor must first use native clarify to ask which format to use, with choices Table and List. After my answer, read the nekodot-secrets skill and use the native terminal to run hermes secret request with this JSON spec: ${jsonEncode(spec)}. Never ask for the value in chat. After requesting the card, end that execution turn; the confidential delivery will continue it. After delivery use real code to check the file has a nonempty QA_KEY, print only true/false, never the value. Then report CARD_DONE_$stamp. Do not schedule anything.',
          );
          await until(
            () => c.node.tasks.values.any(
              (t) => t.conversationId == id && !known.contains(t.taskId),
            ),
            'interaction requirement created',
          );
          final task = c.node.tasks.values.firstWhere(
            (t) => t.conversationId == id && !known.contains(t.taskId),
          );
          await tap(find.byKey(ValueKey('task-${task.taskId}')));
          final handled = <String>{};
          var answered = false, delivered = false, approved = 0;
          final deadline = DateTime.now().add(const Duration(minutes: 6));
          while (DateTime.now().isBefore(deadline)) {
            final messages = (c.node.messages[id] ?? [])
                .where((m) => m.taskId == task.taskId)
                .toList();
            final pending = messages
                .where(
                  (m) =>
                      (m.kind == 'approval' || m.kind == 'question') &&
                      m.status == 'streaming' &&
                      !handled.contains(m.messageId),
                )
                .firstOrNull;
            if (pending != null) {
              expect(pending.taskRole, 'execution');
              await shot('task-${pending.kind}');
              await tap(find.byKey(ValueKey('choice-${pending.messageId}-0')));
              handled.add(pending.messageId);
              if (pending.kind == 'question') {
                answered = true;
              } else {
                approved++;
              }
            }
            final secret = messages
                .where(
                  (m) => m.kind == 'secret' && m.content['state'] == 'pending',
                )
                .firstOrNull;
            if (secret != null && !delivered) {
              final field = find.byKey(const ValueKey('secret-field-QA_KEY'));
              await until(
                () => field.evaluate().isNotEmpty,
                'task secret field visible',
                seconds: 30,
              );
              await tester.enterText(field, 'task-ui-private-$stamp');
              await shot('task-secret');
              await tap(find.byKey(const ValueKey('secret-submit')));
              delivered = true;
            }
            final latest = c.node.tasks[task.taskId]!;
            if (delivered &&
                latest.reportMessageId != null &&
                messages.any(
                  (m) =>
                      m.taskRole == 'report' &&
                      '${m.content['text']}'.contains('CARD_DONE_$stamp'),
                )) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 200));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 300)),
            );
          }
          expect(answered, isTrue);
          expect(approved, greaterThan(0));
          expect(delivered, isTrue);
          final messages = c.node.messages[id]!
              .where((m) => m.taskId == task.taskId)
              .toList();
          expect(
            messages.any(
              (m) =>
                  m.taskRole == 'report' &&
                  '${m.content['text']}'.contains('CARD_DONE_$stamp'),
            ),
            isTrue,
          );
          expect(
            jsonEncode(messages.map((m) => m.toJson()).toList()),
            isNot(contains('task-ui-private-$stamp')),
          );
          await shot('cards-completed');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
          await displayReview(c.node.tasks[task.taskId]!);
        } finally {
          await tester.runAsync(
            () => c.rpc('bots.update', {'botId': botId, 'approvalMode': 'off'}),
          );
        }
      } else {
        await displayReview(c.node.tasks[b.taskId]!);
      }
      if (Platform.isWindows) {
        final aText = await tester.runAsync(
          () => File('$work/task-native-A.txt').readAsString(),
        );
        final bText = await tester.runAsync(
          () => File('$work/task-native-B.txt').readAsString(),
        );
        expect(aText, contains('NEKODOT_NATIVE_LIVE_OK'));
        expect(bText, contains('338350'));
        await tester.runAsync(
          () => File('$evidence/tasks-native-windows.json').writeAsString(
            jsonEncode({
              'stamp': stamp,
              'model': 'gpt-6.1-sol',
              'tasks': observed,
              'files': {'a': aText, 'b': bText},
            }),
          ),
        );
      }
      binding.reportData = {
        ...?binding.reportData,
        'realServices': true,
        'parallelRequirements': true,
        'receptionWhileWorking': true,
        'taskFlow': true,
        'directedSteer': true,
        'taskIds': observed.keys.toList(),
      };
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
