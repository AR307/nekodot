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
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final c = NekodotClient();
      var createdBots = 0;
      var createdGroup = false;
      var sentPrompt = false;
      final roster = [
        [
          '论文统筹',
          'paper_lead',
          '你是大模型论文项目负责人。收敛真实可实施的问题，整合队友意见。不得虚构文献、实验结果或创新性；明确待验假设。',
        ],
        [
          '文献侦察',
          'paper_lit',
          '你是大模型文献审查员。核对给定真实文献与方法的对应关系，指出已有工作重叠，不把未知结论当作事实。',
        ],
        [
          '方法设计',
          'paper_method',
          '你是大模型算法研究员。给出无需训练大模型的最小算法、输入输出、预算和可复现实验设计。区分假设与证明。',
        ],
        [
          '实验审稿',
          'paper_critic',
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
        final auth = await c.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        c.token = auth['token'];
        await c.bootstrap();
        await c.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      c.language = 'zh';
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
                .byType(DropdownButtonFormField<String>)
                .evaluate()
                .any(
                  (e) =>
                      (e.widget as DropdownButtonFormField<String>).initialValue
                          ?.startsWith('custom:') ==
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
                m['kind'] == 'text' &&
                m['content']['welcome'] == true &&
                m['status'] == 'done',
          ),
          seconds: 900,
          label: '${member[0]} real welcome',
        );
        debugPrint('QA real welcome completed ${member[0]}');
      }
      const groupName = '大模型论文工作组 · 真实验收';
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
      await tester.runAsync(() => c.loadMessages(id));
      const prompt = '''@everyone 请共同构思一篇 AI 大模型领域可落地的论文，题为“面向证据缺失与检索噪声的预算感知 RAG 拒答路由”。目前仅是研究计划，不能伪造实验结果或声称已证明创新。
真实基础文献（已从原始论文页面核对标题）：
1. Asai et al., Self-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection, https://arxiv.org/abs/2310.11511
2. Jeong et al., Adaptive-RAG: Learning to Adapt Retrieval-Augmented Large Language Models through Question Complexity, NAACL 2024, https://aclanthology.org/2024.naacl-long.389/
3. Yan et al., Corrective Retrieval Augmented Generation, https://arxiv.org/abs/2401.15884
4. Yang et al., HotpotQA: A Dataset for Diverse, Explainable Multi-hop Question Answering, https://arxiv.org/abs/1809.09600
任务范围：以一个可复现的开源7B级模型+固定检索器，研究answer/retrieve-more/abstain三选一路由；不训练基础大模型。HotpotQA按问题ID划分训练/校准/测试，构造有依据的证据移除与干扰条件，防止校准和测试泄漏。明确相对已有工作到底多了什么，若创新弱就直说。给出至少一个1-2周可执行MVP、固定预算公平比较、EM/F1与risk-coverage、引用支撑率和成本，列出消融、失败判据与不确定性。
接力规则：按统筹、文献、方法、实验顺序每人先贡献一段中文（约600字，不要使用工具或修改文件，本轮依据提供文献与已有知识，并标明未核实细节）。统筹第一轮只给问题与分工，结尾用 @paper_lit 请求文献审查（他已经在队列，不应重复调用）。文献和方法不要@任何人。实验审稿完成后用 @paper_lead 请求综合。统筹第二轮整合其他三人意见，输出约1800字的完整研究构思，包括摘要、假设、算法、数据与基线、算力/时间、消融、风险、真实参考文献；不再@任何人。''';
      if (!(c.node.messages[id] ?? []).any(
        (m) => m['author']['type'] == 'user' && m['content']?['text'] == prompt,
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
      List<Json> replies() => (c.node.messages[id] ?? [])
          .where(
            (m) =>
                m['kind'] == 'text' &&
                m['author']['type'] == 'bot' &&
                m['status'] == 'done',
          )
          .toList();
      var seen = -1;
      await until(
        () {
          final messages = c.node.messages[id] ?? [];
          final failures = messages
              .where((m) => m['status'] == 'failed')
              .toList();
          expect(failures, isEmpty, reason: 'Real research model run failed');
          final n = replies().length;
          if (n != seen) {
            debugPrint('QA research completed replies=$n');
            seen = n;
          }
          return n >= 5 &&
              members.every(
                (b) => replies().any((m) => m['author']['id'] == b),
              ) &&
              find.byTooltip('停止').evaluate().isEmpty;
        },
        seconds: 1200,
        label: 'five real group turns',
      );
      expect(
        replies().length,
        5,
        reason: 'Queued literature reviewer must not run twice',
      );
      final messageIds = replies().map((m) => m['messageId']).toList();
      await tester.runAsync(() => c.loadMessages(id));
      expect(replies().map((m) => m['messageId']).toList(), messageIds);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('research-group-native-android');
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
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
