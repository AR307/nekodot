import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_details.dart';
import 'bot_editor.dart';
import 'files.dart';
import 'commands.dart';
import 'client_commands.dart';
import 'routines.dart';
import 'secrets.dart';
import 'sessions.dart';

class ChatPage extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final bool embedded, reserveControls;

  /// Shows a Bot's details beside the chat instead of on a page of its own.
  final ValueChanged<Json>? onDetails;
  const ChatPage({
    super.key,
    required this.client,
    required this.conversationId,
    this.embedded = false,
    this.reserveControls = true,
    this.onDetails,
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with RouteAware {
  final input = TextEditingController(), scroll = ScrollController();
  bool sending = false;
  String error = '';
  double composerHeight = 76;
  String? pendingId, pendingText;
  String? commandBotId;
  List<Json> commands = [];
  bool loadingCommands = false;
  Json? commandOperation;
  String? submittedCommand;
  String? commandNodeId;
  bool get sideCommand =>
      submittedCommand != null &&
      RegExp(r'^/(bg|btw)(\s|$)').hasMatch(submittedCommand!);
  bool uploading = false;
  String uploadProgress = '';
  List<Json> get attached => c.attachmentDrafts[draftKey] ?? [];
  NekodotClient get c => widget.client;
  String get id => widget.conversationId;
  String get draftKey => '${c.selectedNodeId}:$id';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    nativeRoutes.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    if (c.visibleConversation == id) c.visibleConversation = null;
  }

  @override
  void didPopNext() {
    c.visibleConversation = id;
  }

  @override
  void initState() {
    super.initState();
    input.text = c.drafts[draftKey] ?? '';
    void changed() {
      c.drafts[draftKey] = input.text;
      if (input.text.startsWith('/') && commandBotId == null) {
        final conversation = c.node.conversations
            .where((x) => x['conversationId'] == id)
            .firstOrNull;
        final group = c.node.groups
            .where((x) => x['groupId'] == conversation?['groupId'])
            .firstOrNull;
        final botId = conversation?['botId'] ?? group?['leadBotId'];
        if (botId != null) unawaited(loadCommands('$botId'));
      }
    }

    input.addListener(changed);
    if (input.text.startsWith('/')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) changed();
      });
    }
    c.visibleConversation = id;
    unawaited(
      c.loadMessages(id).catchError((Object e) {
        if (mounted) setState(() => error = '$e');
      }),
    );
  }

  @override
  void dispose() {
    nativeRoutes.unsubscribe(this);
    if (c.visibleConversation == id) c.visibleConversation = null;
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if ((text.isEmpty && attached.isEmpty) ||
        sending ||
        uploading ||
        (commandOperation?['status'] == 'running' &&
            !(sideCommand && !text.startsWith('/')))) {
      return;
    }
    if (text.startsWith('/') && commandBotId == null) {
      return;
    }
    final key = draftKey, nodeId = c.selectedNodeId;
    final files = attached.map((file) => '${file['fileId']}').toList();
    setState(() {
      sending = true;
      error = '';
    });
    final fingerprint = '$text|${files.join(',')}';
    if (pendingText != fingerprint) {
      pendingText = fingerprint;
      pendingId = uid();
    }
    try {
      final command = text.startsWith('/');
      final result = await c.rpc(
        command ? 'commands.execute' : 'messages.send',
        {
          'conversationId': id,
          if (command) 'botId': commandBotId,
          command ? 'command' : 'text': text,
          'clientMsgId': pendingId,
          if (!command && files.isNotEmpty) 'files': files,
        },
        nodeId,
      );
      if (!command) {
        c.attachmentDrafts[key]?.removeWhere(
          (file) => files.contains(file['fileId']),
        );
      }
      if (!command && c.drafts[key]?.trim() == text) c.drafts[key] = '';
      if (!mounted) return;
      // A user can already be drafting the next instruction while RPC returns.
      if (!command && input.text.trim() == text) input.clear();
      if (command) {
        setState(() {
          commandOperation = result;
          submittedCommand = text;
          commandNodeId = nodeId;
        });
        pendingId = null;
        pendingText = null;
        if (sideCommand && input.text.trim() == text) input.clear();
        unawaited(followCommand(result));
      } else {
        pendingId = null;
        pendingText = null;
      }
      await c.loadMessages(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(0);
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> attachFile({
    String? path,
    Uint8List? bytes,
    bool imageOnly = false,
  }) async {
    final key = draftKey;
    setState(() {
      uploading = true;
      uploadProgress = '';
      error = '';
    });
    try {
      final file = await pickChatFile(
        c,
        id,
        (value) {
          if (mounted) setState(() => uploadProgress = value);
        },
        localPath: path,
        imageBytes: bytes,
        imageOnly: imageOnly,
      );
      if (file != null) {
        c.attachmentDrafts.putIfAbsent(key, () => []).add(file);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
          uploadProgress = '';
        });
      }
    }
  }

  Future<void> loadCommands(String botId) async {
    setState(() {
      commandBotId = botId;
      loadingCommands = true;
      commands = [];
      error = '';
    });
    try {
      final result = await c.rpc('commands.list', {'botId': botId});
      if (mounted && commandBotId == botId) {
        setState(() => commands = objects(result['commands']));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loadingCommands = false);
    }
  }

  Future<void> followCommand(Json operation) async {
    try {
      while (operation['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        operation = await c.rpc('operations.get', {
          'operationId': operation['operationId'],
        }, commandNodeId);
        if (mounted) setState(() => commandOperation = operation);
      }
      if (!mounted) return;
      if (operation['status'] != 'done') {
        setState(() => error = '${operation['detail']}');
      } else if (input.text.trim() == submittedCommand) {
        input.clear();
      }
      for (final result in objects(operation['results'])) {
        if (!mounted) return;
        final prefill = result['native']?['prefill'];
        if (prefill is String && input.text.isEmpty) input.text = prefill;
        final action = result['native']?['action'];
        if (action is String && commandNodeId == c.selectedNodeId) {
          await clientCommand(
            context,
            c,
            action,
            '${result['native']?['argument'] ?? ''}',
            c.node.messages[id] ?? [],
            attachFile,
          );
          if (!mounted) return;
        }
        final export = result['native']?['export'];
        if (export is Map) {
          final saved = await FilePicker.saveFile(
            dialogTitle: c.tr('保存原生会话', 'Save native transcript'),
            fileName: '${export['filename']}',
            bytes: Uint8List.fromList(utf8.encode('${export['content']}')),
          );
          if (saved != null && mounted) {
            showNotice(
              context,
              c.tr('会话已保存到当前设备', 'Transcript saved on this device'),
            );
          }
        }
      }
      await c.loadMessages(id);
      if (!mounted || commandNodeId != c.selectedNodeId) return;
      for (final result in objects(operation['results'])) {
        final page = result['native']?['page'];
        if (page is String) {
          await openCommandPage(
            context,
            c,
            page,
            '${result['botId']}',
            '${result['native']?['argument'] ?? ''}',
          );
          if (!mounted) return;
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> stop() async {
    try {
      await c.rpc('runs.stop', {'conversationId': id});
      if (mounted) setState(() => error = '');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, child) {
      final conversation = c.node.conversations
          .where((x) => x['conversationId'] == id)
          .firstOrNull;
      if (conversation == null) return const SizedBox.shrink();
      final group = conversation['kind'] == 'group'
          ? c.node.groups
                .where((x) => x['groupId'] == conversation['groupId'])
                .firstOrNull
          : null;
      final activity = c.node.activities[id] ?? {'state': 'idle'};
      final state = activity['state'],
          running = state != 'idle',
          working = state != 'idle' && state != 'unknown',
          waiting =
              state == 'waiting_approval' ||
              state == 'waiting_question' ||
              state == 'unknown';
      final members = c.node.bots
          .where(
            (b) => group == null
                ? b['botId'] == conversation['botId']
                : (group['botIds'] as List).contains(b['botId']),
          )
          .toList();
      final messages = (c.node.messages[id] ?? [])
          .where(
            (row) => c.chatDisplay['focus'] != true || row['kind'] != 'tool',
          )
          .toList();
      final lastBot = messages
          .where((m) => m['author']['type'] == 'bot')
          .lastOrNull?['author']['id'];
      final bot =
          members
              .where(
                (b) =>
                    b['botId'] ==
                    (activity['botId'] ??
                        lastBot ??
                        group?['leadBotId'] ??
                        conversation['botId']),
              )
              .firstOrNull ??
          members.firstOrNull;
      final title =
          group?['name'] as String? ?? bot?['displayName'] as String? ?? 'Bot';
      final tone = context.tone;
      final memberAvatars = [
        for (final member in members) object(member['avatar']),
      ];
      final tail = messages.lastOrNull;
      final thinking =
          (state == 'thinking' || state == 'tool') &&
          tail?['status'] != 'streaming';
      final lead = thinking && messages.isNotEmpty ? 1 : 0;
      final status = !c.online
          ? c.tr('离线', 'Offline')
          : activity['connection'] == 'reconnecting'
          ? c.tr('重连中', 'Reconnecting')
          : switch (state) {
              'thinking' => c.tr('回复中', 'Replying'),
              'tool' => c.tr('工具运行中', 'Using tools'),
              'waiting_approval' => c.tr('等你确认', 'Needs your OK'),
              'waiting_question' => c.tr('等你回答', 'Needs your answer'),
              'unknown' => c.tr('执行中断，待确认', 'Execution interrupted'),
              _ => null,
            };
      final chain = activity['chain'] as Map?;
      final hasText = input.text.trim().isNotEmpty || attached.isNotEmpty;
      final queueCommand =
          state != 'unknown' && RegExp(r'^/queue(?:\s|$)').hasMatch(input.text);
      final glassHeader = AppBar(
        flexibleSpace: const Frost(),
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 12 : 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: c.tr('详情', 'Details'),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                if (group != null) {
                  pushPage(
                    context,
                    BotEditor(client: c, group: true, existing: group),
                  );
                } else if (bot != null) {
                  pushPage(context, BotDetails(client: c, bot: bot));
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (group != null)
                      GroupAvatar(
                        size: 30,
                        working: working,
                        avatars: memberAvatars,
                      )
                    else if (bot != null)
                      CatAvatar.of(bot, size: 30, working: working),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (status != null || chain != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (chain != null) ...[
                                  ChainDots(
                                    count: chain['count'] as int,
                                    max: chain['max'] as int,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                if (status != null)
                                  Flexible(
                                    child: Text(
                                      status,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (group == null && bot != null)
            IconButton(
              key: const ValueKey('chat-sessions'),
              tooltip: c.tr('历史会话与切换', 'Sessions and switch'),
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                pushPage(
                  context,
                  BotSessionsPage(client: c, botId: '${bot['botId']}'),
                );
              },
              icon: const Icon(Icons.forum_outlined),
            ),
          IconButton(
            tooltip: c.tr('屏幕', 'Screen'),
            onPressed: bot == null
                ? null
                : () => pushPage(
                    context,
                    ScreenPage(client: c, bot: bot, members: members),
                  ),
            icon: const Icon(Icons.desktop_windows_outlined),
          ),
          const SizedBox(width: 8),
        ],
      );
      final header = tone.glass
          ? glassHeader
          : AppBar(
              flexibleSpace: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tone.base, tone.base.withValues(alpha: 0)],
                  ),
                ),
                child: const WindowDrag(),
              ),
              automaticallyImplyLeading: !widget.embedded,
              centerTitle: true,
              titleSpacing: 8,
              title: Tooltip(
                message: c.tr('详情', 'Details'),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: tone.surface,
                    shape: StadiumBorder(side: BorderSide(color: tone.line)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () {
                        if (group != null) {
                          pushPage(
                            context,
                            BotEditor(client: c, group: true, existing: group),
                          );
                        } else if (bot != null) {
                          if (widget.onDetails != null) {
                            widget.onDetails!(bot);
                          } else {
                            pushPage(context, BotDetails(client: c, bot: bot));
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (group != null)
                              GroupAvatar(
                                size: 20,
                                working: working,
                                avatars: memberAvatars,
                              )
                            else if (bot != null)
                              CatAvatar.of(bot, size: 20, working: working),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (chain != null) ...[
                              const SizedBox(width: 8),
                              ChainDots(
                                count: chain['count'] as int,
                                max: chain['max'] as int,
                              ),
                            ],
                            if (status != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                if (group == null && bot != null)
                  IconButton(
                    key: const ValueKey('chat-sessions'),
                    tooltip: c.tr('历史会话与切换', 'Sessions and switch'),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      pushPage(
                        context,
                        BotSessionsPage(client: c, botId: '${bot['botId']}'),
                      );
                    },
                    icon: const Icon(Icons.forum_outlined),
                  ),
                IconAction(
                  tooltip: c.tr('屏幕', 'Screen'),
                  icon: Icons.desktop_windows_outlined,
                  onPressed: bot == null
                      ? null
                      : () => pushPage(
                          context,
                          ScreenPage(client: c, bot: bot, members: members),
                        ),
                ),
                const SizedBox(width: 12),
                if (widget.reserveControls)
                  SizedBox(width: WindowChrome.reserved(context)),
              ],
            );
      final composerRow = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: c.tr('发送文件或图片', 'Attach file or image'),
            onPressed: !c.online || uploading || sending ? null : attachFile,
            icon: const Icon(Icons.add_circle_outline),
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: true,
                ): () {
                  if ((!waiting || queueCommand) && c.online) send();
                },
              },
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: input,
                minLines: 1,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  // CJK glyphs sit low on the Latin baseline; lift them onto the button's line.
                  contentPadding: EdgeInsets.fromLTRB(
                    8,
                    tone.glass ? 11 : 2,
                    8,
                    tone.glass ? 15 : 6,
                  ),
                  hintText: c.tr('发消息', 'Message'),
                ),
              ),
            ),
          ),
          if (running)
            IconButton.filled(
              tooltip: c.tr('停止', 'Stop'),
              style: IconButton.styleFrom(
                fixedSize: Size.square(tone.control - 4),
                minimumSize: Size.square(tone.control - 4),
                padding: EdgeInsets.zero,
                iconSize: tone.icon - 2,
                tapTargetSize: tone.glass
                    ? MaterialTapTargetSize.padded
                    : MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tone.corner - 2),
                ),
                backgroundColor: hasText ? tone.raised : tone.ink,
                foregroundColor: hasText ? tone.ink : tone.base,
              ),
              onPressed: c.online ? stop : null,
              icon: const Icon(Icons.stop),
            ),
          if (!running || hasText) ...[
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: c.tr('发送', 'Send'),
              style: IconButton.styleFrom(
                fixedSize: Size.square(tone.control - 4),
                minimumSize: Size.square(tone.control - 4),
                padding: EdgeInsets.zero,
                iconSize: tone.icon - 2,
                tapTargetSize: tone.glass
                    ? MaterialTapTargetSize.padded
                    : MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tone.corner - 2),
                ),
                backgroundColor: tone.ink,
                foregroundColor: tone.base,
                disabledBackgroundColor: tone.raised,
                disabledForegroundColor: tone.ink3,
              ),
              onPressed:
                  !c.online ||
                      (waiting && !queueCommand) ||
                      sending ||
                      uploading ||
                      (commandOperation?['status'] == 'running' &&
                          !(sideCommand && !input.text.startsWith('/'))) ||
                      !hasText
                  ? null
                  : send,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ],
      );
      final composer = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error.isNotEmpty) ErrorNotice(error),
                  if (uploading) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    Text(
                      uploadProgress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (attached.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final file in attached)
                          InputChip(
                            avatar: Icon(
                              '${file['mime']}'.startsWith('image/')
                                  ? Icons.image_outlined
                                  : Icons.description_outlined,
                              size: 16,
                            ),
                            label: Text(
                              '${file['name']} · ${fileSize(file['size'] as num)}',
                            ),
                            onDeleted: sending
                                ? null
                                : () => setState(
                                    () => c.attachmentDrafts[draftKey]?.remove(
                                      file,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  if (commandOperation?['status'] == 'running')
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Breathing(),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.tr('Hermes 指令执行中…', 'Running Hermes command…'),
                            ),
                          ),
                          if (error.isNotEmpty)
                            TextButton(
                              onPressed: () => followCommand(commandOperation!),
                              child: Text(c.tr('查看结果', 'Check result')),
                            ),
                        ],
                      ),
                    ),
                  if (input.text.startsWith('/') &&
                      commandBotId != null &&
                      !input.text.contains(RegExp(r'\s')))
                    CommandPalette(
                      client: c,
                      entries: commands,
                      members: members,
                      query: input.text,
                      botId: commandBotId!,
                      loading: loadingCommands,
                      onBot: loadCommands,
                      onRefresh: () => loadCommands(commandBotId!),
                      onSelect: (name) {
                        input.text = '$name ';
                        input.selection = TextSelection.collapsed(
                          offset: input.text.length,
                        );
                        setState(() {});
                      },
                    ),
                  if (state == 'unknown')
                    ErrorNotice(
                      c.tr(
                        '执行已中断。请先点击停止确认，再发送新任务；已完成的操作会保留。',
                        'Click Stop to acknowledge the interrupted execution before sending a new task. Completed effects are kept.',
                      ),
                    ),
                  if (group != null && input.text.contains('@'))
                    SizedBox(
                      height: tone.control + 4,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              final start = input.text.lastIndexOf('@');
                              input.text =
                                  '${input.text.substring(0, start)}@everyone ';
                              setState(() {});
                            },
                            icon: const Icon(Icons.groups_outlined, size: 18),
                            label: Text(c.tr('所有成员', 'Everyone')),
                          ),
                          ...members.map(
                            (b) => TextButton.icon(
                              onPressed: () {
                                final start = input.text.lastIndexOf('@');
                                input.text =
                                    '${input.text.substring(0, start)}@${b['handle']} ';
                                setState(() {});
                              },
                              icon: CatAvatar.of(b, size: 18),
                              label: Text('${b['displayName']}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (tone.glass)
                    Panel(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: composerRow,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: tone.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tone.line),
                      ),
                      child: composerRow,
                    ),
                  if (c.chatDisplay['statusbar'] == true ||
                      c.chatDisplay['battery'] == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                      child: Row(
                        key: const ValueKey('chat-statusbar'),
                        children: [
                          if (c.chatDisplay['statusbar'] == true)
                            Expanded(
                              child: Text(
                                '${status ?? c.tr('已连接', 'Connected')} · ${c.tr('Bot 配置', 'Bot config')}: ${bot?['model'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            )
                          else
                            const Spacer(),
                          if (c.chatDisplay['battery'] == true)
                            DeviceBattery(client: c),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return Scaffold(
        appBar: header,
        body: Stack(
          children: [
            if (messages.isEmpty)
              Center(
                child: bot == null
                    ? null
                    : group == null
                    ? CatAvatar.of(bot, size: 56)
                    : GroupAvatar(size: 56, avatars: memberAvatars),
              )
            else
              ListView.builder(
                key: const ValueKey('chat-messages'),
                controller: scroll,
                reverse: true,
                padding: EdgeInsets.fromLTRB(14, 6, 14, composerHeight + 2),
                itemCount: messages.length + 1 + lead,
                findChildIndexCallback: (key) {
                  final index = messages.indexWhere(
                    (message) => ValueKey(message['messageId']) == key,
                  );
                  return index < 0 ? null : messages.length - 1 - index + lead;
                },
                itemBuilder: (context, position) {
                  if (position < lead) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ThinkingRow(bot: bot, showName: group != null),
                      ),
                    );
                  }
                  final index = position - lead;
                  if (index == messages.length) {
                    return (c.node.messages[id]?.length ?? 0) < 50
                        ? const SizedBox.shrink()
                        : Center(
                            child: IconButton(
                              tooltip: c.tr('加载更早消息', 'Load earlier messages'),
                              onPressed: () async {
                                try {
                                  await c.loadMessages(
                                    id,
                                    before: messages.first['seq'] as int,
                                  );
                                } catch (e) {
                                  if (mounted) setState(() => error = '$e');
                                }
                              },
                              icon: const Icon(Icons.expand_less),
                            ),
                          );
                  }
                  final at = messages.length - 1 - index,
                      m = messages[at],
                      previous = at == 0 ? null : messages[at - 1],
                      author = members
                          .where((b) => b['botId'] == m['author']['id'])
                          .firstOrNull;
                  return Align(
                    key: ValueKey(m['messageId']),
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: MessageTile(
                        client: c,
                        message: m,
                        bot: author,
                        showName: group != null,
                        working: working && index == 0,
                        continued:
                            previous != null &&
                            previous['kind'] != 'system' &&
                            previous['author']['id'] == m['author']['id'] &&
                            previous['author']['type'] == m['author']['type'],
                        onRetry: (text) {
                          input.text = text;
                        },
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MeasureHeight(
                onChange: (height) {
                  if (mounted && height != composerHeight) {
                    setState(() => composerHeight = height);
                  }
                },
                child: composer,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The working cat and its hopping dots, until the reply starts to stream.
class ThinkingRow extends StatelessWidget {
  final Json? bot;
  final bool showName;
  const ThinkingRow({super.key, this.bot, this.showName = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (bot != null) CatAvatar.of(bot!, size: 24, working: true),
        const SizedBox(width: 10),
        const ThinkingDots(),
      ],
    ),
  );
}

class ToolRow extends StatefulWidget {
  final Json message;
  const ToolRow({super.key, required this.message});
  @override
  State<ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<ToolRow> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final m = widget.message, body = object(m['content']);
    final running = m['status'] == 'streaming',
        failed = m['status'] == 'failed';
    final duration = (body['durationMs'] as num?) ?? 0;
    final preview = '${body['preview'] ?? ''}'.trim();
    final detail = [
      preview,
      '${body['resultPreview'] ?? ''}'.trim(),
    ].where((text) => text.isNotEmpty).join('\n');
    final mono = TextStyle(
      fontFamily: monoFont,
      fontSize: 12,
      color: tone.ink2,
    );
    return Material(
      color: tone.glass ? tone.bubble : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tone.corner),
        side: tone.glass ? BorderSide(color: tone.line) : BorderSide.none,
      ),
      child: InkWell(
        onTap: detail.isEmpty ? null : () => setState(() => open = !open),
        child: AnimatedSize(
          alignment: Alignment.topCenter,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tone.glass ? 10 : 4,
              vertical: tone.glass ? 7 : 3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    running
                        ? const Breathing(size: 8)
                        : StatusDot(color: failed ? tone.danger : tone.ink3),
                    const SizedBox(width: 8),
                    Text(
                      '${body['tool']}',
                      style: mono.copyWith(color: tone.ink),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        open ? '' : preview.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono.copyWith(color: tone.ink3),
                      ),
                    ),
                    if (!running) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${(duration / 1000).toStringAsFixed(1)}s',
                        style: mono.copyWith(color: tone.ink3),
                      ),
                    ],
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 10),
                  SelectableText(detail, style: mono),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MessageTile extends StatelessWidget {
  final NekodotClient client;
  final Json message;
  final Json? bot;
  final bool continued, showName, working;
  final ValueChanged<String> onRetry;
  const MessageTile({
    super.key,
    required this.client,
    required this.message,
    this.bot,
    this.continued = false,
    this.showName = false,
    this.working = false,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final c = client,
        m = message,
        tone = context.tone,
        body = object(m['content']),
        user = m['author']['type'] == 'user',
        kind = m['kind'];
    if (kind == 'system') {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '${body['text']}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            for (final fileId in (body['files'] as List? ?? []))
              FileCard(
                client: c,
                fileId: '$fileId',
                messageId: '${m['messageId']}',
              ),
            if (body['retryText'] != null)
              TextButton(
                onPressed: () => onRetry(body['retryText'] as String),
                child: Text(c.tr('重新编辑', 'Edit & resend')),
              ),
          ],
        ),
      );
    }
    Widget content;
    if (kind == 'secret') {
      content = SecretCard(
        key: ValueKey(m['messageId']),
        client: c,
        content: body,
      );
    } else if (kind == 'routine') {
      content = RoutineCard(client: c, content: body);
    } else if (kind == 'tool') {
      content = ToolRow(message: m);
    } else if (kind == 'question' || kind == 'approval') {
      content = ControlCard(
        key: ValueKey(m['messageId']),
        client: c,
        message: m,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body['queue'] != null)
            Text(
              switch (body['queue']) {
                'queued' => c.tr(
                  '已排队 · 当前任务完成后执行',
                  'Queued · runs after the current turn',
                ),
                'running' => c.tr('队列任务', 'Queued task'),
                'steered' => c.tr('已交给当前任务', 'Sent to the current turn'),
                _ => c.tr('已取消排队', 'Queue entry cancelled'),
              },
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: user ? tone.base.withValues(alpha: 0.75) : tone.ink3,
              ),
            ),
          if (body['routine'] != null)
            TextButton.icon(
              onPressed: () => pushPage(
                context,
                RoutinePage(
                  client: c,
                  botId: '${m['author']['id']}',
                  routineId: '${body['routine']['routineId']}',
                  executionId: '${body['routine']['executionId']}',
                ),
              ),
              icon: const Icon(Icons.webhook, size: 16),
              label: Text(c.tr('例行任务 · 查看执行', 'Routine · view execution')),
            ),
          MarkdownBody(
            data:
                '${body['text'] ?? ''}${m['status'] == 'streaming' ? ' •' : ''}',
            selectable: true,
            styleSheet: markdownStyle(context, color: user ? tone.base : null),
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
          if (body['files'] is List)
            for (final fileId in body['files'] as List)
              FileCard(
                client: c,
                fileId: '$fileId',
                botId: bot?['botId'] as String?,
                messageId: m['messageId'] as String,
                foreground: user ? tone.base : null,
              ),
          if (m['status'] == 'failed' || m['status'] == 'cancelled')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                m['status'] == 'cancelled'
                    ? c.tr('已停止', 'Stopped')
                    : body['failureReason'] as String? ??
                          c.tr('已中断', 'Interrupted'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: m['status'] == 'cancelled' ? tone.ink3 : tone.danger,
                ),
              ),
            ),
          if (body['welcome'] == true &&
              ['failed', 'cancelled'].contains(m['status']))
            TextButton.icon(
              onPressed: !c.online
                  ? null
                  : () async {
                      try {
                        await c.rpc('bots.welcome.retry', {
                          'messageId': m['messageId'],
                        });
                      } catch (e) {
                        if (context.mounted) {
                          showNotice(context, '$e');
                        }
                      }
                    },
              icon: const Icon(Icons.refresh),
              label: Text(c.tr('重试自我介绍', 'Retry introduction')),
            ),
        ],
      );
    }
    if (c.chatDisplay['timestamps'] == true) {
      final at = DateTime.parse('${m['createdAt']}').toLocal();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
            key: ValueKey('message-time-${m['messageId']}'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: user ? tone.base.withValues(alpha: .7) : tone.ink3,
            ),
          ),
          content,
        ],
      );
    }
    final compact = c.chatDisplay['density'] == true;
    if (user) {
      return Padding(
        padding: EdgeInsets.only(top: continued || compact ? 3 : 12, left: 56),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: tone.ink,
              borderRadius: BorderRadius.circular(12),
            ),
            child: content,
          ),
        ),
      );
    }
    if (tone.glass) {
      return Padding(
        padding: EdgeInsets.only(top: continued || compact ? 4 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: continued
                  ? null
                  : bot == null
                  ? const CatAvatar(color: '#8C8376', size: 24)
                  : CatAvatar.of(bot!, size: 24, working: working),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showName && !continued && bot != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${bot!['displayName']}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  content,
                ],
              ),
            ),
          ],
        ),
      );
    }
    final bubble = kind == 'tool' || kind == 'question' || kind == 'approval'
        ? content
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: tone.bubble,
              borderRadius: BorderRadius.circular(12),
            ),
            child: content,
          );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showName && !continued && bot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 0, 4),
            child: Text(
              '${bot!['displayName']}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: bubble,
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: continued || compact ? 3 : 12, right: 40),
      child: !showName
          ? Align(alignment: Alignment.centerLeft, child: column)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: continued
                      ? null
                      : bot == null
                      ? const CatAvatar(color: '#8C8376', size: 24)
                      : CatAvatar.of(bot!, size: 24, working: working),
                ),
                const SizedBox(width: 10),
                Flexible(child: column),
              ],
            ),
    );
  }
}

