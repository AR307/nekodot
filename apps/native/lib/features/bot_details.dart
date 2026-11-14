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
      final text = Theme.of(context).textTheme, tone = context.tone;
      final botId = '${bot['botId']}';
      final role = '${bot['role'] ?? ''}'.trim();
      Widget link(
        String key,
        IconData icon,
        String title,
        Widget Function() page,
      ) => ListTile(
        key: ValueKey(key),
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => pushPage(context, page()),
      );
      final about = AsyncPane(
        initialData: const {},
        load: () => c.rpc('routines.list', {'botId': botId}),
        builder: (context, data, reload) {
          final routines = objects(data['routines']);
          return PageList(
            children: [
              if (role.isNotEmpty) ...[
                SelectableText(
                  role,
                  style: text.bodyMedium?.copyWith(color: tone.ink2),
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
                    'bot-learning',
                    Symbols.auto_stories,
                    c.tr('学习历程', 'Learning journey'),
                    () => LearningPage(client: c, botId: botId),
                  ),
                ],
              ),
              RoutineList(client: c, routines: routines, reload: reload),
            ],
          );
        },
      );
      final memory = AsyncPane(
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
          const refineIcon = Icon(Symbols.auto_fix_high, size: 18);
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
                          MemoryEditor(client: c, botId: botId, document: doc),
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
      );
      final library = LibraryPage(client: c, bot: bot, embedded: true);
      final settings = HermesSettings(
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
              Symbols.lock,
              c.tr('保密资料', 'Confidential information'),
              () => BotSecretsPage(client: c, botId: botId),
            ),
          ],
          'voice': [
            link(
              'bot-voice',
              Symbols.mic,
              c.tr('语音与唤醒', 'Voice & wake word'),
              () => VoicePage(client: c, botId: botId),
            ),
          ],
        },
      );
      final parts = [about, memory, library, settings];
      final labels = [
        c.tr('详情', 'Details'),
        c.tr('记忆', 'Memory'),
        c.tr('资料库', 'Files'),
        c.tr('设置', 'Settings'),
      ];
      final actions = [
        IconAction(
          tooltip: c.tr('屏幕', 'Screen'),
          icon: Symbols.desktop_windows,
          onPressed: () => pushPage(context, ScreenPage(client: c, bot: bot)),
        ),
        const SizedBox(width: 4),
        IconAction(
          tooltip: c.tr('编辑', 'Edit'),
          icon: Symbols.edit,
          onPressed: () => openPage(
            context,
            BotEditor(client: c, existing: bot),
            form: true,
          ),
        ),
      ];
      final identity = Row(
        children: [
          CatAvatar.of(bot, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${bot['displayName']}',
                  style: text.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '@${bot['handle']}',
                  style: text.bodyMedium?.copyWith(color: tone.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );
      if (onClose != null) {
        // A drawer over a desktop window: one long page, its parts listed
        // beside it.
        return Material(
          color: tone.base,
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    IconAction(
                      tooltip: c.tr('关闭', 'Close'),
                      icon: Symbols.close,
                      onPressed: onClose,
                    ),
                    const Expanded(child: WindowDrag()),
                    ...actions,
                    const SizedBox(width: 8),
                    SizedBox(width: WindowChrome.reserved(context)),
                  ],
                ),
              ),
              Expanded(
                child: _LongPage(labels: labels, head: identity, parts: parts),
              ),
            ],
          ),
        );
      }
      // A sheet on a phone: who it is, then its parts as tabs.
      return DefaultTabController(
        length: 4,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 14),
                child: Row(
                  children: [
                    Expanded(child: identity),
                    ...actions,
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DetailTabs(labels: labels),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: TabBarView(children: parts)),
            ],
          ),
        ),
      );
    },
  );
}

/// One long page with its parts listed beside it. A part's name scrolls to
/// it, and the list marks the part being read.
class _LongPage extends StatefulWidget {
  final List<String> labels;
  final List<Widget> parts;
  final Widget head;
  const _LongPage({
    required this.labels,
    required this.parts,
    required this.head,
  });
  @override
  State<_LongPage> createState() => _LongPageState();
}

class _LongPageState extends State<_LongPage> {
  final scroll = ScrollController();
  final view = GlobalKey();
  late final keys = [for (final _ in widget.labels) GlobalKey()];
  int at = 0;

  /// The part being scrolled to; until it arrives the list keeps marking it.
  int? going;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  bool follow(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (going != null) {
      if (notification is ScrollEndNotification) going = null;
      return false;
    }
    final box = view.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    // The last part whose top has reached the top of the page.
    var index = 0;
    for (final (i, key) in keys.indexed) {
      final part = key.currentContext?.findRenderObject() as RenderBox?;
      if (part != null &&
          part.localToGlobal(Offset.zero, ancestor: box).dy <= 32) {
        index = i;
      }
    }
    // At the very end the last parts cannot reach the top; the one chosen
    // there stays marked.
    final end =
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 1;
    if (index != at && !(end && index < at)) setState(() => at = index);
    return false;
  }

  void go(int index) {
    final target = keys[index].currentContext;
    if (target == null) return;
    setState(() {
      at = index;
      going = index;
    });
    Scrollable.ensureVisible(
      target,
      duration: Motion.still(context) ? Duration.zero : Motion.swap.duration,
      curve: Motion.leave,
    ).whenComplete(() => going = null);
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone, text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Column(
              children: [
                for (final (i, label) in widget.labels.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      key: ValueKey('details-part-$i'),
                      borderRadius: BorderRadius.circular(Tone.r8),
                      onTap: () => go(i),
                      child: AnimatedContainer(
                        duration: Motion.still(context)
                            ? Duration.zero
                            : Motion.tint,
                        height: 32,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: i == at
                              ? tone.hover
                              : tone.hover.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(Tone.r8),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: i == at ? tone.ink : tone.ink2,
                            fontWeight: i == at ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: follow,
            child: SingleChildScrollView(
              key: view,
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 4, 24, 40),
              child: Unscrolled(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    widget.head,
                    for (final (i, part) in widget.parts.indexed)
                      Column(
                        key: keys[i],
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(
                              widget.labels[i],
                              style: text.titleLarge,
                            ),
                          ),
                          part,
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The shared compact selector follows native tab swipes without another track.
class DetailTabs extends StatelessWidget {
  final List<String> labels;
  const DetailTabs({super.key, required this.labels});
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) => Segment<int>(
        value: controller.index,
        position: controller.animation!.value,
        options: {for (final (i, label) in labels.indexed) i: Text(label)},
        onChanged: (index) => controller.animateTo(
          index,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
        ),
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
