import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../ui/message_markdown.dart';
import '../ui/prompt_card.dart';
import '../ui/chat_notice.dart';
import '../screen/viewer.dart';
import 'bot_details.dart';
import 'bot_editor.dart';
import 'files.dart';
import 'commands.dart';
import 'client_commands.dart';
import 'routines.dart';
import 'secrets.dart';
import 'sessions.dart';
import 'voice.dart';
import 'work.dart';
import 'flowchart.dart';

class ChatPage extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final bool embedded, reserveControls;

  /// Shows a Bot's details beside the chat instead of on a page of its own.
  final ValueChanged<Json>? onDetails;
  final ValueChanged<FlowMessageFocus>? onFlow;
  final bool flowOpen;
  const ChatPage({
    super.key,
    required this.client,
    required this.conversationId,
    this.embedded = false,
    this.reserveControls = true,
    this.onDetails,
    this.onFlow,
    this.flowOpen = false,
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
  String? focusedMessage;
  final focusedKey = GlobalKey();
  bool get sideCommand =>
      submittedCommand != null &&
      RegExp(r'^/(bg|btw)(\s|$)').hasMatch(submittedCommand!);
  bool uploading = false;
  String uploadProgress = '';
  List<Json> get attached => c.attachmentDrafts[draftKey] ?? [];
  NekodotClient get c => widget.client;
  String get id => widget.conversationId;
  String get draftKey => '${c.selectedNodeId}:$id';
  Json? get routineDraft => c.routineDrafts[draftKey];
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

  Future<void> focusFlowMessage(String messageId) async {
    await c.loadMessages(id, around: messageId);
    if (!mounted) return;
    setState(() => focusedMessage = messageId);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !scroll.hasClients) return;
    scroll.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    while (mounted &&
        focusedKey.currentContext == null &&
        scroll.offset < scroll.position.maxScrollExtent) {
      await scroll.animateTo(
        (scroll.offset + scroll.position.viewportDimension * .8).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 80),
        curve: Curves.linear,
      );
    }
    final target = focusedKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target, alignment: .35);
    }
  }

  Widget flowButton() => IconButton(
    key: const ValueKey('chat-flowchart'),
    tooltip: 'Flow',
    isSelected: widget.flowOpen,
    onPressed: () {
      FocusManager.instance.primaryFocus?.unfocus();
      if (widget.onFlow != null) {
        widget.onFlow!(focusFlowMessage);
      } else {
        unawaited(openFlowchart(context, c, id, focusFlowMessage));
      }
    },
    icon: const Icon(Icons.account_tree_outlined),
  );

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
    final routineId = routineDraft?['executionId'];
    setState(() {
      sending = true;
      error = '';
    });
    final fingerprint = '$text|${files.join(',')}|$routineId';
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
          if (!command && routineId != null) 'routineExecutionId': routineId,
        },
        nodeId,
      );
      if (!command) {
        if (c.routineDrafts[key]?['executionId'] == routineId) {
          c.routineDrafts.remove(key);
        }
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
            (row) =>
                (c.chatDisplay['focus'] != true || row['kind'] != 'tool') &&
                // A text segment that ended empty when a tool started has nothing to show.
                !(row['kind'] == 'commentary' &&
                    '${row['content']?['text'] ?? ''}'.trim().isEmpty),
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
      // Steps fold together: the tool calls in a row and what the Bot wrote
      // between them, until it writes its reply or asks you something.
      final items = <List<Json>>[];
      // An approval the user allowed is one of the steps: it runs inside the box.
      bool allowed(Json m) =>
          m['kind'] == 'approval' &&
          m['status'] != 'streaming' &&
          const {
            'once',
            'session',
            'always',
          }.contains(object(m['content'])['choice']);
      bool step(Json m) => m['kind'] == 'tool' || allowed(m);
      bool work(List<Json> item) =>
          item.any((m) => m['kind'] == 'tool' || allowed(m));
      for (final m in messages) {
        if (isProgressMessage(m)) continue;
        final last = items.lastOrNull;
        if (step(m) &&
            last != null &&
            step(last.first) &&
            last.first['author']['id'] == m['author']['id']) {
          last.add(m);
        } else {
          items.add([m]);
        }
      }
      for (var i = items.length - 1; i >= 0; i--) {
        if (items[i].length > 1 && !work(items[i])) {
          items.replaceRange(i, i + 1, [
            for (final m in items[i]) [m],
          ]);
        }
      }
      // This turn of the working Bot: what it did since your last message.
      List<Json> currentTurn() {
        final all = c.node.messages[id] ?? const <Json>[];
        final start = all.lastIndexWhere((m) => m['author']['type'] == 'user');
        return all
            .skip(start + 1)
            .where(
              (m) =>
                  m['author']['type'] == 'bot' &&
                  (bot == null || m['author']['id'] == bot['botId']),
            )
            .toList();
      }

      final tail = messages.lastOrNull;
      final thinking =
          (state == 'thinking' || state == 'tool') &&
          (tail?['status'] != 'streaming' ||
              tail?['kind'] == 'tool' ||
              (tail != null && isProgressMessage(tail)));
      // While it works, the row above the composer says what it is doing.
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
                  popPage(context, BotDetails(client: c, bot: bot));
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
          flowButton(),
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
          if (widget.reserveControls)
            SizedBox(width: WindowChrome.reserved(context)),
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
                    shape: const StadiumBorder(),
                    shadows: tone.rest,
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
                            popPage(context, BotDetails(client: c, bot: bot));
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 5, 14, 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (group != null)
                              GroupAvatar(
                                size: 22,
                                working: working,
                                avatars: memberAvatars,
                              )
                            else if (bot != null)
                              CatAvatar.of(bot, size: 22, working: working),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                const SizedBox(width: 4),
                flowButton(),
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
      final composerField = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // Enter sends, Ctrl+Enter starts a new line. While an input method is
        // composing, Enter is its own.
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent ||
              (event.logicalKey != LogicalKeyboardKey.enter &&
                  event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
            return KeyEventResult.ignored;
          }
          final value = input.value;
          if (value.composing.isValid && !value.composing.isCollapsed) {
            return KeyEventResult.ignored;
          }
          if (HardwareKeyboard.instance.isControlPressed) {
            final at = value.selection.isValid
                ? value.selection
                : TextSelection.collapsed(offset: value.text.length);
            input.value = value.replaced(at, '\n');
            return KeyEventResult.handled;
          }
          if ((!waiting || queueCommand) && c.online) send();
          return KeyEventResult.handled;
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
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            hintText: c.tr('发消息', 'Message'),
          ),
        ),
      );
      final roundAction = IconButton.styleFrom(
        fixedSize: const Size.square(32),
        minimumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        iconSize: 17,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        backgroundColor: tone.ink,
        foregroundColor: tone.base,
        disabledBackgroundColor: tone.raised,
        disabledForegroundColor: tone.ink3,
      );
      final composerTools = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('composer-attach'),
            tooltip: c.tr('发送文件或图片', 'Attach file or image'),
            onPressed: !c.online || uploading || sending ? null : attachFile,
            iconSize: 19,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
          ),
        ],
      );
      final canSend =
          c.online &&
          (!waiting || queueCommand) &&
          !sending &&
          !uploading &&
          !(commandOperation?['status'] == 'running' &&
              !(sideCommand && !input.text.startsWith('/'))) &&
          hasText;
      final composerAction = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (group == null && bot != null && !hasText && !running)
            IconButton.filled(
              key: const ValueKey('composer-voice'),
              tooltip: c.tr('语音', 'Voice'),
              style: roundAction,
              onPressed: !c.online || uploading || sending || waiting
                  ? null
                  : () => pushPage(
                      context,
                      VoicePage(
                        client: c,
                        botId: '${bot['botId']}',
                        onTranscript: (text) {
                          input.text = [
                            input.text,
                            text,
                          ].where((part) => part.isNotEmpty).join(' ');
                          input.selection = TextSelection.collapsed(
                            offset: input.text.length,
                          );
                          setState(() {});
                        },
                      ),
                    ),
              icon: const Icon(Icons.mic_none),
            ),
          if (running)
            IconButton.filled(
              tooltip: c.tr('停止', 'Stop'),
              style: hasText
                  ? roundAction.copyWith(
                      backgroundColor: WidgetStatePropertyAll(tone.raised),
                      foregroundColor: WidgetStatePropertyAll(tone.ink),
                    )
                  : roundAction,
              onPressed: c.online ? stop : null,
              icon: const Icon(Icons.stop),
            ),
          if (hasText || (!running && (group != null || bot == null))) ...[
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: c.tr('发送', 'Send'),
              style: roundAction,
              onPressed: canSend ? send : null,
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
                  if (routineDraft != null)
                    InputChip(
                      key: const ValueKey('routine-followup-chip'),
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        '${routineDraft!['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: sending
                          ? null
                          : () => setState(
                              () => c.routineDrafts.remove(draftKey),
                            ),
                    ),
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
                          Expanded(
                            child: ShiningText(
                              text: c.tr(
                                'Hermes 指令执行中…',
                                'Running Hermes command…',
                              ),
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
                  PromptCard(
                    key: const ValueKey('composer-card'),
                    field: composerField,
                    tools: composerTools,
                    action: composerAction,
                    hasContent: hasText || uploading,
                    running: running,
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
                itemCount: items.length + 1 + lead,
                findChildIndexCallback: (key) {
                  final index = items.indexWhere(
                    (item) => ValueKey(item.first['messageId']) == key,
                  );
                  return index < 0 ? null : items.length - 1 - index + lead;
                },
                itemBuilder: (context, position) {
                  if (position < lead) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ThinkingRow(
                          key: const ValueKey('thinking-row'),
                          bot: bot,
                          line: workingLine(
                            c,
                            '${bot?['displayName'] ?? 'Bot'}',
                            currentTurn(),
                          ),
                        ),
                      ),
                    );
                  }
                  final index = position - lead;
                  if (index == items.length) {
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
                  final at = items.length - 1 - index,
                      item = items[at],
                      m = item.first,
                      previous = at == 0 ? null : items[at - 1].last,
                      author = members
                          .where((b) => b['botId'] == m['author']['id'])
                          .firstOrNull;
                  return Align(
                    key: ValueKey(m['messageId']),
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: KeyedSubtree(
                        key: item.any((m) => m['messageId'] == focusedMessage)
                            ? focusedKey
                            : null,
                        child: MessageTile(
                          client: c,
                          message: m,
                          steps: work(item) ? item : null,
                          // Still going while only its questions follow it.
                          live:
                              working &&
                              items
                                  .skip(at + 1)
                                  .every(
                                    (later) => const {
                                      'approval',
                                      'question',
                                    }.contains(later.first['kind']),
                                  ),
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

/// Above the composer while a Bot works: its avatar and, in its own words,
/// what it is doing ("Lumi 正在查看推文").
class ThinkingRow extends StatelessWidget {
  final Json? bot;
  final String line;
  const ThinkingRow({super.key, this.bot, required this.line});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (bot != null) CatAvatar.of(bot!, size: 24, working: true),
        const SizedBox(width: 10),
        Flexible(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: ShiningText(
              key: ValueKey(line),
              text: line,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.tone.ink3),
            ),
          ),
        ),
      ],
    ),
  );
}

class MessageTile extends StatefulWidget {
  final NekodotClient client;
  final Json message;

  /// The steps folded with this one, and whether the Bot is still on them.
  final List<Json>? steps;
  final bool live;
  final Json? bot;
  final bool continued, showName, working;
  final ValueChanged<String> onRetry;
  const MessageTile({
    super.key,
    required this.client,
    required this.message,
    this.steps,
    this.live = false,
    this.bot,
    this.continued = false,
    this.showName = false,
    this.working = false,
    required this.onRetry,
  });
  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool hovered = false, focused = false;
  NekodotClient get client => widget.client;
  Json get message => widget.message;
  Json? get bot => widget.bot;
  bool get showName => widget.showName;
  bool get continued => widget.continued;
  List<Json>? get steps => widget.steps;
  bool get live => widget.live;
  bool get working => widget.working;
  ValueChanged<String> get onRetry => widget.onRetry;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => focused = value),
      child: content(context),
    ),
  );
  Widget content(BuildContext context) {
    final c = client,
        m = message,
        tone = context.tone,
        body = object(m['content']),
        user = m['author']['type'] == 'user',
        kind = m['kind'];
    if (kind == 'system') {
      final raw = '${body['text']}';
      final command =
          '${body['command'] ?? (raw.startsWith('/') ? raw.split(RegExp(r'\s')).first : '')}';
      final label = switch (command) {
        '/resume' => c.tr('已切换会话', 'Session switched'),
        '/new' || '/clear' => c.tr('已创建新会话', 'New session created'),
        '/branch' => c.tr('已创建会话分支', 'Session branched'),
        '/compress' => c.tr('压缩结果', 'Compression result'),
        '/undo' => c.tr('已撤回上一轮', 'Last turn undone'),
        '/save' => c.tr('已保存会话', 'Session saved'),
        '' => raw,
        _ => c.tr('已执行 $command', 'Executed $command'),
      };
      return Column(
        children: [
          ChatNotice(
            text: label,
            onTap:
                command.isEmpty ||
                    const ['/resume', '/new', '/clear'].contains(command)
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(command),
                      content: SingleChildScrollView(
                        child: SelectableText(raw),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(c.tr('关闭', 'Close')),
                        ),
                      ],
                    ),
                  ),
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
      );
    }
    if (kind == 'routine') {
      return RoutineCard(client: c, content: body);
    }
    final text = body['files'] is List && (body['files'] as List).isNotEmpty
            ? withoutDeliveries('${body['text'] ?? ''}')
            : visibleMessageText(m),
        streaming = m['status'] == 'streaming',
        stopped = m['status'] == 'failed' || m['status'] == 'cancelled';
    // Files stand on their own under the words, never inside the bubble.
    final attachments = [
      if (body['files'] is List)
        for (final fileId in body['files'] as List)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FileCard(
              client: c,
              fileId: '$fileId',
              botId: user ? null : bot?['botId'] as String?,
              messageId: m['messageId'] as String,
            ),
          ),
    ];
    final card =
        steps != null ||
        const {'secret', 'routine', 'question', 'approval'}.contains(kind);
    Widget? content;
    if (kind == 'secret') {
      content = SecretCard(
        key: ValueKey(m['messageId']),
        client: c,
        content: body,
      );
    } else if (kind == 'routine') {
      content = RoutineCard(client: c, content: body);
    } else if (steps != null) {
      content = WorkBlock(
        key: ValueKey('work-${m['messageId']}'),
        client: c,
        steps: steps!,
        live: live,
      );
    } else if (kind == 'question' || kind == 'approval') {
      content = ControlCard(
        key: ValueKey(m['messageId']),
        client: c,
        message: m,
      );
    } else if (text.trim().isNotEmpty ||
        streaming ||
        stopped ||
        body['queue'] != null ||
        body['routine'] != null) {
      content = SelectionArea(
        child: Column(
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
                    botId: user
                        ? '${c.node.conversations.firstWhere((row) => row['conversationId'] == m['conversationId'])['botId']}'
                        : '${m['author']['id']}',
                    routineId: '${body['routine']['routineId']}',
                    executionId: '${body['routine']['executionId']}',
                  ),
                ),
                icon: const Icon(Icons.webhook, size: 16),
                key: ValueKey('routine-result-${m['messageId']}'),
                style: user
                    ? TextButton.styleFrom(foregroundColor: tone.base)
                    : null,
                label: Text(c.tr('例行任务 · 查看执行', 'Routine · view execution')),
              ),
            MessageMarkdown(
              data: '$text${streaming ? ' •' : ''}',
              color: user ? tone.base : null,
            ),
            if (stopped)
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
            if (body['welcome'] == true && stopped)
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
        ),
      );
    }
    if (content != null && c.chatDisplay['timestamps'] == true) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (content != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: tone.ink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: content,
                ),
              ...attachments,
            ],
          ),
        ),
      );
    }
    final copy = !card && !streaming && text.trim().isNotEmpty
        ? Opacity(
            opacity: hovered || focused ? 1 : 0,
            child: IgnorePointer(
              ignoring: !hovered && !focused,
              child: CopyButton(
                key: ValueKey('copy-${m['messageId']}'),
                client: c,
                text: text,
              ),
            ),
          )
        : null;
    final name = showName && !continued && bot != null
        ? Padding(
            padding: EdgeInsets.fromLTRB(tone.glass ? 0 : 2, 0, 0, 4),
            child: Text(
              '${bot!['displayName']}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          )
        : null;
    final avatar = SizedBox(
      width: 24,
      child: continued
          ? null
          : bot == null
          ? const CatAvatar(color: '#8C8376', size: 24)
          : CatAvatar.of(bot!, size: 24, working: working),
    );
    if (tone.glass) {
      return Padding(
        padding: EdgeInsets.only(top: continued || compact ? 4 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [?name, ?content, ...attachments, ?copy],
              ),
            ),
          ],
        ),
      );
    }
    final bubble = content == null || card
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
        ?name,
        if (bubble != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: bubble,
          ),
        ...attachments,
        ?copy,
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: continued || compact ? 3 : 12, right: 40),
      child: !showName
          ? Align(alignment: Alignment.centerLeft, child: column)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 10),
                Flexible(child: column),
              ],
            ),
    );
  }
}

