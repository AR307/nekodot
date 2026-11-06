import 'package:nekodot_native/data/chat_models.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nekodot_native/features/bot_model.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/ui/chat_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/work.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the installed client's saved login untouched.
class MemoryVault extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

const email = String.fromEnvironment('QA_EMAIL');
const password = String.fromEnvironment('QA_PASSWORD');
const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const workFolder = String.fromEnvironment('QA_WORK_DIR');
const evidenceFolder = String.fromEnvironment('QA_EVIDENCE_DIR');
const hold = bool.fromEnvironment('QA_HOLD');
const releaseFile = String.fromEnvironment('QA_RELEASE_FILE');

/// Exercises the candidate UI against real Hermes and model calls. Windows
/// hosts the isolated Node; Android connects while that journey holds.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'catalog model settings, compact notices and progress with real Hermes',
    (tester) async {
      final android = Platform.isAndroid;
      final report = <String, Object?>{'platform': Platform.operatingSystem};
      void note(String key, Object? value) {
        report[key] = value;
        debugPrint('QA $key: ${jsonEncode(value)}');
      }

      SharedPreferences.setMockInitialValues({});
      final client = NekodotClient(vault: MemoryVault());
      LocalRuntime? local;
      if (!android) {
        await LocalLocation(runtimeFolder, dataFolder).save();
        local = localRuntime = LocalRuntime(client);
        addTearDown(() => local!.stop());
        await DesktopHost.initialize();
        tester.view.physicalSize = const Size(2880, 2000);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
      }

      Future<void> until(
        bool Function() done, {
        int seconds = 90,
        String what = '',
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        expect(done(), isTrue, reason: 'Did not reach: $what');
      }

      Future<void> settle([int ms = 500]) async {
        final end = DateTime.now().add(Duration(milliseconds: ms));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 40));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      // Centred: the chat list runs under the composer, so an item scrolled
      // only to the list's edge can sit behind it.
      Future<void> reveal(Finder finder) =>
          Scrollable.ensureVisible(tester.element(finder.first), alignment: .5);

      Future<void> tap(Finder finder) async {
        await reveal(finder);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(finder.hitTestable().first);
        await settle(450);
      }

      var converted = false;
      Future<void> shot(String name) async {
        await settle(800);
        if (android) {
          if (!converted) {
            await binding.convertFlutterSurfaceToImage();
            converted = true;
            await tester.pump();
          }
          await binding.takeScreenshot('ui-refinement-android-$name');
          return;
        }
        await Directory(evidenceFolder).create(recursive: true);
        final view = tester.binding.renderViews.first;
        await tester.runAsync(() async {
          // The root layer already scales by the device ratio.
          final image = await (view.debugLayer! as OffsetLayer).toImage(
            Offset.zero & view.flutterView.physicalSize,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidenceFolder/ui-refinement-windows-$name.png')
              .writeAsBytes(png!.buffer.asUint8List());
        });
      }

      runApp(NekodotApp(client: client));
      await until(
        () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
        what: 'auth page',
      );
      await settle(1500);
      final notice = find.widgetWithText(TextButton, '继续');
      if (notice.evaluate().isNotEmpty) await tap(notice);
      await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        password,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.widgetWithText(FilledButton, '登录'));
      await until(() => client.connection.ready, what: 'signed in');
      await until(
        () =>
            client.online &&
            (local == null || local.phase == LocalPhase.online) &&
            client.node.bots.isNotEmpty,
        seconds: 600,
        what: 'real node online with its Bots',
      );
      note('node', client.selectedNodeId);
      await settle(1500);

      final bot = client.node.bots.firstWhere(
        (b) => '${b['displayName']}'.startsWith('创建验收'),
      );
      final botId = '${bot['botId']}';
      final dm = client.node.conversations.firstWhere(
        (r) => r['kind'] == 'dm' && r['botId'] == botId,
      );
      final id = '${dm['conversationId']}';
      await tap(find.byKey(ValueKey('conversation-$id')));
      final input = find.byKey(const ValueKey('chat-input'));
      await until(() => input.evaluate().isNotEmpty);
      await until(() => client.node.messages[id] != null);
      List<ChatMessage> messages() => client.node.messages[id] ?? [];
      bool idle() => client.node.activities[id]?.state == 'idle';
      await until(idle);
      if (!android) {
        await tester.drag(
          find.byKey(const ValueKey('sidebar-split')),
          const Offset(-700, 0),
        );
        await settle();
        expect(client.prefs.sidebarWidth, 240);
        expect(tester.takeException(), isNull);
        await shot('narrow-sidebar');
      }
      expect(find.byKey(const ValueKey('composer-model')), findsNothing);
      final plus = find.byKey(const ValueKey('composer-attach'));
      expect(plus, findsOneWidget);
      expect(
        tester.getCenter(plus).dx,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('composer-card'))).dx,
        ),
      );
      note('composer', 'attachment on right; no model control');
      await tap(find.byTooltip('详情').first);
      await until(
        () => find
            .byKey(const ValueKey('bot-model-settings'))
            .evaluate()
            .isNotEmpty,
      );
      await tap(find.byKey(const ValueKey('bot-model-settings')).first);
      await until(() => find.byType(BotModelPage).evaluate().isNotEmpty);
      final choose = find.byKey(const ValueKey('model-choice'));
      await until(
        () => tester.widget<OutlinedButton>(choose).onPressed != null,
        seconds: 180,
        what: 'native model catalog',
      );
      await tap(choose);
      final search = find.byKey(const ValueKey('model-search'));
      await tester.enterText(search, 'gpt-6');
      await settle();
      final options = find
          .byWidgetPredicate(
            (w) => w is ListTile && '${w.key}'.contains('model-option-'),
          )
          .evaluate()
          .toList();
      note('models', options.map((e) => '${e.widget.key}').toList());
      expect(options.length, greaterThan(1));
      await shot('model-catalog');
      final alternate = find.byKey(const ValueKey('model-option-gpt-6-sol'));
      await tap(alternate);
      await tester.enterText(
        find.byKey(const ValueKey('model-context-length')),
        '128000',
      );
      await tap(find.byKey(const ValueKey('save-bot-model')));
      await until(
        () => find.byType(BotModelPage).evaluate().isEmpty,
        seconds: 180,
        what: 'model saved',
      );
      final info = await tester.runAsync(
        () => client.rpc('models.info', {'botId': botId}),
      );
      note('nativeModel', {
        'model': info!['model'],
        'configuredContext': info['configuredContext'],
      });
      expect(info['configuredContext'], 128000);
      await tap(find.widgetWithText(ExpansionTile, '模型与压缩'));
      await shot('model-details');
      await tap(
        find.descendant(of: find.byType(BotDetails), matching: find.text('设置')),
      );
      final advanced = find.byKey(const ValueKey('advanced-settings'));
      await until(() => advanced.evaluate().isNotEmpty);
      expect(tester.widget<SwitchListTile>(advanced).value, isFalse);
      await tap(advanced);
      await tap(find.byKey(const ValueKey('settings-group-model')));
      final settingSearch = find.descendant(
        of: find.byType(HermesSettings),
        matching: find.byType(TextField),
      );
      await until(() => settingSearch.evaluate().isNotEmpty);
      await tester.enterText(settingSearch, 'auxiliary.compression.model');
      await settle();
      await tap(find.widgetWithText(ListTile, '上下文压缩模型'));
      await until(
        () =>
            choose.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(choose).onPressed != null,
        seconds: 180,
        what: 'auxiliary model catalog',
      );
      await tap(choose);
      await tester.enterText(search, 'gpt-6.1-sol');
      await settle();
      await tap(find.byKey(const ValueKey('model-option-gpt-6.1-sol')));
      await shot('auxiliary-model');
      await tap(find.widgetWithText(FilledButton, '保存'));
      await until(() => find.byType(AlertDialog).evaluate().isEmpty);
      final settings = await tester.runAsync(
        () => client.rpc('hermes.settings.get', {'botId': botId}),
      );
      final auxiliary = objects(settings!['fields'])
          .firstWhere((field) => field['key'] == 'auxiliary.compression.model');
      expect(auxiliary['value'], 'gpt-6.1-sol');
      note('auxiliaryModel', auxiliary['value']);
      await tap(find.byType(BackButton).first);
      if (android) {
        Navigator.of(tester.element(find.byType(BotDetails))).pop();
      } else {
        await tap(
          find.descendant(
            of: find.byType(BotDetails),
            matching: find.byTooltip('关闭'),
          ),
        );
      }
      await until(() => find.byType(BotDetails).evaluate().isEmpty);
      Future<void> command(String text) async {
        var op = await tester.runAsync(
          () => client.rpc('commands.execute', {
            'conversationId': id,
            'botId': botId,
            'command': text,
            'clientMsgId': uid(),
          }),
        );
        for (var i = 0; i < 120; i++) {
          op = await tester.runAsync(
            () => client.rpc('operations.get', {
              'operationId': op!['operationId'],
            }),
          );
          if (op!['status'] != 'running') break;
          await settle(500);
        }
        expect(op!['status'], 'done', reason: '$op');
        await client.loadMessages(id);
        await settle();
      }

      final previousSession = await tester.runAsync(
        () => client.rpc('sessions.list', {'botId': botId}),
      );
      await command('/new UI refinement');
      expect(find.text('已创建新会话'), findsWidgets);
      await command('/resume ${previousSession!['currentSessionId']}');
      expect(find.text('已切换会话'), findsWidgets);
      note('commands', ['new', 'resume']);
      await shot('command-notice');
      final seen = messages().map((m) => m.messageId).toSet();
      final task = android
          ? '请先用一句正常的话回应我，再用 terminal 执行 python -c "print(17*19)"，最后只告诉我真实结果。'
          : '请先用一句自然的话回应我，然后用 terminal 运行 python -c "print(17*19)"。接着创建一个名字为 UI提醒验收的定时任务：3分钟后只回复“UI例行任务执行完成”，单次执行。请使用真实工具，最后简洁告诉我计算结果和已安排的任务。';
      await tester.enterText(input, task);
      await settle();
      await tap(find.byTooltip('发送'));
      final statuses = <String>[];
      final end = DateTime.now().add(const Duration(minutes: 8));
      ChatMessage? reply;
      var liveShot = false;
      while (DateTime.now().isBefore(end)) {
        final pending = messages()
            .where((m) => m.kind == 'approval' && m.status == 'streaming')
            .lastOrNull;
        if (pending != null) {
          final allow = find.byKey(ValueKey('choice-${pending.messageId}-0'));
          if (allow.evaluate().isNotEmpty) {
            await tap(allow);
            continue;
          }
        }
        final row = find.byKey(const ValueKey('thinking-row'));
        if (row.evaluate().isNotEmpty) {
          final line = find
              .descendant(of: row, matching: find.byType(Text))
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .lastOrNull;
          if (line != null && line != statuses.lastOrNull) statuses.add(line);
          if (!liveShot &&
              messages().any(
                (m) => !seen.contains(m.messageId) && m.kind == 'tool',
              )) {
            await shot('working');
            liveShot = true;
          }
        }
        reply = messages()
            .where(
              (m) =>
                  !seen.contains(m.messageId) &&
                  m.kind == 'text' &&
                  m.author.type == 'bot' &&
                  m.status == 'done',
            )
            .lastOrNull;
        if (reply != null && idle()) break;
        await settle(300);
      }
      note('statuses', statuses);
      expect(reply, isNotNull);
      expect(reply!.content['text'], contains('323'));
      final tools = messages()
          .where((m) => !seen.contains(m.messageId) && m.kind == 'tool')
          .toList();
      expect(tools, isNotEmpty);
      note('tools', tools.map((m) => m.content['tool']).toList());
      final acknowledgements = messages().where(
        (m) => !seen.contains(m.messageId) && m.kind == 'commentary',
      );
      for (final message in acknowledgements) {
        expect(visibleMessageText(message), isNot(contains('\n正在')));
      }
      note(
        'acknowledgements',
        acknowledgements
            .map(visibleMessageText)
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      final progress = messages()
          .where((m) => !seen.contains(m.messageId) && isProgressMessage(m))
          .toList();
      for (final m in progress) {
        expect(
          find.byWidgetPredicate(
            (w) => w is MessageTile && w.message.messageId == m.messageId,
          ),
          findsNothing,
        );
      }
      await shot('chat-result');
      final tile = find.byWidgetPredicate(
        (w) => w is MessageTile && w.message.messageId == reply!.messageId,
      );
      await reveal(tile);
      if (!android) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        await settle();
        Finder opacity() => find
            .ancestor(
              of: find.descendant(of: tile, matching: find.byType(CopyButton)),
              matching: find.byType(Opacity),
            )
            .first;
        expect(tester.widget<Opacity>(opacity()).opacity, 0);
        await mouse.moveTo(tester.getCenter(tile));
        await settle();
        expect(tester.widget<Opacity>(opacity()).opacity, 1);
        await shot('copy-hover');
        await mouse.removePointer();
        await until(
          () => messages().any(
            (m) =>
                m.kind == 'routine' &&
                !seen.contains(m.messageId) &&
                m.content['action'] == 'executed',
          ),
          seconds: 300,
          what: 'native scheduled task completed',
        );
        final notice = find.byWidgetPredicate(
          (w) => w is ChatNotice && w.text.startsWith('已执行'),
        );
        await settle();
        tester
            .widget<ListView>(find.byKey(const ValueKey('chat-messages')))
            .controller!
            .jumpTo(0);
        await settle();
        await reveal(notice.last);
        await shot('routine-executed');
        note(
          'routineNotices',
          messages()
              .where((m) => m.kind == 'routine' && !seen.contains(m.messageId))
              .map((m) => m.content['action'])
              .toList(),
        );
        expect(
          messages()
              .where((m) => m.kind == 'routine' && !seen.contains(m.messageId))
              .map((m) => m.content['action']),
          isNot(contains('stopped')),
        );
      }
      expect(tester.takeException(), isNull);
      note('done', true);
      if (!android) {
        await File('$evidenceFolder/ui-refinement-windows.json')
            .writeAsString(jsonEncode(report));
        if (hold) {
          final release = File(releaseFile);
          debugPrint('QA holding for Android: ${release.path}');
          await until(
            release.existsSync,
            seconds: 1800,
            what: 'Android completed',
          );
        }
      }
      debugPrint('QA REPORT ${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
