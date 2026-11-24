import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/data/spaces.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/spaces.dart';
import 'package:nekodot_native/features/space_webview.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real isolated services, actual model and the platform's embedded browser.
// This test never publishes a fixture in place of the Dot's generated package.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Space creation, native webview, records and cached reopening', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    SharedPreferences.setMockInitialValues({});
    final vault = MemoryVault();
    var c = NekodotClient(vault: vault);
    final phone = Platform.isAndroid;
    const conversation = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    addTearDown(() => c.dispose());
    Future<void> frames([int ms = 400]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready, String label) async {
      final end = DateTime.now().add(const Duration(minutes: 12));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(180);
      }
      expect(ready(), isTrue, reason: label);
      debugPrint('SPACE verified $label');
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target.hitTestable().first);
      await tester.tap(target.hitTestable().first);
      await frames();
      expect(tester.takeException(), isNull);
    }

    Future<void> control(String path) async {
      final response = await http.post(
        Uri.parse(const String.fromEnvironment('QA_CONTROL') + path),
      );
      expect(response.statusCode, 200, reason: 'QA control $path');
    }

    Future<void> shot(String label) async {
      await frames(700);
      if (phone) {
        // Android's hybrid WebView is not part of Flutter's Surface image.
        // Capture the actual fixed emulator display through the QA host.
        await control('/screenshot?name=space-android-$label');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/space-windows-$label.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Space QA');
      await windowManager.show();
      await windowManager.setSize(const Size(1200, 850));
    }
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => c.online && c.node.bots.isNotEmpty,
      'real Node connected',
    );
    Future<void> mount() => tester.pumpWidget(
      ListenableBuilder(
        listenable: c.prefs,
        builder: (_, _) => MaterialApp(
          navigatorObservers: [nativeRoutes],
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (_, child) =>
              phone ? Ambient(child: child!) : WindowChrome(child: child!),
          home: HomePage(client: c),
        ),
      ),
    );
    await mount();
    await frames(1000);
    if (phone &&
        find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await frames();
    }
    bool isStudy(Space s) => s.name == 'Space Study QA' && s.version > 0;
    if (find.byType(SpacePage).evaluate().isNotEmpty &&
        tester.widget<SpacePage>(find.byType(SpacePage)).spaceId !=
            c.node.spaces.values.firstWhere(isStudy).spaceId) {
      await tap(find.byTooltip('返回'));
    }
    if (!c.node.spaces.values.any(isStudy)) {
      await tap(find.byKey(const ValueKey('conversation-$conversation')));
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '创建一个名为 Space Study QA 的空间，做成可用的小型英语单词复习游戏。'
        '必须使用 nekodot-spaces skill 和真实 nekodot_space prepare/publish 工具，发布后由主 Dot 简短交付。'
        '包含三个简单词汇，点击“答对了”会记下一次练习，点击“重开”重新显示第一题但保留历史。'
        '用 window.nekodotSpace 保存每次练习到独立记录 ID，加载时读取历史次数；不用 localStorage。'
        'HTML/CSS/JS 与 data.json 都在空间目录中，页面用相对 fetch 读取 data.json。'
        '适配手机和桌面，布局清爽，不要远程 CDN，不用提问。'
        '在发布 origins 中声明 https://example.com 用于后续授权测试，但核心功能不得依赖联网。',
      );
      await frames(250);
      await tap(find.byTooltip(c.tr('发送', 'Send')));
      await until(
        () => c.node.spaces.values.any((s) => s.version > 0),
        'model published actual HTML',
      );
      await until(
        () => (c.node.messages[conversation] ?? []).any(
          (m) =>
              m.author.type == 'bot' &&
              m.taskRole != 'execution' &&
              (m.content['spaces'] as List? ?? []).isNotEmpty,
        ),
        'main Dot delivered structured Space card',
      );
      await shot('chat-delivery');
      await tap(find.byType(SpaceCard).last);
    } else if (find.byType(SpacePage).evaluate().isEmpty) {
      await until(
        () => find.text('空间').hitTestable().evaluate().isNotEmpty,
        'category switch available after restoring the previous route',
      );
      await tap(find.text('空间').first);
      await tap(find.text(c.node.spaces.values.firstWhere(isStudy).name).first);
    }
    await until(
      () => find.byType(SpaceWebView).evaluate().isNotEmpty,
      'platform webview opened',
    );
    await frames(5000);
    InAppWebViewController currentView() {
      final dynamic state = tester.state(find.byType(SpaceWebView));
      return state.controller as InAppWebViewController;
    }

    var view = currentView();
    final ready = await view.callAsyncJavaScript(
      functionBody: 'await window.nekodotSpace.ready; return {title: document.title, text: document.body.innerText, sdk: !!window.nekodotSpace};',
    );
    debugPrint('SPACE rendered ${ready?.value}');
    expect(ready?.error, isNull);
    expect(ready?.value['sdk'], isTrue);
    await shot('game');
    final before = object(
      (await view.callAsyncJavaScript(
        functionBody: 'return await window.nekodotSpace.list();',
      ))!.value,
    );
    final click = await view.callAsyncJavaScript(
      functionBody: "const button = [...document.querySelectorAll('button')].find(x=>x.textContent.includes('答对了')); if(!button) throw new Error('Game action missing'); button.click(); return true;",
    );
    expect(click?.error, isNull);
    await frames(1500);
    final after = object(
      (await view.callAsyncJavaScript(
        functionBody: 'return await window.nekodotSpace.list();',
      ))!.value,
    );
    expect(after.keys.length, greaterThan(before.keys.length));
    final space = c.node.spaces.values.firstWhere(isStudy);
    await until(
      () => c.spaces.data(c.selectedNodeId!, space.spaceId).pending.isEmpty,
      'records synchronized with Node',
    );
    final cached = c.store!.file('files/${c.selectedNodeId}/${space.fileId}');
    debugPrint(
      'SPACE cache package bytes=${await cached.length()} resources=${(tester.widget<SpaceWebView>(find.byType(SpaceWebView))).bundle.files.length}',
    );
    final remote = await c.rpc('spaces.data.read', {'spaceId': space.spaceId});
    expect(objects(remote['records']).length, after.length);
    final denied = await view.callAsyncJavaScript(
      functionBody: "try { await fetch('https://example.com/'); return false; } catch(e) { return true; }",
    );
    expect(denied?.value, isTrue);
    final fileDenied = await view.callAsyncJavaScript(
      functionBody: "try { await fetch('file:///C:/Windows/win.ini'); return false; } catch(e) { return true; }",
    );
    expect(fileDenied?.value, isTrue);
    final hostDenied = await view.callAsyncJavaScript(
      functionBody: "return await window.flutter_inappwebview.callHandler('spaceData', {operation:'rpc', method:'secrets.list'});",
    );
    expect(hostDenied?.value['error'], isNotNull);
    await shot('saved');
    if (const bool.fromEnvironment('QA_SPACE_BACKGROUND')) {
      await view.evaluateJavascript(
        source:
            'window.spaceTicks=0; window.spaceEvents=0; window.spaceTimes=[]; window.spaceVisibility=[]; '
            'window.spaceClock=setInterval(()=>{window.spaceTicks++; window.spaceTimes.push(Date.now());},100); '
            'document.addEventListener("visibilitychange",()=>window.spaceVisibility.push({state:document.visibilityState,at:Date.now()})); '
            'window.addEventListener("nekodotspacechange",()=>window.spaceEvents++);',
      );
      await frames(700);
      final ticks = await view.evaluateJavascript(source: 'window.spaceTicks');
      await tap(find.byTooltip('更多'));
      await c.rpc('spaces.data.write', {
        'spaceId': space.spaceId,
        'mutationId': uid(),
        'records': [
          {'key': 'while-covered', 'value': uid()},
        ],
      });
      await frames(2500);
      await tester.binding.handlePopRoute();
      await frames(500);
      final resumed = await view.evaluateJavascript(
        source: '({ticks:window.spaceTicks, events:window.spaceEvents})',
      );
      debugPrint('SPACE covered timer before=$ticks after=$resumed');
      expect(
        resumed['ticks'] - ticks,
        lessThan(15),
        reason: 'Covered page pauses JavaScript timers',
      );
      expect(
        resumed['events'],
        greaterThan(0),
        reason: 'Returning page receives records synchronized while hidden',
      );
      if (const bool.fromEnvironment('QA_SPACE_OS_BACKGROUND')) {
        await view.evaluateJavascript(
          source: 'window.spaceTimes=[]; window.spaceVisibility=[];',
        );
        final beforeBackground = await view.evaluateJavascript(
          source: 'window.spaceTicks',
        );
        if (phone) {
          // The external QA driver sends actual Android Home / resume actions.
          debugPrint('SPACE OS background probe ready');
          await Future<void>.delayed(const Duration(seconds: 8));
        } else {
          await windowManager.minimize();
          await Future<void>.delayed(const Duration(seconds: 3));
          await windowManager.show();
          await windowManager.focus();
        }
        await frames(500);
        final afterBackground = await view.evaluateJavascript(
          source: 'window.spaceTicks',
        );
        debugPrint(
          'SPACE background timer $beforeBackground -> $afterBackground',
        );
        final background = await view.evaluateJavascript(
          source:
              '({visibility:window.spaceVisibility,'
              'gap:Math.max(0,...window.spaceTimes.slice(1).map((t,i)=>t-window.spaceTimes[i]))})',
        );
        debugPrint('SPACE background observation $background');
        expect(
          (background['visibility'] as List).any((v) => v['state'] == 'hidden'),
          isTrue,
        );
        expect(
          background['gap'],
          greaterThan(1000),
          reason: 'Actual hidden interval suspends the 100ms page timer',
        );
      }
      await view.evaluateJavascript(source: 'clearInterval(window.spaceClock)');
      await shot('resumed');
    }
    if (!phone) {
      await tap(find.byTooltip('展开'));
      expect(
        identical(view, currentView()),
        isTrue,
        reason: 'Expansion retains the running page',
      );
      await shot('expanded');
      await tap(find.byTooltip('展开'));
      debugPrint(
        'SPACE after collapse ${await view.evaluateJavascript(source: '({visibility:document.visibilityState,width:innerWidth,height:innerHeight})')}',
      );
    }
    final pendingKey = 'offline-${phone ? 'android' : 'windows'}-${uid()}';
    if (const bool.fromEnvironment('QA_SPACE_LIFECYCLE', defaultValue: true)) {
      // Stop the actual QA Node and Hermes, not a stubbed online flag.
      await control('/node/stop');
      await until(() => !c.node.online, 'Node offline');
      final offlineWrite = await view.callAsyncJavaScript(
        functionBody:
            'await window.nekodotSpace.set(key, {offline:true}); return true;',
        arguments: {'key': pendingKey},
      );
      expect(offlineWrite?.error, isNull);
      expect(
        c.spaces.data(c.selectedNodeId!, space.spaceId).pending,
        isNotEmpty,
      );
      await shot('offline-saved');
      await tap(find.byTooltip('返回'));
      expect(find.byType(SpaceWebView), findsNothing);
      // Reopen from the real cached bundle while the owner is still shut down.
      if (!phone) await tap(find.text('空间').first);
      await tap(find.text(space.name).first);
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'cached page reopened offline',
      );
      await frames(2500);
      view = currentView();
      expect(
        (await view.callAsyncJavaScript(
          functionBody: 'return await window.nekodotSpace.get(key);',
          arguments: {'key': pendingKey},
        ))?.value['offline'],
        isTrue,
      );
      // Reconstruct client state from disk, preserving the same account vault.
      await tester.pumpWidget(const SizedBox.shrink());
      await frames();
      await c.flushContent();
      await c.connection.disconnect();
      c.dispose();
      c = NekodotClient(vault: vault);
      await c.prefs.update(locale: 'zh', appearance: 'light');
      await c.initialize();
      await mount();
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'client restart restored cached space',
      );
      await frames(2500);
      view = currentView();
      expect(
        (await view.callAsyncJavaScript(
          functionBody: 'return await window.nekodotSpace.get(key);',
          arguments: {'key': pendingKey},
        ))?.value['offline'],
        isTrue,
      );
      await control('/node/start');
      await until(() => c.online, 'Node restarted');
      await until(
        () => c.spaces.data(c.selectedNodeId!, space.spaceId).pending.isEmpty,
        'offline record synced after both restarts',
      );
      final restored = await c.rpc('spaces.data.read', {
        'spaceId': space.spaceId,
      });
      expect(
        objects(restored['records']).any((r) => r['key'] == pendingKey),
        isTrue,
      );
      // Actual transport duplicate delivery and per-record merging.
      final mutation = {
        'spaceId': space.spaceId,
        'mutationId': uid(),
        'records': [
          {
            'key': 'shared-setting',
            'value': {'device': phone ? 'android' : 'windows'},
          },
        ],
      };
      final once = await c.rpc('spaces.data.write', mutation);
      final twice = await c.rpc('spaces.data.write', mutation);
      expect(twice['revision'], once['revision']);
      expect(
        objects(twice['records']).any((r) => r['key'] == pendingKey),
        isTrue,
      );
    }
    if (const bool.fromEnvironment('QA_SPACE_UPDATE')) {
      final version = c.node.spaces[space.spaceId]!.version;
      await c.rpc('messages.send', {
        'conversationId': conversation,
        'spaceId': space.spaceId,
        'clientMsgId': uid(),
        'text':
            '更新这个现有空间：保留游戏与全部历史记录，增加一行可见的 SPACE-UPDATE 验收标记；'
            '监听 nekodotspacechange 重新读取练习次数，不重载页面。'
            '修正页面的 prefers-color-scheme 深色适配。'
            '在 origins 中保留 https://example.com，增加 https://raw.githubusercontent.com；'
            '页面不要自动请求它，只声明供我通过原生设置授权测试。'
            '按正常主 Dot 委派流程让执行任务使用真实 nekodot_space get/publish 更新相同空间，不要找客户端调试接口，不要 mock SDK，不创建定时任务。'
            '发布后直接简短完成汇报。',
      });
      await until(
        () => c.node.spaces[space.spaceId]!.version > version,
        'real Dot published an update',
      );
      expect(identical(view, currentView()), isTrue);
      expect(
        await view.evaluateJavascript(
          source: "document.body.innerText.includes('SPACE-UPDATE')",
        ),
        isFalse,
      );
      await shot('update-pending');
      await tap(find.byTooltip('刷新'));
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'updated page opened',
      );
      await frames(3000);
      view = currentView();
      expect(
        await view.evaluateJavascript(
          source: "document.body.innerText.includes('SPACE-UPDATE')",
        ),
        isTrue,
      );
      if (const bool.fromEnvironment(
        'QA_SPACE_LIFECYCLE',
        defaultValue: true,
      )) {
        expect(
          (await view.callAsyncJavaScript(
            functionBody: 'return await window.nekodotSpace.get(key);',
            arguments: {'key': pendingKey},
          ))?.value['offline'],
          isTrue,
        );
      }
    }
    if (const bool.fromEnvironment('QA_SPACE_ACCESS')) {
      const website = 'https://raw.githubusercontent.com';
      const fetchWebsite =
          "try { const r = await fetch('https://raw.githubusercontent.com/AR307/nekodot/main/package.json'); return r.status; } catch(e) { return 0; }";
      expect(
        (await view.callAsyncJavaScript(functionBody: fetchWebsite))?.value,
        0,
      );
      Future<void> toggleWebsite() async {
        await tap(find.byTooltip('更多'));
        await tap(find.text('网站访问'));
        await tap(find.text(website));
        await shot('website-access');
        await tap(find.text('保存'));
        await until(
          () => find.byType(SpaceWebView).evaluate().isNotEmpty,
          'website permission applied',
        );
        await frames(2500);
        view = currentView();
      }

      await toggleWebsite();
      expect(
        (await view.callAsyncJavaScript(functionBody: fetchWebsite))?.value,
        200,
      );
      await toggleWebsite();
      expect(
        (await view.callAsyncJavaScript(functionBody: fetchWebsite))?.value,
        0,
      );
      debugPrint('SPACE verified allowed HTTPS/CORS access and revocation');
    }
    if (const bool.fromEnvironment('QA_SPACE_MANAGEMENT')) {
      await tap(find.byTooltip('更多'));
      await tap(find.text('重命名'));
      await tester.enterText(
        find.byType(TextFormField),
        'Space Study QA renamed',
      );
      await tap(find.text('保存'));
      await until(
        () => c.node.spaces[space.spaceId]?.name == 'Space Study QA renamed',
        'native rename saved',
      );
      expect(identical(view, currentView()), isTrue);
      await shot('renamed');
      await tap(find.byTooltip('更多'));
      await tap(find.text('重命名'));
      await tester.enterText(find.byType(TextFormField), space.name);
      await tap(find.text('保存'));
      await tap(find.byTooltip('更多'));
      await tap(find.text('请 Dot 修改'));
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        'edit returned to owning Dot',
      );
      expect(
        c.spaceDrafts['${c.selectedNodeId}:$conversation']?['spaceId'],
        space.spaceId,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'SPACE-DRAFT-PRESERVE',
      );
      await frames();
      await shot('edit-reference');
      if (phone) {
        await tester.binding.handlePopRoute();
        await frames();
      }
      await tap(find.text('群聊').first);
      expect(find.text('QA Team'), findsOneWidget);
      expect(find.byKey(ValueKey('conversation-$conversation')), findsNothing);
      await tap(find.text('空间').first);
      await tap(find.text(space.name).first);
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'space reopened after category switch',
      );
      await frames(2000);
      view = currentView();
      await tap(find.byTooltip('更多'));
      await tap(find.text('归档'));
      await tap(find.widgetWithText(TextButton, '归档'));
      await until(
        () => c.node.spaces[space.spaceId]?.archived == true,
        'native archive saved',
      );
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        'archive returned to chat',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        'SPACE-DRAFT-PRESERVE',
      );
      await tester.enterText(find.byKey(const ValueKey('chat-input')), '');
      if (phone) {
        await tester.binding.handlePopRoute();
        await frames();
      }
      await tap(find.text('空间').first);
      expect(find.text(space.name), findsNothing);
      // Restore the test publication without deleting records or repeating model work.
      await c.rpc('spaces.update', {
        'spaceId': space.spaceId,
        'archived': false,
      });
      await until(
        () => c.node.spaces[space.spaceId]?.archived == false,
        'test space restored',
      );
      await tap(find.byTooltip('新建空间'));
      await tap(find.byType(DropdownButtonFormField<String>));
      await tap(find.text('QA Lead').last);
      await tester.enterText(
        find.byType(TextField),
        List.filled(12, '请创建用于复习的单词空间。').join('\n'),
      );
      if (phone) {
        tester.testTextInput.unregister();
        FocusManager.instance.primaryFocus?.unfocus();
        await frames();
        await tap(find.byType(TextField));
        await frames(1000);
        expect(
          tester.view.viewInsets.bottom,
          greaterThan(0),
          reason: 'real Android keyboard',
        );
      }
      await shot('create-form');
      if (phone) {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await frames();
        tester.testTextInput.register();
      }
      await tester.binding.handlePopRoute();
      await frames();
      debugPrint(
        'SPACE verified categories, editing, draft, rename, archive and creation form',
      );
    }
    if (const bool.fromEnvironment('QA_SPACE_CREATE')) {
      if (find.byType(SpacePage).evaluate().isNotEmpty) {
        await tap(find.byTooltip('返回'));
      }
      await tap(find.text('空间').first);
      if (!c.node.spaces.values.any(
        (s) => s.name == 'Space Offline QA' && s.version > 0,
      )) {
        await tap(find.byTooltip('新建空间'));
        await tap(find.byType(DropdownButtonFormField<String>));
        await tap(find.text('QA Lead').last);
        await tester.enterText(
          find.byType(TextField),
          '做一个简单的计数器，名字叫 Space Offline QA，按一下加一，下次打开可以继续。',
        );
        await frames();
        await shot('create-compact');
        await tap(find.widgetWithText(FilledButton, '发送'));
        expect(find.byType(CreateSpacePage), findsNothing);
        await until(
          () => c.node.spaces.values.any(
            (s) => s.name == 'Space Offline QA' && s.version > 0,
          ),
          'creation form submitted a real model task',
        );
        await until(
          () => c.node.tasks.values
              .where((t) => t.conversationId == conversation)
              .every((t) => !t.active && t.reportMessageId != null),
          'creation task finished',
        );
      }
      if (phone) {
        await tester.binding.handlePopRoute();
        await frames();
      }
      await tap(find.text('空间').first);
      await control('/node/stop');
      await until(() => !c.node.online, 'owner offline for uncached open');
      await tap(find.text('Space Offline QA').first);
      await until(
        () => find.text('尚未下载').evaluate().isNotEmpty,
        'uncached space requires its Node',
      );
      expect(find.byType(SpaceWebView), findsNothing);
      await shot('not-downloaded');
      await control('/node/start');
      await until(() => c.online, 'owner reconnected');
      await tap(find.byTooltip('刷新'));
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'first download after Node reconnect',
      );
      await frames(2500);
      await shot('first-download');
    }
    if (const bool.fromEnvironment('QA_SPACE_REPORT')) {
      if (find.byType(SpacePage).evaluate().isNotEmpty) {
        await tap(find.byTooltip('返回'));
      }
      if (find.text('空间').hitTestable().evaluate().isNotEmpty) {
        await tap(find.text('空间').first);
      }
      await until(
        () => c.node.spaces.values.any(
          (s) => s.name == 'Space Daily QA' && s.version > 1,
        ),
        'native Cron published report update',
      );
      await tap(find.text('Space Daily QA').first);
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'report webview opened',
      );
      await frames(3000);
      view = currentView();
      final report = await view.callAsyncJavaScript(
        functionBody: 'await window.nekodotSpace.ready; return {orders:document.getElementById("orders").textContent,revenue:document.getElementById("revenue").textContent,note:await window.nekodotSpace.get("daily-note")};',
      );
      expect(report?.value['orders'], '15');
      expect(report?.value['revenue'], '633.25');
      expect(report?.value['note']['text'], contains('SPACE-NOTE'));
      await view.callAsyncJavaScript(
        functionBody:
            'const input=document.getElementById("daily-note"); input.value="SPACE-NOTE-${phone ? 'ANDROID' : 'WINDOWS'}"; input.dispatchEvent(new Event("input")); document.getElementById("save-note").click(); return true;',
      );
      await frames(1500);
      final reportSpace = c.node.spaces.values.firstWhere(
        (s) => s.name == 'Space Daily QA',
      );
      await until(() {
        final data = c.spaces.data(c.selectedNodeId!, reportSpace.spaceId);
        return data.records['daily-note']?['text'] ==
                'SPACE-NOTE-${phone ? 'ANDROID' : 'WINDOWS'}' &&
            data.pending.isEmpty;
      }, 'report note synchronized');
      final reportRecords = await c.rpc('spaces.data.read', {
        'spaceId': reportSpace.spaceId,
      });
      expect(
        objects(reportRecords['records'])
            .firstWhere((r) => r['key'] == 'daily-note')['value']['text'],
        'SPACE-NOTE-${phone ? 'ANDROID' : 'WINDOWS'}',
      );
      // A page cannot switch its bridge to another space by supplying an ID.
      final isolated = await view.callAsyncJavaScript(
        functionBody:
            'return await window.flutter_inappwebview.callHandler("spaceData", {operation:"get", key:"shared-setting", spaceId:"${space.spaceId}"});',
      );
      expect(isolated?.value['value'], isNull);
      await shot('cron-report');
      debugPrint(
        'SPACE verified actual Cron values, retained note and cross-space bridge isolation',
      );
    }
    if (const bool.fromEnvironment('QA_SPACE_LEARNING')) {
      // This page came from the separate natural conversation, not a seeded
      // publication or a tool-directed prompt. Its observed controls are used
      // here to verify Windows -> Android continuation of a real learner's draft.
      const guideConversation = String.fromEnvironment(
        'QA_PROACTIVE_CONVERSATION',
      );
      await until(
        () => c.node.spaces.values.any(
          (s) => s.conversationId == guideConversation && s.version > 0,
        ),
        'naturally proposed learning page published',
      );
      final guide = c.node.spaces.values.firstWhere(
        (s) => s.conversationId == guideConversation && s.version > 0,
      );
      await until(
        () => c.node.tasks.values
            .where((t) => t.conversationId == guideConversation)
            .every((t) => !t.active && t.reportMessageId != null),
        'learning task completed and reported',
      );
      if (find.byType(SpacePage).evaluate().isNotEmpty) {
        await tap(find.byTooltip('返回'));
      }
      c.openNotification({
        'nodeId': c.selectedNodeId!,
        'conversationId': guideConversation,
      });
      final card = find.byWidgetPredicate(
        (w) => w is SpaceCard && w.spaceId == guide.spaceId,
      );
      await until(
        () => card.evaluate().isNotEmpty,
        'main Dot delivered the learning page in chat',
      );
      await shot('learning-delivery');
      if (const bool.fromEnvironment('QA_SPACE_UNCACHED')) {
        expect(
          await c.store!.read(
            'spaces/open/${c.selectedNodeId}/${guide.spaceId}',
          ),
          isNull,
          reason: 'Never-opened page, not cleared test data',
        );
        expect(c.node.tasks.values.any((t) => t.active), isFalse);
        await control('/node/stop');
        await until(
          () => !c.node.online,
          'Node shut down before first download',
        );
        await tap(card.last);
        await until(
          () => find.text('尚未下载').evaluate().isNotEmpty,
          'uncached learning page waits for its Node',
        );
        expect(find.byType(SpaceWebView), findsNothing);
        await shot('not-downloaded');
        await control('/node/start');
        await until(() => c.online, 'same Node reconnected');
        await tap(find.byTooltip('刷新'));
      } else {
        await tap(card.last);
      }
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'real learning page opened',
      );
      await frames(3000);
      view = currentView();
      final learning = await view.callAsyncJavaScript(
        functionBody:
            'await window.nekodotSpace.ready; '
            'return {text:document.body.innerText, records:await window.nekodotSpace.list()};',
      );
      expect(learning?.error, isNull);
      expect(learning?.value['text'], contains('5个'));
      await shot('learning-home');
      Future<void> clickLearning(String selector) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          final available = await view.callAsyncJavaScript(
            functionBody: 'const e=document.querySelector(selector); return !!e && !e.disabled;',
            arguments: {'selector': selector},
          );
          if (available?.value == true) break;
          await frames(180);
        }
        final result = await view.callAsyncJavaScript(
          functionBody:
              'const e=document.querySelector(selector); '
              'if(!e || e.disabled) throw new Error("Learning action unavailable: "+selector); '
              'e.click(); return true;',
          arguments: {'selector': selector},
        );
        expect(result?.error, isNull);
        await frames(600);
      }

      await clickLearning('[data-action="continue"]');
      if (!phone) {
        await clickLearning('[data-action="to-recognition"]');
        await clickLearning('[data-action="recognition"][data-answer=""]');
        await clickLearning('[data-action="feedback-next"]');
        await view.callAsyncJavaScript(
          functionBody:
              'const input=document.getElementById("answer"); '
              'input.value="appl"; input.dispatchEvent(new Event("input",{bubbles:true})); return true;',
        );
        await frames(1000);
        await until(
          () => c.spaces
              .data(c.selectedNodeId!, guide.spaceId)
              .records
              .values
              .any((v) => v is Map && v['draft'] == 'appl'),
          'learner spelling draft saved',
        );
        await shot('learning-draft');
      } else {
        // Continue the saved attempt if a previous inspection stopped midway;
        // never reset the learner's record or replay completed answers.
        final saved = object(
          (await view.callAsyncJavaScript(
            functionBody: 'return await window.nekodotSpace.list();',
          ))!.value,
        );
        final attempt = saved.values.whereType<Map>().firstWhere(
          (v) => v['kind'] == 'attempt' && v['complete'] != true,
        );
        var step = attempt['step'];
        if (step == 'recall') {
          expect(
            await view.evaluateJavascript(
              source: 'document.getElementById("answer").value',
            ),
            'appl',
            reason: 'Actual Windows draft resumed on Android',
          );
          await shot('learning-cross-device');
          await clickLearning('#answerForm button[type="submit"]');
          step = 'recallFeedback';
        }
        if (step == 'recallFeedback') {
          await clickLearning('[data-action="feedback-next"]');
          step = 'use';
        }
        if (step == 'use') {
          await clickLearning('[data-action="skip-answer"]');
          step = 'useFeedback';
        }
        if (step == 'useFeedback') {
          await clickLearning('[data-action="feedback-next"]');
          step = 'self';
        }
        expect(step, 'self');
        await clickLearning('#selfForm button[type="submit"]');
        await until(
          () => c.spaces
              .data(c.selectedNodeId!, guide.spaceId)
              .records
              .values
              .any((v) => v is Map && v['complete'] == true),
          'mobile learning result saved',
        );
        await clickLearning('[data-tab="weak"]');
        expect(
          await view.evaluateJavascript(
            source: 'document.querySelectorAll(".word-row").length',
          ),
          greaterThan(0),
        );
        await shot('learning-weak-words');
      }
      await until(
        () => c.spaces.data(c.selectedNodeId!, guide.spaceId).pending.isEmpty,
        'learning records synchronized',
      );
      final learningRecords = await c.rpc('spaces.data.read', {
        'spaceId': guide.spaceId,
      });
      expect(
        objects(learningRecords['records']).any((r) {
          final value = r['value'];
          return value is Map &&
              (phone ? value['complete'] == true : value['draft'] == 'appl');
        }),
        isTrue,
      );
      debugPrint(
        'SPACE verified natural proposal, consent, delivery and ${phone ? 'Android continuation' : 'Windows draft'}',
      );
    }
    await c.prefs.update(locale: 'en', appearance: 'dark');
    await frames();
    await shot('dark-english');
    if (const String.fromEnvironment('QA_PROACTIVE_CONVERSATION').isNotEmpty) {
      await c.prefs.update(locale: 'zh', appearance: 'light');
      c.openNotification({
        'nodeId': c.selectedNodeId!,
        'conversationId': const String.fromEnvironment(
          'QA_PROACTIVE_CONVERSATION',
        ),
      });
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        'natural learning conversation opened',
      );
      await shot('proactive-proposal');
    }
    debugPrint(
      'SPACE COMPLETE native=${phone ? 'android' : 'windows'} version=${c.node.spaces[space.spaceId]!.version} records=${c.spaces.data(c.selectedNodeId!, space.spaceId).records.length}',
    );
    if (const bool.fromEnvironment('QA_INSPECT')) await frames(90000);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(800);
    expect(tester.takeException(), isNull);
  });
}
