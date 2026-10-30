import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'chat.dart';
import 'bot_editor.dart';
import 'extensions.dart';
import 'settings.dart';
import 'pairing.dart';

class HomePage extends StatefulWidget {
  final NekodotClient client;
  const HomePage({super.key, required this.client});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<Json>? destinations;
  String? conversation;
  String? hoveredConversation;
  String search = '';
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    destinations = c.destinations.stream.listen(openDestination);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.pendingDestination != null) openDestination(c.pendingDestination!);
    });
  }

  Future<void> openDestination(Json target) async {
    c.pendingDestination = null;
    final nodeId = target['nodeId'] as String;
    if (!objects(c.me?['nodes']).any((n) => n['nodeId'] == nodeId)) return;
    await c.selectNode(nodeId);
    final value = c.node.conversations
        .where((v) => v['conversationId'] == target['conversationId'])
        .firstOrNull;
    if (value == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await open(value, MediaQuery.sizeOf(context).width < 840);
  }

  @override
  void dispose() {
    destinations?.cancel();
    super.dispose();
  }

  Future<void> open(Json value, bool narrow) async {
    final id = value['conversationId'] as String;
    if (narrow) {
      await pushPage(context, ChatPage(client: c, conversationId: id));
    } else {
      setState(() => conversation = id);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 840;
        final active = c.node.conversations.where(
          (x) => x['kind'] == 'dm'
              ? c.node.bots.any(
                  (b) => b['botId'] == x['botId'] && b['archived'] != true,
                )
              : c.node.groups.any(
                  (g) => g['groupId'] == x['groupId'] && g['archived'] != true,
                ),
        );
        final list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 16),
              child: Row(
                children: [
                  const CatAvatar(size: 32),
                  const SizedBox(width: 10),
                  Text(
                    'nekodot',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: c.tr('新建', 'Create'),
                    icon: const Icon(Icons.add),
                    onSelected: (value) => pushPage(
                      context,
                      value == 'node'
                          ? PairingPage(client: c)
                          : BotEditor(client: c, group: value == 'group'),
                    ),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'bot',
                        child: Text(c.tr('新建 Bot', 'New Bot')),
                      ),
                      PopupMenuItem(
                        value: 'group',
                        child: Text(c.tr('新建群组', 'New group')),
                      ),
                      PopupMenuItem(
                        value: 'node',
                        child: Text(c.tr('添加电脑', 'Add computer')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                initialValue: c.selectedNodeId,
                key: ValueKey(c.selectedNodeId),
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.computer,
                    color: c.online ? const Color(0xff2f9e8f) : null,
                  ),
                  labelText: c.tr('当前电脑', 'Computer'),
                ),
                items: objects(c.me?['nodes'])
                    .map(
                      (n) => DropdownMenuItem(
                        value: n['nodeId'] as String,
                        child: Text(
                          '${n['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) {
                    setState(() => conversation = null);
                    c.selectNode(id);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: c.tr('搜索会话', 'Search conversations'),
                ),
                onChanged: (value) =>
                    setState(() => search = value.toLowerCase()),
              ),
            ),
            if (!c.online)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.tr(
                          '电脑离线 · 草稿会保留',
                          'Computer offline · Drafts are kept',
                        ),
                      ),
                    ),
                    if (!c.ready)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            if (c.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    ErrorNotice(c.error),
                    TextButton.icon(
                      onPressed: () => c.bootstrap(),
                      icon: const Icon(Icons.refresh),
                      label: Text(c.tr('重新连接', 'Reconnect')),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: active.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CatAvatar(size: 56),
                            const SizedBox(height: 18),
                            Text(c.tr('从一位 Bot 开始', 'Start with a Bot')),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => pushPage(
                                context,
                                c.selectedNodeId == null
                                    ? PairingPage(client: c)
                                    : BotEditor(client: c),
                              ),
                              child: Text(c.tr('开始', 'Get started')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      children: active.map((value) {
                        final isGroup = value['kind'] == 'group';
                        final entity = isGroup
                            ? c.node.groups.firstWhere(
                                (x) => x['groupId'] == value['groupId'],
                              )
                            : c.node.bots.firstWhere(
                                (x) => x['botId'] == value['botId'],
                              );
                        final name =
                            '${entity[isGroup ? 'name' : 'displayName']}';
                        if (!name.toLowerCase().contains(search)) {
                          return const SizedBox.shrink();
                        }
                        final messages =
                            c.node.messages[value['conversationId']] ?? [];
                        final last = messages
                            .where((x) => x['kind'] == 'text')
                            .lastOrNull;
                        final selected =
                            conversation == value['conversationId'];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: MouseRegion(
                            onEnter: (_) => setState(
                              () =>
                                  hoveredConversation = value['conversationId'],
                            ),
                            onExit: (_) =>
                                setState(() => hoveredConversation = null),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 80),
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent.withValues(alpha: .10)
                                    : hoveredConversation ==
                                          value['conversationId']
                                    ? accent.withValues(alpha: .05)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  key: ValueKey(
                                    'conversation-${value['conversationId']}',
                                  ),
                                  selected: selected,
                                  leading: isGroup
                                      ? const Icon(
                                          Icons.forum_outlined,
                                          size: 34,
                                        )
                                      : CatAvatar(
                                          color: '${entity['avatar']['color']}',
                                        ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    last?['content']['text'] as String? ??
                                        (isGroup
                                            ? c.tr(
                                                '群聊 · @成员开始接力',
                                                'Group · @mention to relay',
                                              )
                                            : '@${entity['handle']}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => open(value, narrow),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => pushPage(
                      context,
                      ExtensionsPage(client: c, kind: 'skills'),
                    ),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Skills'),
                  ),
                  TextButton.icon(
                    onPressed: () => pushPage(
                      context,
                      ExtensionsPage(client: c, kind: 'plugins'),
                    ),
                    icon: const Icon(Icons.extension_outlined, size: 18),
                    label: Text(c.tr('插件', 'Plugins')),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: c.tr('设置', 'Settings'),
                    onPressed: () => pushPage(context, SettingsPage(client: c)),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
          ],
        );
        return PopScope(
          canPop: !Platform.isAndroid,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && Platform.isAndroid) {
              const MethodChannel('app.nekodot/lifecycle')
                  .invokeMethod('background');
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  SizedBox(
                    width: narrow ? constraints.maxWidth : 300,
                    child: list,
                  ),
                  if (!narrow) ...[
                    const VerticalDivider(width: 1),
                    Expanded(
                      child:
                          conversation != null &&
                              c.node.conversations.any(
                                (x) => x['conversationId'] == conversation,
                              )
                          ? ChatPage(
                              key: ValueKey(
                                '${c.selectedNodeId}:$conversation',
                              ),
                              client: c,
                              conversationId: conversation!,
                              embedded: true,
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CatAvatar(size: 80),
                                  const SizedBox(height: 20),
                                  Text(
                                    c.tr(
                                      '让想法，开始行动。',
                                      'Turn ideas into action.',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    c.tr(
                                      '选择一段会话，与你的 AI 团队一起工作。',
                                      'Choose a conversation and work with your AI team.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
