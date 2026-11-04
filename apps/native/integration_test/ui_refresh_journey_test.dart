import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/data/hermes_zh.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/user_memory.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
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

const relay = String.fromEnvironment('RELAY_URL');
const email = String.fromEnvironment('QA_EMAIL');
const password = String.fromEnvironment('QA_PASSWORD');
const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const workFolder = String.fromEnvironment('QA_WORK_DIR');
const evidenceFolder = String.fromEnvironment('QA_EVIDENCE_DIR');
const hold = bool.fromEnvironment('QA_HOLD');

/// The refreshed home, Bot details and settings, on a real node with
/// official Hermes. The Windows run hosts the node on this computer; the
/// Android run connects to it while the Windows run holds.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('refreshed home, details and settings on a real node', (
    tester,
  ) async {
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

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(finder.hitTestable().first);
      await settle(450);
    }

    var converted = false;
    Future<void> shot(String name) async {
      await settle(700);
      if (android) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('ui-refresh-android-$name');
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
        await File('$evidenceFolder/ui-refresh-windows-$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      });
    }

    Future<Map<String, dynamic>> qa(String path) async {
      final response = await http.get(
        Uri.parse('$relay$path'),
        headers: {'Authorization': 'Bearer ${client.token}'},
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
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
    await until(() => client.ready, what: 'signed in');
    await until(
      () =>
          client.online &&
          (local == null || local.phase == LocalPhase.online) &&
          client.node.bots.isNotEmpty,
      seconds: 600,
      what: 'real node online with its Bots',
    );
    final nodeId = client.selectedNodeId!;
    note('node', nodeId);

    // A team worth showing: a second Bot and a group, made on the real node.
    if (!android && client.node.groups.isEmpty) {
      final source = objects((await client.rpc('providers.list'))['sources'])
          .firstWhere((s) => s['ready'] == true);
      final model = (await qa('/qa/model'))['model'] as String;
      final second = await client.rpc('bots.create', {
        'displayName': '笔笔',
        'role': '周报、邮件和文案，语气简洁',
        'model': model,
        'sourceId': source['sourceId'],
        'avatar': {'shape': 'bunny', 'color': '#2E8BFF'},
      });
      await client.rpc('groups.create', {
        'name': '周报小组',
        'botIds': [
          client.node.bots.first['botId'],
          object(second['bot'])['botId'],
        ],
        'leadBotId': object(second['bot'])['botId'],
      });
      await until(
        () => client.node.groups.isNotEmpty && client.node.bots.length > 1,
        what: 'group synced',
      );
    }
    await settle(1500);

    // Home: groups first, then Bots; each section folds.
    final groupSection = find.byKey(const ValueKey('section-groups'));
    final botSection = find.byKey(const ValueKey('section-bots'));
    await until(
      () =>
          groupSection.evaluate().isNotEmpty &&
          botSection.evaluate().isNotEmpty,
      what: 'two sections',
    );
    expect(
      tester.getTopLeft(groupSection).dy,
      lessThan(tester.getTopLeft(botSection).dy),
    );
    final dm = client.node.conversations.firstWhere((x) => x['kind'] == 'dm');
    final dmRow = find.byKey(ValueKey('conversation-${dm['conversationId']}'));
    // Opens the details from the chat title and samples the frames as they
    // appear, with the real time of each: they must pass through between.
    Future<(List<String>, bool)> openDetails() async {
      await tester.tap(find.byTooltip('详情').first);
      final clock = Stopwatch()..start();
      final frames = <String>[];
      var between = false;
      for (var frame = 0; frame < 40; frame++) {
        // The time stamp the animations of the next frame are given.
        var stamp = Duration.zero;
        SchedulerBinding.instance.scheduleFrameCallback((t) => stamp = t);
        await tester.pump(const Duration(milliseconds: 16));
        final scale = find.ancestor(
          of: find.byType(BotDetails),
          matching: find.byType(ScaleTransition),
        );
        final value = !android
            ? tester.getSize(find.byType(SidePanel)).width
            : scale.evaluate().isEmpty
            ? null
            : tester.widget<ScaleTransition>(scale.first).scale.value;
        if (value == null) continue;
        frames.add(
          '${value.toStringAsFixed(3)}@${clock.elapsedMilliseconds}'
          '/${stamp.inMilliseconds}',
        );
        if (android
            ? value > .9405 && value < .9995
            : value > 5 && value < 335) {
          between = true;
        }
      }
      return (frames, between);
    }

    if (android) {
      // Timed before the first screenshot: taking one switches Android's
      // surface to images, which slows every frame after it.
      await tap(dmRow);
      await until(
        () => find.byTooltip('详情').evaluate().isNotEmpty,
        what: 'chat title',
      );
      final (frames, between) = await openDetails();
      note('detailsFrames', frames);
      expect(between, isTrue);
      await settle(600);
      await tester.pageBack();
      await settle(400);
      await tester.pageBack();
      await settle(400);
    }
    await shot('home');
    // Black and white on every device: the ground is plain white or black.
    final ground = tester.element(botSection).tone.base.toARGB32();
    note('ground', ground.toRadixString(16));
    expect([0xffffffff, 0xff000000], contains(ground));
    await tap(botSection);
    await settle(300);
    note('botsFolded', dmRow.evaluate().isEmpty);
    expect(dmRow.evaluate(), isEmpty);
    await tap(botSection);
    await until(() => dmRow.evaluate().isNotEmpty, what: 'Bots unfolded');

    // Chat, then details that grow out of the title.
    await tap(dmRow);
    await until(
      () => find.byTooltip('详情').evaluate().isNotEmpty,
      what: 'chat title',
    );
    await shot('chat');

    // The command palette describes every command in Chinese.
    final composer = find.descendant(
      of: find.byType(ChatPage),
      matching: find.byType(TextField),
    );
    await tester.enterText(composer.last, '/');
    await until(
      () => find.text(hermesCommandZh['/new']!).evaluate().isNotEmpty,
      what: 'commands in Chinese',
    );
    final commands = objects(
      (await client.rpc('commands.list', {
        'botId': '${dm['botId']}',
      }))['commands'],
    );
    final untranslated = [
      for (final command in commands)
        if (!hermesCommandZh.containsKey(command['name'])) command['name'],
    ];
    note('commands', commands.length);
    note('commandsWithoutChinese', untranslated);
    expect(untranslated, isEmpty);
    await shot('commands');
    await tester.enterText(composer.last, '');
    await settle(400);

    final (frames, between) = await openDetails();
    note(android ? 'detailsFramesAfterShots' : 'detailsFrames', frames);
    if (!android) expect(between, isTrue);
    await settle(600);
    if (!android) {
      note('panelWidth', tester.getSize(find.byType(SidePanel)).width);
    }
    await shot('details');

    // Bot settings by kind; installation settings are not here.
    await tap(find.widgetWithText(Tab, '设置'));
    await until(
      () => find
          .byKey(const ValueKey('settings-group-model'))
          .evaluate()
          .isNotEmpty,
      what: 'settings by kind',
    );
    final botId = '${dm['botId']}';
    final own = await client.rpc('hermes.settings.get', {'botId': botId});
    final shared = await client.rpc('hermes.shared.get');
    final ownKeys = [for (final f in objects(own['fields'])) '${f['key']}'];
    final sharedKeys = [
      for (final f in objects(shared['fields'])) '${f['key']}',
    ];
    final kinds = <String, int>{};
    for (final f in objects(own['fields'])) {
      kinds.update('${f['group']}', (n) => n + 1, ifAbsent: () => 1);
    }
    note('botSettingKinds', kinds);
    note('sharedSettingCount', sharedKeys.length);
    expect(ownKeys.toSet().intersection(sharedKeys.toSet()), isEmpty);
    expect(ownKeys.any((k) => k.startsWith('logging.')), isFalse);
    expect(sharedKeys, contains('logging.level'));
    for (final group in botSettingGroups) {
      if (kinds.containsKey(group)) {
        expect(
          find.text(settingGroupName(client, group)),
          findsWidgets,
          reason: group,
        );
      }
    }
    expect(find.byKey(const ValueKey('bot-secrets')), findsOneWidget);
    // Every Hermes setting this node offers, the Bot's own and the shared
    // ones, has a Chinese name and note.
    final missing = [
      for (final key in [...ownKeys, ...sharedKeys])
        if (!hermesSettingZh.containsKey(key)) key,
    ];
    note('settingsWithoutChinese', missing);
    expect(missing, isEmpty);
    await shot('bot-settings');
    await tap(find.byKey(const ValueKey('settings-group-tools')));
    // The capabilities page, once its settings have loaded.
    final toolsSearch = find.descendant(
      of: find.ancestor(
        of: find.descendant(
          of: find.byType(AppBar),
          matching: find.text(settingGroupName(client, 'tools')),
        ),
        matching: find.byType(AppPage),
      ),
      matching: find.byType(TextField),
    );
    await until(
      () => toolsSearch.evaluate().isNotEmpty,
      what: 'capabilities page',
    );
    await tester.enterText(toolsSearch, 'terminal.backend');
    await until(
      () => find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text(hermesSettingZh['terminal.backend']!.$1),
          )
          .evaluate()
          .isNotEmpty,
      what: 'terminal.backend in Chinese',
    );
    await shot('bot-settings-tools');
    await tester.pageBack();
    await settle(400);
    if (!android) {
      await tap(find.byTooltip('关闭'));
      await settle(400);
      expect(find.byType(BotDetails), findsNothing);
    } else {
      await tester.pageBack();
      await settle(400);
      await tester.pageBack();
      await settle(400);
    }

    // App settings: what every Bot shares.
    await tap(find.byTooltip('设置').first);
    await until(
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
      what: 'app settings',
    );
    await shot('settings');
    await tap(find.byKey(const ValueKey('settings-user-memory')));
    await until(
      () => find.byType(SharedUserMemoryPage).evaluate().isNotEmpty,
      what: 'about you',
    );
    await tester.pageBack();
    await settle(400);
    await tap(find.byKey(const ValueKey('settings-shared-hermes')));
    await until(
      () => find
          .byKey(const ValueKey('settings-group-general'))
          .evaluate()
          .isNotEmpty,
      what: 'shared settings',
    );
    await shot('shared-settings');

    if (!android) {
      // One shared change reaches the root profile and every Bot profile,
      // and a Bot made afterwards starts with it.
      final home = '$dataFolder/accounts/${local!.userId}/hermes';
      final field = objects(shared['fields'])
          .firstWhere((f) => f['key'] == 'display.compact');
      final before = field['value'] == true;
      final search = find.descendant(
        of: find.byType(HermesSettings),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'display.compact');
      await settle(500);
      final toggle = find.widgetWithText(
        SwitchListTile,
        hermesSettingZh['display.compact']!.$1,
      );
      await until(() => toggle.evaluate().isNotEmpty, what: 'shared field');
      await tap(toggle);
      await until(
        () => find.textContaining('Hermes profile').evaluate().isNotEmpty,
        what: 'applied notice',
      );
      await shot('shared-applied');
      Future<Map<String, bool?>> compact() async {
        final files = {
          'default': File('$home/config.yaml'),
          for (final bot in client.node.bots)
            '${bot['botId']}': File(
              '$home/profiles/${bot['botId']}/config.yaml',
            ),
        };
        return {
          for (final entry in files.entries)
            entry.key:
                RegExp(
                  r'^display:\r?\n(?:[ ].*\r?\n)*?  compact: (\w+)',
                  multiLine: true,
                ).firstMatch(await entry.value.readAsString())?.group(1) ==
                'true',
        };
      }

      final applied = await tester.runAsync(compact);
      note('compactAfterShared', applied);
      expect(applied!.values.every((v) => v == !before), isTrue);
      final source = objects((await client.rpc('providers.list'))['sources'])
          .firstWhere((s) => s['ready'] == true);
      final model = (await qa('/qa/model'))['model'] as String;
      final made = await client.rpc('bots.create', {
        'displayName': '记账',
        'role': '记账和对账',
        'model': model,
        'sourceId': source['sourceId'],
        'avatar': {'shape': 'mochi', 'color': '#D9932B'},
      });
      final madeId = '${object(made['bot'])['botId']}';
      await until(
        () => client.node.bots.any((b) => b['botId'] == madeId),
        what: 'new Bot synced',
      );
      final inherited = await tester.runAsync(compact);
      note('newBotInherits', inherited![madeId]);
      expect(inherited[madeId], !before);
      await client.rpc('hermes.shared.set', {
        'key': 'display.compact',
        'value': before,
      });
      final restored = await tester.runAsync(compact);
      note('compactRestored', restored);
      expect(restored!.values.every((v) => v == before), isTrue);
      // The Bot made for this check is not one of the user's.
      await client.rpc('bots.archive', {'botId': madeId});
      await expectLater(
        client.rpc('hermes.settings.set', {
          'botId': botId,
          'key': 'display.compact',
          'value': !before,
        }),
        throwsA(anything),
      );
    }
    await tester.pageBack();
    await settle(400);
    await tester.pageBack();
    await settle(400);

    // Dark: the same screens on a black ground.
    await client.preferences(appearance: 'dark');
    await settle(800);
    await shot('home-dark');
    if (!android) {
      await tap(dmRow);
      await tap(find.byTooltip('详情').first);
      await settle(600);
      await shot('details-dark');
      await tap(find.byTooltip('关闭'));
    }
    await client.preferences(appearance: 'system');
    expect(tester.takeException(), isNull);

    if (!android && hold) {
      // A new name each run, so an earlier marker never releases this one.
      final release = File(
        '$workFolder/hold-release-${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('QA holding for Android; create ${release.path} to finish');
      await until(
        () => release.existsSync(),
        seconds: 1800,
        what: 'hold released',
      );
    }
    note('done', true);
    if (!android && evidenceFolder.isNotEmpty) {
      await File('$evidenceFolder/ui-refresh-windows.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    debugPrint('QA REPORT ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
