import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_editor.dart';
import 'files.dart';
import 'hermes_settings.dart';
import 'learning.dart';
import 'memory_usage.dart';
import 'model_info.dart';
import 'routines.dart';
import 'sessions.dart';
import 'desktop_control.dart';
import 'secrets.dart';
import 'voice.dart';

class BotDetails extends StatelessWidget {
  final NekodotClient client;
  final Json bot;

  /// Set when shown as a side panel; closes it instead of popping a page.
  final VoidCallback? onClose;
  const BotDetails({
    super.key,
    required this.client,
    required this.bot,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([client, client.node]),
    builder: (context, child) {
      final c = client;
      final bot = c.node.bots
          .where((value) => value['botId'] == this.bot['botId'])
          .firstOrNull;
      if (bot == null || bot['archived'] == true) {
        return AppPage(
          title: c.tr('已归档', 'Archived'),
          body: const Center(
            child: Opacity(opacity: .25, child: CatAvatar(size: 72)),
          ),
        );
      }
      final text = Theme.of(context).textTheme;
      final panel = onClose != null;
      final botId = '${bot['botId']}';
      Widget link(
        String key,
        IconData icon,
        String title,
        Widget Function() page,
      ) => ListTile(
        key: ValueKey(key),
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => pushPage(context, page()),
      );
      final pages = TabBarView(
        children: [
          AsyncPane(
            load: () => c.rpc('routines.list', {'botId': botId}),
            builder: (context, data, reload) {
              final routines = objects(data['routines']);
              return PageList(
                children: [
                  if (context.tone.glass) ...[
                    Center(child: CatAvatar.of(bot, size: 64)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('@${bot['handle']}', style: text.labelMedium),
                    ),
                    const SizedBox(height: 18),
                    SelectableText(
                      '${bot['role']}',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                  ] else ...[
                    SectionLabel(c.tr('角色', 'Role')),
                    Panel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText(
                          '${bot['role']}',
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  ModelInformation(
                    key: ValueKey(
                      '${bot['sourceId']}:${bot['model']}:${bot['modelSettings']}',
                    ),
                    client: c,
                    botId: botId,
                  ),
                  PanelGroup(
                    children: [
                      link(
                        'bot-sessions',
                        Icons.forum_outlined,
                        c.tr('历史会话', 'Sessions'),
                        () => BotSessionsPage(client: c, botId: botId),
                      ),
                      link(
                        'bot-learning',
                        Icons.auto_stories_outlined,
                        c.tr('学习历程', 'Learning journey'),
                        () => LearningPage(client: c, botId: botId),
                      ),
                    ],
                  ),
                  RoutineList(client: c, routines: routines, reload: reload),
                ],
              );
            },
          ),
          AsyncPane(
            load: () => c.rpc('memory.get', {'botId': botId}),
            builder: (context, data, reload) {
              Future<void> refine() async {
                await pushPage(context, RefinePage(client: c, botId: botId));
                reload();
              }

              final full = objects(data['documents']).any(
                (doc) =>
                    doc['name'] == 'MEMORY.md' &&
                    doc['limit'] != null &&
                    nearMemoryLimit('${doc['content']}', doc['limit'] as int),
              );
              const refineIcon = Icon(Icons.auto_fix_high_outlined, size: 18);
              final refineLabel = Text(c.tr('整理记忆', 'Refine memory'));
              return PageList(
                children: [
                  PanelGroup(
                    children: [
                      // What a Bot knows about you is shared, so it lives in app settings.
                      for (final doc in objects(
                        data['documents'],
                      ).where((doc) => doc['name'] != 'USER.md'))
                        ListTile(
                          title: Text('${doc['name']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ('${doc['content']}'.trim().isNotEmpty)
                                Text(
                                  '${doc['content']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (doc['limit'] != null) ...[
                                const SizedBox(height: 6),
                                MemoryUsage(
                                  client: c,
                                  content: '${doc['content']}',
                                  limit: doc['limit'] as int,
                                ),
                              ],
                            ],
                          ),
                          onTap: () async {
                            await pushPage(
                              context,
                              MemoryEditor(
                                client: c,
                                botId: botId,
                                document: doc,
                              ),
                            );
                            reload();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: full
                        ? FilledButton.icon(
                            key: const ValueKey('refine-memory-full'),
                            onPressed: refine,
                            icon: refineIcon,
                            label: refineLabel,
                          )
                        : OutlinedButton.icon(
                            onPressed: refine,
                            icon: refineIcon,
                            label: refineLabel,
                          ),
                  ),
                  if ('${data['pending'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        '${data['pending']}',
                        style: text.bodySmall,
                      ),
                    ),
                ],
              );
            },
          ),
          LibraryPage(client: c, bot: bot, embedded: true),
          HermesSettings(
            client: c,
            botId: botId,
            extras: {
              'model': [
                ModelInformation(
                  key: ValueKey('${bot['model']}:${bot['modelSettings']}'),
                  client: c,
                  botId: botId,
                ),
              ],
              'tools': [
                if (c.node.capabilities['host'] == 'desktop')
                  DesktopControlTile(
                    key: ValueKey('desktop-$botId'),
                    client: c,
                    botId: botId,
                  ),
              ],
              'security': [
                link(
                  'bot-secrets',
                  Icons.lock_outline,
                  c.tr('保密资料', 'Confidential information'),
                  () => BotSecretsPage(client: c, botId: botId),
                ),
              ],
              'voice': [
                link(
                  'bot-voice',
                  Icons.mic_none,
                  c.tr('语音与唤醒', 'Voice & wake word'),
                  () => VoicePage(client: c, botId: botId),
                ),
              ],
            },
          ),
        ],
      );
      final tabs = [
        c.tr('详情', 'Details'),
        c.tr('记忆', 'Memory'),
        c.tr('资料库', 'Files'),
        c.tr('设置', 'Settings'),
      ];
      final actions = [
        IconAction(
          tooltip: c.tr('屏幕', 'Screen'),
          icon: Icons.desktop_windows_outlined,
          onPressed: () => pushPage(context, ScreenPage(client: c, bot: bot)),
        ),
        const SizedBox(width: 4),
        IconAction(
          tooltip: c.tr('编辑', 'Edit'),
          icon: Icons.edit_outlined,
          onPressed: () =>
              pushPage(context, BotEditor(client: c, existing: bot)),
        ),
      ];
      if (context.tone.glass && !panel) {
        return DefaultTabController(
          length: 4,
          child: AppPage(
            title: '${bot['displayName']}',
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DetailTabs(labels: tabs),
                ),
              ),
            ),
            actions: actions,
            body: pages,
          ),
        );
      }
      return DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !panel,
            flexibleSpace: const WindowDrag(),
            actions: [
              ...actions,
              if (panel) ...[
                const SizedBox(width: 4),
                IconAction(
                  tooltip: c.tr('关闭', 'Close'),
                  icon: Icons.close,
                  onPressed: onClose,
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(width: WindowChrome.reserved(context)),
            ],
          ),
          body: Column(
            children: [
              CatAvatar.of(bot, size: 56),
              const SizedBox(height: 8),
              Text(
                '${bot['displayName']}',
                style: text.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('@${bot['handle']}', style: text.labelMedium),
              const SizedBox(height: 12),
              DetailTabs(labels: tabs),
              const SizedBox(height: 6),
              Expanded(child: pages),
            ],
          ),
        ),
      );
    },
  );
}

/// The details tabs as a pill track as wide as its labels; the chosen tab is
/// a raised pill that glides with the page swipe.
class DetailTabs extends StatelessWidget {
  final List<String> labels;
  const DetailTabs({super.key, required this.labels});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final controller = DefaultTabController.of(context);
    final text = Theme.of(context).textTheme.labelLarge;
    final height = tone.glass ? 34.0 : 28.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: tone.glass ? tone.surface : tone.raised.withValues(alpha: .7),
        shape: const StadiumBorder(),
      ),
      child: AnimatedBuilder(
        animation: controller.animation!,
        builder: (context, _) {
          final at = controller.animation!.value;
          return IntrinsicWidth(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(
                      labels.length == 1
                          ? 0
                          : -1 + 2 * at / (labels.length - 1),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / labels.length,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: tone.glass ? tone.ink : tone.thumb,
                          shape: const StadiumBorder(),
                          shadows: tone.glass ? null : tone.rest,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (index, label) in labels.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: controller.index == index,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => controller.animateTo(index),
                            child: Tab(
                              height: height,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Text(
                                  label,
                                  style: text?.copyWith(
                                    color: (at - index).abs() < .5
                                        ? (tone.glass ? tone.base : tone.ink)
                                        : tone.ink2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MemoryEditor extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Json document;
  const MemoryEditor({
    super.key,
    required this.client,
    required this.botId,
    required this.document,
  });
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final text = TextEditingController(
    text: widget.document['content'] as String,
  );
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '${widget.document['name']}',
    actions: [
      TextButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.client.rpc('memory.save', {
                    'botId': widget.botId,
                    'name': widget.document['name'],
                    'content': text.text,
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = '$e');
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(widget.client.tr('保存', 'Save')),
      ),
    ],
    body: SafeArea(
      child: Column(
        children: [
          ErrorNotice(error),
          Expanded(
            child: TextField(
              controller: text,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.all(24),
              ),
            ),
          ),
          if (widget.document['limit'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: ValueListenableBuilder(
                valueListenable: text,
                builder: (context, value, _) => MemoryUsage(
                  client: widget.client,
                  content: value.text,
                  limit: widget.document['limit'] as int,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class RefinePage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const RefinePage({super.key, required this.client, required this.botId});
  @override
  State<RefinePage> createState() => _RefinePageState();
}

class _RefinePageState extends State<RefinePage> {
  final focus = TextEditingController();
  Json? operation;
  String error = '';
  Timer? timer;
  @override
  void dispose() {
    focus.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('整理记忆', 'Refine memory'),
    body: PageList(
      children: [
        LabeledField(
          label: widget.client.tr('重点', 'Focus'),
          child: TextField(
            controller: focus,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: operation?['status'] == 'running'
                ? null
                : () async {
                    try {
                      final value = await widget.client.rpc('memory.refine', {
                        'botId': widget.botId,
                        'focus': focus.text,
                      });
                      if (!mounted) return;
                      setState(() => operation = value);
                      timer = Timer.periodic(const Duration(seconds: 2), (
                        _,
                      ) async {
                        try {
                          final value = await widget.client.rpc(
                            'operations.get',
                            {'operationId': operation!['operationId']},
                          );
                          if (mounted) setState(() => operation = value);
                          if (value['status'] != 'running') timer?.cancel();
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                          timer?.cancel();
                        }
                      });
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    }
                  },
            child: Text(widget.client.tr('开始整理', 'Refine')),
          ),
        ),
        if (operation != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              '${operation!['status']}\n${operation!['detail']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}