class ControlCard extends StatefulWidget {
  final NekodotClient client;
  final Json message;
  const ControlCard({super.key, required this.client, required this.message});
  @override
  State<ControlCard> createState() => _ControlCardState();
}

class _ControlCardState extends State<ControlCard> {
  final answer = TextEditingController();
  final selected = <String>{};
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> respond(String value) async {
    setState(() {
      busy = true;
      error = '';
    });
    final question = widget.message['kind'] == 'question';
    try {
      await widget.client.rpc(
        question ? 'questions.respond' : 'approvals.respond',
        {
          'messageId': widget.message['messageId'],
          question ? 'answer' : 'choice': value,
        },
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client,
        m = widget.message,
        tone = context.tone,
        data = object(m['content']),
        question = m['kind'] == 'question',
        pending = m['status'] == 'streaming',
        multi = data['multiSelect'] == true;
    String label(Object? choice) => switch (choice) {
      'once' => c.tr('允许一次', 'Allow once'),
      'session' => c.tr('本会话允许', 'Allow session'),
      'always' => c.tr('总是允许', 'Always allow'),
      'deny' => c.tr('拒绝', 'Deny'),
      _ => '$choice',
    };
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('${data[question ? 'question' : 'prompt']}'),
            if (data['command'] != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: tone.bubble,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  '${data['command']}',
                  style: const TextStyle(fontFamily: monoFont, fontSize: 12),
                ),
              ),
            if (!pending)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: tone.ink3),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label(data['answer'] ?? data['choice'] ?? m['status']),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (pending && question) ...[
              const SizedBox(height: 4),
              for (final option in data['choices'] as List? ?? [])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('$option'),
                  value: selected.contains('$option'),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          if (!multi) selected.clear();
                          if (value == true) {
                            selected.add('$option');
                          } else {
                            selected.remove('$option');
                          }
                        }),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: answer,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: c.tr('回答', 'Answer')),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed:
                    !c.online ||
                        busy ||
                        (selected.isEmpty && answer.text.trim().isEmpty)
                    ? null
                    : () => respond(
                        [
                          ...selected,
                          if (answer.text.trim().isNotEmpty) answer.text.trim(),
                        ].join('\n'),
                      ),
                child: Text(c.tr('提交', 'Submit')),
              ),
            ],
            if (pending && !question) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (index, choice)
                      in (data['choices'] as List? ?? ['once', 'deny']).indexed)
                    index == 0
                        ? FilledButton(
                            onPressed: !c.online || busy
                                ? null
                                : () => respond('$choice'),
                            child: Text(label(choice)),
                          )
                        : OutlinedButton(
                            onPressed: !c.online || busy
                                ? null
                                : () => respond('$choice'),
                            child: Text(label(choice)),
                          ),
                ],
              ),
            ],
            ErrorNotice(error),
          ],
        ),
      ),
    );
  }
}
