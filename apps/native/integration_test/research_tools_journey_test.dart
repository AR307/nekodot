import 'package:nekodot_native/data/chat_models.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'four real model Bots create a grounded research proposal through native UI',
    (tester) async {
      if (Platform.isWindows) await DesktopHost.initialize();
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final c = NekodotClient();
      var createdBots = 0;
      var createdGroup = false;
      var sentPrompt = false;
      final roster = [
        [
          '工具统筹',
          'tool_lead',
          '你是大模型论文项目负责人。收敛真实可实施的问题，整合队友意见。不得虚构文献、实验结果或创新性；明确待验假设。',
        ],
        [
          '自主检索',
          'tool_lit',
          '你是大模型文献审查员。自主检索并核对原始文献与方法的对应关系，指出已有工作重叠，不把未知结论当作事实。',
        ],
        [
          '原型实验',
          'tool_method',
          '你是大模型算法研究员。给出无需训练大模型的最小算法、输入输出、预算和可复现实验设计。区分假设与证明。',
        ],
        [
          '复现审稿',
          'tool_critic',
          '你是严谨的实验与复现审稿人。检查数据泄漏、检索基线、校准集合、成本公平性与失败判据；不编造结果。',
        ],
      ];
      Future<void> until(
        bool Function() ready, {
        int seconds = 180,
        String label = 'native UI',
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
        }
        expect(ready(), isTrue, reason: '$label did not complete');
      }

      Future<void> show(Finder finder, {double delta = 250}) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            delta,
            scrollable: find.byType(Scrollable).last,
            maxScrolls: 80,
          );
        }
        await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> tap(Finder finder) async {
        await show(finder);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> fill(String label, String value) async {
        final field = find.descendant(
          of: find.widgetWithText(LabeledField, label),
          matching: find.byType(TextField),
        );
        await show(field);
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> save() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 200));
        await tap(find.widgetWithText(FilledButton, '保存'));
        await until(
          () => find.byType(BotEditor).evaluate().isEmpty,
          label: 'Bot/group save',
        );
      }

      await tester.runAsync(() async {
        final auth = await c.account.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        c.account.token = auth['token'];
        await c.bootstrap();
        await c.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      c.prefs.language = 'zh';
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          navigatorObservers: [nativeRoutes],
          builder: (_, child) => Platform.isWindows
              ? WindowChrome(child: child!)
              : Ambient(child: child!),
          home: HomePage(client: c),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await until(() => c.online && c.node.bots.isNotEmpty);
      for (final member in roster) {
        if (!c.node.bots.any((bot) => bot['handle'] == member[1])) {
          await tap(find.byTooltip('新建').first);
          await tap(find.text('新建 Bot').last);
          await until(() => find.byType(BotEditor).evaluate().isNotEmpty);
          await fill('名称', member[0]);
          await tester.tap(find.text('高级').last);
          await tester.pump(const Duration(milliseconds: 300));
          await fill('@handle', member[1]);
          await until(
            () => find
                .byType(MenuSelect<String>)
                .evaluate()
                .any(
                  (e) =>
                      (e.widget as MenuSelect<String>).value?.startsWith(
                        'custom:',
                      ) ==
                      true,
                ),
          );
          await fill('模型', 'gpt-6.1-sol');
          await save();
          await until(
            () => c.node.bots.any((bot) => bot['handle'] == member[1]),
          );
          debugPrint('QA created ${member[0]} through native editor');
          createdBots++;
        }
        final bot = c.node.bots.firstWhere((b) => b['handle'] == member[1]);
        expect(bot['model'], 'gpt-6.1-sol');
        final dm = c.node.conversations.firstWhere(
          (row) => row['kind'] == 'dm' && row['botId'] == bot['botId'],
        );
        final id = '${dm['conversationId']}';
        await tester.runAsync(() => c.loadMessages(id));
        await until(
          () => (c.node.messages[id] ?? []).any(
            (m) =>
                m.kind == 'text' &&
                m.content['welcome'] == true &&
                m.status == 'done',
          ),
          seconds: 900,
          label: '${member[0]} real welcome',
        );
        debugPrint('QA real welcome completed ${member[0]}');
      }
      const groupName = '自主检索与工具论文组';
      if (!c.node.groups.any((g) => g['name'] == groupName)) {
        await tap(find.byTooltip('新建').first);
        await tap(find.text('新建群组').last);
        await until(() => find.byType(BotEditor).evaluate().isNotEmpty);
        await fill('名称', groupName);
        for (final member in roster) {
          await tap(find.widgetWithText(CheckboxListTile, member[0]));
        }
        await save();
        await until(() => c.node.groups.any((g) => g['name'] == groupName));
        debugPrint('QA four-member group created through native editor');
        createdGroup = true;
      }
      final group = c.node.groups.firstWhere((g) => g['name'] == groupName);
      expect((group['botIds'] as List).length, 4);
      final conversation = c.node.conversations.firstWhere(
        (v) => v['groupId'] == group['groupId'],
      );
      final id = '${conversation['conversationId']}';
      await tap(find.byKey(ValueKey('conversation-$id')));
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await tester.runAsync(() async {
        await c.loadMessages(id);
        while ((c.node.messages[id]?.length ?? 0) >= 50) {
          final before = c.node.messages[id]!.first.seq;
          await c.loadMessages(id, before: before);
          if (c.node.messages[id]!.first.seq == before) break;
        }
      });
      const prompt = '''@everyone 上一轮验收无效，本轮从零开始，不提供论文名称、网址、预选题目或方法答案。你们必须实际调用原生工具自主完成研究，而不是只描述将如何做。请在大语言模型领域自行选一个可用单张GPU或API预算在1-2周内验证的问题，完成有真实原始文献支撑的研究构思。
每位成员本轮必须实际调用工具并在结果中说明实际观察：工具统筹先搜索研究方向并读原始来源，提出一个值得检验的问题；自主检索独立搜索并读取至少3篇真实相关论文的原始页面或正文，核对题名、作者、年份、标识和现有工作重叠；原型实验基于前两位结果用terminal编写并真实运行一个小型可执行算法/评估验证，保存源码和实际输出到自己profile工作区的research-tool-qa目录，不要伪造论文实验，不安装大依赖、不运行长训练；复现审稿用工具独立核对至少一项文献或结果，审查泄漏/基线/成本/可复现性，然后@tool_lead；统筹最后结合真实工具结果形成Markdown研究方案，包含标题、摘要、文献表格链接、方法伪代码、实验设计、失败判据和未验证项目。统筹首轮末尾@tool_lit，他已在队列不要另外重复发任务，检索和实验两位不要@成员，最后统筹不要再@。
可以用现有web_search、浏览器或terminal访问公开文献；缺少依赖或工具失败必须如实说明并用可用原生工具继续完成研究。只读取公开文献及本次研究材料，不读取凭据、私有日志或其他项目文件，不修改服务或系统配置。实际工具输出与假设必须区分，禁止说执行了未调用的工具。''';
      if (!(c.node.messages[id] ?? []).any(
        (m) => m.author.type == 'user' && m.content['text'] == prompt,
      )) {
        await tester.enterText(
          find.byKey(const ValueKey('chat-input')),
          prompt,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tap(find.byTooltip('发送'));
        debugPrint('QA actual research prompt sent through native composer');
        sentPrompt = true;
      }
      final members = (group['botIds'] as List).cast<String>();
      List<ChatMessage> replies() => (c.node.messages[id] ?? [])
          .where(
            (m) =>
                m.kind == 'text' &&
                m.author.type == 'bot' &&
                m.status == 'done',
          )
          .toList();
      var seen = -1;
      await until(
        () {
          final messages = c.node.messages[id] ?? [];
          final failures = messages
              .where((m) => m.kind == 'text' && m.status == 'failed')
              .toList();
          expect(failures, isEmpty, reason: 'Real research model run failed');
          final n = replies().length;
          if (n != seen) {
            debugPrint('QA research completed replies=$n');
            seen = n;
          }
          return n >= 5 &&
              members.every((b) => replies().any((m) => m.author.id == b)) &&
              find.byTooltip('停止').evaluate().isEmpty;
        },
        seconds: 2400,
        label: 'five real tool-enabled group turns',
      );
      expect(
        replies().length,
        5,
        reason: 'Queued literature reviewer must not run twice',
      );
      for (final botId in members) {
        expect(
          (c.node.messages[id] ?? []).any(
            (m) => m.kind == 'tool' && m.author.id == botId,
          ),
          isTrue,
          reason: 'Each Bot must actually invoke a native tool',
        );
      }
      final messageIds = replies().map((m) => m.messageId).toList();
      await tester.runAsync(() => c.loadMessages(id));
      expect(replies().map((m) => m.messageId).toList(), messageIds);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('research-tools-native-android');
      }
      binding.reportData = {
        ...?binding.reportData,
        'realModel': 'gpt-6.1-sol',
        'device': Platform.operatingSystem,
        'createdBotsThisRun': createdBots,
        'createdGroupThisRun': createdGroup,
        'sentPromptThisRun': sentPrompt,
        'restoredFiveRepliesWithoutResending': !sentPrompt,
        'group': group,
        'bots': c.node.bots
            .where((b) => members.contains(b['botId']))
            .map(
              (b) => {
                'botId': b['botId'],
                'name': b['displayName'],
                'handle': b['handle'],
                'model': b['model'],
              },
            )
            .toList(),
        'conversationId': id,
        'replies': replies(),
        'physicalAndroidTested': false,
        'productionChanged': false,
      };
      debugPrint(
        'QA five real gpt-6.1-sol turns complete; all four Bots contributed',
      );
      if (Platform.isWindows) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 60)),
        );
      }
      c.dispose();
    },
    timeout: const Timeout(Duration(minutes: 55)),
  );
}
