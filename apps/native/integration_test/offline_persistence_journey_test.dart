import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/secrets.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real platform secure storage, with test-only keys separate from installed login.
class ColdJourneyVault extends FlutterSecureStorage {
  final real = const FlutterSecureStorage();
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => real.read(key: 'offline-cold-journey:$key');
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
  }) => real.write(key: 'offline-cold-journey:$key', value: value);
}

// Launch twice without reinstalling. Between phases, stop only this candidate
// process. The loopback proxy retains the fault while the application is closed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('process restart, partial upload and secret exclusion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: ColdJourneyVault());
    final capture = GlobalKey();
    const node = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final dir = await tester.runAsync(
      () async => Platform.isAndroid
          ? '${(await getExternalStorageDirectory())!.path}/offline-cold-evidence'
          : '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/cold',
    );
    final stateFile = File('$dir/${Platform.operatingSystem}-state.json');
    final existing = await tester.runAsync(
      () async => await stateFile.exists()
          ? object(jsonDecode(await stateFile.readAsString()))
          : <String, dynamic>{},
    );
    final state = existing!;
    final restoring = state['stage'] == 'prepared';
    final marker =
        state['marker'] as String? ??
        'COLD_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
    var stage = 'boot';
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<Json> fault(String mode) async => (await tester.runAsync(() async {
      final r = await http.get(
        Uri.parse(
          '${const String.fromEnvironment('RELAY_URL')}/__fault?mode=$mode',
        ),
      );
      expect(r.statusCode, 200);
      return object(jsonDecode(r.body));
    }))!;
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
        await Directory(dir!).create(recursive: true);
        await File('$dir/${Platform.operatingSystem}-$name.png')
            .writeAsBytes(bytes);
        image.dispose();
      });
    }

    Future<void> save() async {
      await tester.runAsync(() async {
        await stateFile.parent.create(recursive: true);
        await stateFile.writeAsString(jsonEncode(state), flush: true);
      });
    }

    if (!restoring) await fault('online');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    if (!restoring) {
      await until(
        () =>
            find.byType(HomePage).evaluate().isNotEmpty ||
            find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
      );
      if (find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty) {
        await tester.enterText(
          find.byKey(const ValueKey('auth-email')),
          const String.fromEnvironment('QA_EMAIL'),
        );
        await tester.enterText(
          find.byKey(const ValueKey('auth-password')),
          const String.fromEnvironment('QA_PASSWORD'),
        );
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
      }
      await until(() => c.connection.ready);
      await tester.runAsync(() => c.selectNode(node));
      await until(() => c.online);
      await tester.runAsync(() => c.loadMessages(dm));
    }
    await until(() => c.node.messages[dm]?.isNotEmpty == true);
    await until(() => find.byType(HomePage).evaluate().isNotEmpty);
    final input = find.byKey(const ValueKey('chat-input'));
    if (input.evaluate().isEmpty) {
      Navigator.of(tester.element(find.byType(HomePage))).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(client: c, conversationId: dm),
        ),
      );
    }
    await until(() => input.evaluate().isNotEmpty);
    Future<void> send(String words) async {
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(input, words);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byTooltip(c.tr('发送', 'Send')));
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    if (!restoring) {
      stage = 'second chunk acknowledged upstream, receipt interrupted';
      debugPrint('OFFLINE COLD: prepare chunk interruption');
      final path = '$dir/$marker.txt';
      await tester.runAsync(() async {
        await Directory(dir!).create(recursive: true);
        await File(path).writeAsString('UPLOAD_SAMPLE_LINE\n' * 32768);
        await tester
            .state<ChatComposerState>(find.byType(ChatComposer))
            .attachFile(path: path);
      });
      await fault('upload-cut');
      await send('附件只用于传输测试，不要读取内容。只回复 ${marker}_DONE，不调用工具。');
      await until(() => !c.connection.ready);
      await tester.enterText(input, '进程重启后仍保留_$marker');
      await tester.runAsync(() => c.flushContent());
      final item = c.deliveries.items.firstWhere(
        (i) => '${i['params']['text']}'.contains(marker),
      );
      final file = objects(item['files']).single;
      expect(file['offset'], 196608);
      state.addAll({
        'stage': 'prepared',
        'marker': marker,
        'firstPid': pid,
        'clientMsgId': item['id'],
        'importId': file['importId'],
        'offset': file['offset'],
        'originalFile': path,
        'messageIds': c.node.messages[dm]!.map((m) => m.messageId).toList(),
      });
      await shot('prepared-offline');
      await save();
      debugPrint('OFFLINE COLD: PREPARED; restart this candidate only');
      binding.reportData = {'stage': 'prepared', 'pid': pid};
      return;
    }
    stage = 'restored while offline';
    expect(pid, isNot(state['firstPid']));
    expect(c.connection.ready, isFalse);
    expect(
      tester.widget<TextField>(input).controller!.text,
      '进程重启后仍保留_$marker',
    );
    expect(
      (state['messageIds'] as List).every(
        (id) => c.node.messages[dm]!.any((m) => m.messageId == id),
      ),
      isTrue,
    );
    expect(
      c.deliveries.items.any((i) => i['id'] == state['clientMsgId']),
      isTrue,
    );
    await shot('cold-offline');
    await fault('online');
    await tester.runAsync(() => c.connection.connect());
    stage = 'resume same upload and deliver once';
    await until(
      () => c.node.messages[dm]!.any(
        (m) =>
            m.author.type == 'bot' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains('${marker}_DONE'),
      ),
      seconds: 360,
    );
    final sent = c.node.messages[dm]!.where(
      (m) => m.clientMsgId == state['clientMsgId'],
    );
    expect(sent.length, 1);
    final data = await tester.runAsync(
      () => downloadFile(
        c,
        (sent.single.content['files'] as List).single as String,
      ),
    );
    final original = await tester.runAsync(
      () => File(state['originalFile'] as String).readAsBytes(),
    );
    expect(data, original);
    final uploads = objects((await fault('status'))['uploads']);
    expect(uploads.map((u) => u['importId']).toSet(), {state['importId']});
    expect(uploads.take(3).map((u) => u['offset']).toList(), [
      0,
      196608,
      196608,
    ]);
    state.addAll({
      'secondPid': pid,
      'coldProcessRestore': true,
      'sameImportResumedAtOffset': true,
      'singleMessage': true,
      'uploadBytes': data!.length,
      'uploads': uploads,
    });
    await shot('upload-recovered');
    await save();

    stage = 'real secret request';
    debugPrint('OFFLINE COLD: actual secret card');
    final spec = {
      'service': marker,
      'purpose': 'Offline card exclusion test',
      'fields': [
        {'name': 'QA_VALUE', 'label': 'QA', 'kind': 'password'},
      ],
      'target': {
        'kind': 'file',
        'path': '${const String.fromEnvironment('QA_WORK_DIR')}/$marker.env',
        'format': 'env',
      },
    };
    await send(
      "Read nekodot-secrets skill and use terminal to run hermes secret request --spec '${jsonEncode(spec)}'. Create the card then finish your turn. Do not ask for values in chat. This test will cancel without delivery.",
    );
    await until(
      () => c.node.messages[dm]!.any(
        (m) => m.kind == 'secret' && m.content['service'] == marker,
      ),
      seconds: 360,
    );
    final request = c.node.messages[dm]!.firstWhere(
      (m) => m.kind == 'secret' && m.content['service'] == marker,
    );
    final card = find.byWidgetPredicate(
      (w) =>
          w is SecretCard &&
          w.content['requestId'] == request.content['requestId'],
    );
    await until(() => card.evaluate().isNotEmpty);
    final field = find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('secret-field-QA_VALUE')),
    );
    await until(() => field.evaluate().isNotEmpty);
    await tester.ensureVisible(field);
    await tester.pump(const Duration(milliseconds: 300));
    final sentinel =
        'PRIVATE_OFFLINE_SENTINEL_${DateTime.now().microsecondsSinceEpoch}';
    await tester.enterText(field, sentinel);
    await fault('offline');
    await until(() => !c.online);
    final submit = find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('secret-submit')),
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.runAsync(() => c.flushContent());
    expect(jsonEncode(c.deliveries.items).contains(sentinel), isFalse);
    expect(jsonEncode(c.drafts).contains(sentinel), isFalse);
    await tester.runAsync(() async {
      await for (final f in c.store!.directory.list(recursive: true)) {
        if (f is File && f.path.endsWith('.json')) {
          expect(
            (await f.readAsString()).contains(sentinel),
            isFalse,
            reason: 'Secret must not enter local content',
          );
        }
      }
    });
    final controller = tester.widget<TextField>(field).controller!;
    final nav = Navigator.of(tester.element(card));
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox())),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.text, isEmpty);
    nav.pop();
    await tester.pump(const Duration(milliseconds: 400));
    await fault('online');
    await tester.runAsync(() => c.connection.connect());
    await until(() => c.online);
    await tester.runAsync(
      () => c.rpc('secrets.cancel', {
        'botId': request.content['botId'],
        'requestId': request.content['requestId'],
      }),
    );
    state['secretExcludedFromDiskDraftAndQueue'] = true;
    state['secretClearedOnLeavingCard'] = true;
    for (final appearance in ['light', 'dark']) {
      for (final locale in ['zh', 'en']) {
        await tester.runAsync(
          () => c.prefs.update(locale: locale, appearance: appearance),
        );
        await fault('offline');
        await until(() => !c.online);
        await shot('$appearance-$locale-offline');
        expect(tester.takeException(), isNull);
        await fault('online');
        await tester.runAsync(() => c.connection.connect());
        await until(() => c.online);
      }
    }
    state['stage'] = 'completed';
    await save();
    binding.reportData = state;
    debugPrint('OFFLINE COLD: COMPLETED');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