/// Copies a message's words; a tick shows it worked.
class CopyButton extends StatefulWidget {
  final NekodotClient client;
  final String text;
  const CopyButton({super.key, required this.client, required this.text});
  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  Timer? reset;
  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = reset?.isActive ?? false;
    return IconButton(
      tooltip: widget.client.tr('复制', 'Copy'),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 26),
      iconSize: 15,
      color: context.tone.ink3,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (!mounted) return;
        reset?.cancel();
        setState(() {
          reset = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() {});
          });
        });
      },
      icon: Icon(done ? Icons.check : Icons.content_copy_outlined),
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
  bool unfolded = false;
  String error = '';

  /// The choice being sent, the one the Node accepted (final even before the
  /// card's own update arrives), and the last one tried, for a retry.
  String? sending, sent, tried;
  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> respond(String value) async {
    if (sending != null || sent != null) return;
    setState(() {
      sending = tried = value;
      error = '';
    });
    final question = widget.message['kind'] == 'question';
    final routine = '${widget.message['messageId']}'.startsWith(
      'routine-approval:',
    );
    try {
      await widget.client.rpc(
        routine
            ? 'routines.approvalRespond'
            : question
            ? 'questions.respond'
            : 'approvals.respond',
        routine
            ? {
                'botId': object(widget.message['content'])['botId'],
                'executionId': object(widget.message['content'])['runId'],
                'promptId': object(widget.message['content'])['requestId'],
                'choice': value,
              }
            : {
                'messageId': widget.message['messageId'],
                question ? 'answer' : 'choice': value,
              },
      );
      if (mounted) setState(() => sent = value);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client,
        m = widget.message,
        tone = context.tone,
        text = Theme.of(context).textTheme,
        data = object(m['content']),
        question = m['kind'] == 'question',
        pending = m['status'] == 'streaming' && sent == null,
        multi = data['multiSelect'] == true,
        open = c.online && sending == null,
            // An interrupted question or approval ends without an answer.
            answered =
            data['answer'] ?? data['choice'] ?? sent;
    String label(Object? choice) => switch (choice) {
      'once' => c.tr('允许一次', 'Allow once'),
      'session' => c.tr('本会话允许', 'Allow session'),
      'always' => c.tr('总是允许', 'Always allow'),
      'deny' => c.tr('拒绝', 'Deny'),
      _ => '$choice',
    };
    final choices =
        (data['choices'] as List?) ??
        (question ? const [] : const ['once', 'deny']);
    void answerWith() {
      final typed = answer.text.trim();
      if (selected.isEmpty && typed.isEmpty) return;
      respond([...selected, if (typed.isNotEmpty) typed].join('\n'));
    }

    // A send that failed can be tried again as it was.
    final retry = tried == null || !pending
        ? null
        : TextButton(
            key: const ValueKey('control-retry'),
            onPressed: open ? () => respond(tried!) : null,
            child: Text(c.tr('重试', 'Retry')),
          );

    if (!question) {
      // A command waiting for you sits in the same line as the steps do, with
      // its choices under it; once it is allowed it joins the steps instead.
      final command = firstLine(
        data['command'] == null ? '${data['prompt']}' : '${data['command']}',
      );
      final full = data['command'] == null
          ? '${data['prompt']}'
          : '${data['command']}';
      return StepFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepLine(
              key: const ValueKey('command-fold'),
              leading: pending
                  ? Icon(Icons.schedule, size: 14, color: tone.ink2)
                  : Icon(
                      answered == 'deny' ? Icons.close : Icons.check,
                      size: 14,
                      color: tone.ink3,
                    ),
              label: pending
                  ? c.tr('等你确认 · $command', 'Needs your OK · $command')
                  : '${answered == null ? c.tr('未回答', 'Not answered') : label(answered)} · $command',
              style: TextStyle(
                fontFamily: monoFont,
                fontSize: 12,
                color: pending ? tone.ink : tone.ink2,
              ),
              trailing: Icon(
                unfolded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: tone.ink3,
              ),
              onTap: () => setState(() => unfolded = !unfolded),
            ),
            if (unfolded)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tone.bubble,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  full.trim(),
                  style: TextStyle(
                    fontFamily: monoFont,
                    fontSize: 12,
                    color: tone.ink2,
                  ),
                ),
              ),
            if (pending)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (index, choice) in choices.indexed)
                      index == 0
                          ? FilledButton(
                              key: ValueKey('choice-${m['messageId']}-$index'),
                              style: optionStyle(context),
                              onPressed: !open
                                  ? null
                                  : () => respond('$choice'),
                              child: sending == '$choice'
                                  ? ShiningText(text: label(choice))
                                  : Text(label(choice)),
                            )
                          : OutlinedButton(
                              key: ValueKey('choice-${m['messageId']}-$index'),
                              style: optionStyle(context),
                              onPressed: !open
                                  ? null
                                  : () => respond('$choice'),
                              child: sending == '$choice'
                                  ? ShiningText(text: label(choice))
                                  : Text(label(choice)),
                            ),
                  ],
                ),
              ),
            ErrorNotice(error, action: retry),
          ],
        ),
      );
    }
    return ChatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data[question ? 'question' : 'prompt']}',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (!pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(
                    answered == null ? Icons.remove : Icons.check,
                    size: 16,
                    color: tone.ink3,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      answered == null
                          ? c.tr('未回答', 'Not answered')
                          : label(answered),
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            for (final (index, choice) in choices.indexed)
              ChoiceRow(
                key: ValueKey('choice-${m['messageId']}-$index'),
                index: index,
                label: label(choice),
                selected: selected.contains('$choice'),
                onTap: !open
                    ? null
                    : !question || !multi
                    ? () {
                        setState(
                          () => selected
                            ..clear()
                            ..add('$choice'),
                        );
                        respond('$choice');
                      }
                    : () => setState(() {
                        if (!selected.remove('$choice')) {
                          selected.add('$choice');
                        }
                      }),
              ),
            if (question)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  key: ValueKey('answer-${m['messageId']}'),
                  controller: answer,
                  enabled: open,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => answerWith(),
                  decoration: InputDecoration(
                    hintText: choices.isEmpty
                        ? c.tr('回答', 'Answer')
                        : c.tr('其他回答', 'Something else'),
                    suffixIcon: multi
                        ? null
                        : IconButton(
                            tooltip: c.tr('提交', 'Submit'),
                            onPressed: open && answer.text.trim().isNotEmpty
                                ? answerWith
                                : null,
                            icon: const Icon(Icons.arrow_upward, size: 18),
                          ),
                  ),
                ),
              ),
            if (question && multi)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton(
                  style: optionStyle(context),
                  onPressed:
                      open &&
                          (selected.isNotEmpty || answer.text.trim().isNotEmpty)
                      ? answerWith
                      : null,
                  child: Text(c.tr('提交', 'Submit')),
                ),
              ),
          ],
          ErrorNotice(error, action: retry),
        ],
      ),
    );
  }
}
