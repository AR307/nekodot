import 'task_details.dart';
import '../data/chat_models.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import '../ui/prompt_card.dart';
import 'files.dart';
import 'commands.dart';
import 'client_commands.dart';
import 'voice.dart';

import 'chat_presentation.dart';
import 'reasoning_slider.dart';

class ChatComposer extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final ChatPresentation view;
  final VoidCallback onSent;
  final bool historyFocused;
  const ChatComposer({
    super.key,
    required this.client,
    required this.conversationId,
    required this.view,
    required this.onSent,
    this.historyFocused = false,
  });
  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  final input = TextEditingController();
  final inputScroll = ScrollController();
  bool sending = false;
  bool savingReasoning = false;
  int reasoningRevision = 0;
  void refreshReasoning() {
    if (mounted) setState(() => reasoningRevision++);
  }

  String error = '';
  String? commandBotId;
  List<Json> commands = [];
  bool loadingCommands = false;
  CommandOperation? commandOperation;
  String? submittedCommand;
  String? commandNodeId;
  bool uploading = false;
  String uploadProgress = '';
  List<Json> get attached => c.attachmentDrafts[draftKey] ?? [];
  NekodotClient get c => widget.client;
  String get id => widget.conversationId;
  String get draftKey => '${c.selectedNodeId}:$id';
  Json? get routineDraft => c.routineDrafts[draftKey];
  Json? get taskDraft => c.workspace['taskQuote:$draftKey'] is Map
      ? object(c.workspace['taskQuote:$draftKey'])
      : null;

  @override
  void initState() {
    super.initState();
    input.text = c.drafts[draftKey] ?? '';
    quoted = c.quotes[draftKey];
    c.deliveries.addListener(deliveriesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => deliveriesChanged());
    void changed() {
      // A cleared long message must not scroll its old offset into the next draft.
      if (input.text.isEmpty && inputScroll.hasClients) inputScroll.jumpTo(0);
      c.drafts[draftKey] = input.text;
      c.saveContent();
      // Moving the caret can enter or leave an @ token without editing text.
      setState(() {});
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
  }

  @override
  void dispose() {
    c.deliveries.removeListener(deliveriesChanged);
    input.dispose();
    inputScroll.dispose();
    field.dispose();
    super.dispose();
  }

  void editDraft(String text) {
    input.text = text;
    setState(() {});
  }

  void showError(String value) {
    setState(() => error = value);
  }

  /// Words from a reply that the next message answers.
  String? quoted;
  final field = FocusNode();

  void quote(String words) {
    setState(() => quoted = words.trim());
    c.quotes[draftKey] = words.trim();
    c.saveContent();
    field.requestFocus();
  }

  /// The message as sent: the quote first, as Markdown, then your words.
  String withQuote(String text) => quoted == null || text.startsWith('/')
      ? text
      : '${quoted!.split('\n').map((line) => '> $line').join('\n')}\n\n$text';

  Future<void> send() async {
    final text = input.text.trim();
    final sentQuote = quoted;
    if ((text.isEmpty && attached.isEmpty) ||
        sending ||
        savingReasoning ||
        uploading ||
        (commandOperation?.status == 'running' &&
            !(!text.startsWith('/') ||
                RegExp(r'^/stop(?:\s|$)').hasMatch(text)))) {
      return;
    }
    if (text.startsWith('/') && commandBotId == null) {
      return;
    }
    final key = draftKey, nodeId = c.selectedNodeId;
    final messageText = withQuote(text);
    final files = attached
        .map((file) => Map<String, dynamic>.from(file))
        .toList();
    final routineId = routineDraft?['executionId'];
    final taskId = taskDraft?['taskId'];
    setState(() {
      sending = true;
      error = '';
    });
    try {
      final command = text.startsWith('/');
      final session = c.node.conversations
          .where((v) => v['conversationId'] == id)
          .firstOrNull?['sessionId'];
      await c.deliveries.enqueue(
        command ? 'commands.execute' : 'messages.send',
        {
          'conversationId': id,
          'sessionId': ?session,
          if (command) 'botId': commandBotId,
          command ? 'command' : 'text': messageText,
          'clientMsgId': uid(),
          'taskId': ?taskId,
          if (!command && routineId != null) 'routineExecutionId': routineId,
        },
        nodeId!,
        command ? [] : files,
      );
      if (!command) {
        if (c.routineDrafts[key]?['executionId'] == routineId) {
          c.routineDrafts.remove(key);
        }
        c.attachmentDrafts.remove(key);
      }
      if (c.drafts[key]?.trim() == text) c.drafts[key] = '';
      c.quotes.remove(key);
      if (taskDraft?['taskId'] == taskId) c.workspace.remove('taskQuote:$key');
      c.saveContent();
      if (!mounted) return;
      if (!command && quoted == sentQuote) setState(() => quoted = null);
      // A user can already be drafting the next instruction while RPC returns.
      if (input.text.trim() == text) input.clear();
      widget.onSent();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void deliveriesChanged() {
    if (!mounted) return;
    setState(() {});
    final ready = c.deliveries.items
        .where(
          (item) =>
              item['nodeId'] == c.selectedNodeId &&
              item['params']['conversationId'] == id &&
              item['state'] == 'completed',
        )
        .firstOrNull;
    if (ready == null || commandOperation?.status == 'running') return;
    ready['state'] = 'observing';
    submittedCommand = ready['params']['command'] as String;
    commandNodeId = ready['nodeId'] as String;
    commandOperation = CommandOperation.fromJson(object(ready['result']));
    unawaited(
      followCommand(commandOperation!).then((_) async {
        if (!mounted && commandOperation?.status == 'running') {
          ready['state'] = 'completed';
        } else {
          c.deliveries.items.remove(ready);
        }
        await c.deliveries.save();
      }),
    );
  }

  Future<void> attachFile({
    String? path,
    Uint8List? bytes,
    bool imageOnly = false,
  }) async {
    if (uploading || sending) return;
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
        c.saveContent();
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

  Future<void> attachDroppedFiles(List<DropItemFile> files) async {
    if (uploading || sending || files.isEmpty) return;
    final key = draftKey, conversationId = id;
    setState(() {
      uploading = true;
      error = '';
    });
    try {
      for (final item in files) {
        if (!mounted || draftKey != key) break;
        // Windows reports directory drops as file items too. Do not traverse
        // folders or silently attach their contents.
        if (item.path.isNotEmpty &&
            await FileSystemEntity.isDirectory(item.path)) {
          continue;
        }
        if (!mounted || draftKey != key) break;
        final file = await pickChatFile(
          c,
          conversationId,
          (_) {},
          droppedFile: item,
        );
        if (file != null) {
          c.attachmentDrafts.putIfAbsent(key, () => []).add(file);
          c.saveContent();
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => uploading = false);
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

  Future<void> followCommand(CommandOperation operation) async {
    try {
      while (operation.status == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        operation = CommandOperation.fromJson(
          await c.awaitOperation({
            'operationId': operation.operationId,
          }, commandNodeId),
        );
        if (mounted) setState(() => commandOperation = operation);
      }
      if (!mounted) return;
      if (operation.status != 'done') {
        setState(() => error = operation.detail);
      } else if (input.text.trim() == submittedCommand) {
        input.clear();
      }
      for (final result in operation.results) {
        if (!mounted) return;
        final prefill = result.prefill;
        if (prefill is String && input.text.isEmpty) input.text = prefill;
        final action = result.action;
        if (action is String && commandNodeId == c.selectedNodeId) {
          await clientCommand(
            context,
            c,
            action,
            result.argument,
            c.node.messages[id] ?? [],
            attachFile,
          );
          if (!mounted) return;
        }
        final export = result.export;
        if (export != null) {
          final saved = await FilePicker.saveFile(
            dialogTitle: c.tr('保存原生会话', 'Save native transcript'),
            fileName: export.filename,
            bytes: Uint8List.fromList(utf8.encode(export.content)),
          );
          if (saved != null && mounted) {
            showNotice(
              context,
              c.tr('会话已保存到当前设备', 'Transcript saved on this device'),
            );
          }
        }
      }
      await c.loadMessages(id, target: commandNodeId);
      if (!mounted || commandNodeId != c.selectedNodeId) return;
      refreshReasoning();
      for (final result in operation.results) {
        final page = result.page;
        if (page is String) {
          await openCommandPage(
            context,
            c,
            page,
            result.botId,
            result.argument,
          );
          if (!mounted) return;
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone,
        group = widget.view.group,
        bot = widget.view.bot,
        members = widget.view.members,
        running = widget.view.running,
        waiting = widget.view.waiting,
        status = widget.view.status(c);
    final hasText = input.text.trim().isNotEmpty || attached.isNotEmpty;
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
        send();
        return KeyEventResult.handled;
      },
      child: TextField(
        key: const ValueKey('chat-input'),
        controller: input,
        scrollController: inputScroll,
        focusNode: field,
        minLines: 1,
        maxLines: 7,
        textCapitalization: TextCapitalization.sentences,
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
      fixedSize: Size.square(tone.glass ? 48 : 32),
      minimumSize: Size.square(tone.glass ? 48 : 32),
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
          onPressed: uploading || sending ? null : attachFile,
          iconSize: 19,
          visualDensity: tone.glass
              ? VisualDensity.standard
              : VisualDensity.compact,
          icon: const Icon(Icons.add),
        ),
      ],
    );
    final canSend =
        !sending &&
        !savingReasoning &&
        !uploading &&
        !(commandOperation?.status == 'running' &&
            !(!input.text.startsWith('/') ||
                RegExp(r'^/stop(?:\s|$)').hasMatch(input.text))) &&
        hasText;
    final composerAction = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group == null && bot != null) ...[
          Flexible(
            child: ReasoningSlider(
              key: ValueKey('${c.selectedNodeId}:$id:${bot['model']}'),
              client: c,
              botId: '${bot['botId']}',
              enabled: !running && !sending,
              revision: reasoningRevision,
              onSaving: (value) {
                if (mounted) setState(() => savingReasoning = value);
              },
            ),
          ),
          const SizedBox(width: 6),
        ],
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
    // The name being typed after an @, while it is still being typed.
    final caret = input.selection.isValid
        ? input.selection.extentOffset
        : input.text.length;
    final mentioning = input.selection.isCollapsed
        ? RegExp(r'(?:^|\s)@(\S*)$')
              .firstMatch(input.text.substring(0, caret))
              ?.group(1)
        : null;
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
                // What appears above the box grows into place instead of
                // pushing the box up in one jump.
                SizeMotion(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error.isNotEmpty) ErrorNotice(error),
                      if (c.node.tasks.values.any(
                        (task) =>
                            task.conversationId == id &&
                            (task.active || task.reportMessageId == null),
                      ))
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final task in c.node.tasks.values.where(
                                (task) =>
                                    task.conversationId == id &&
                                    (task.active ||
                                        task.reportMessageId == null),
                              ))
                                TaskLink(client: c, task: task),
                            ],
                          ),
                        ),
                      if (taskDraft != null)
                        QuoteChip(
                          text: '${taskDraft!['title']}',
                          tooltip: c.tr('取消', 'Cancel'),
                          onClear: () {
                            setState(
                              () => c.workspace.remove('taskQuote:$draftKey'),
                            );
                            c.saveContent();
                          },
                        ),

                      for (final item in c.deliveries.items.where(
                        (i) =>
                            i['action'] != true &&
                            i['nodeId'] == c.selectedNodeId &&
                            i['params']['conversationId'] == id &&
                            [
                              'queued',
                              'sending',
                              'failed',
                            ].contains(i['state']),
                      ))
                        Row(
                          children: [
                            Icon(
                              item['state'] == 'failed'
                                  ? Icons.error_outline
                                  : Icons.schedule,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${item['error'] ?? item['params']['text'] ?? item['params']['command']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: c.tr('取消', 'Cancel'),
                              icon: const Icon(Icons.close, size: 16),
                              onPressed:
                                  item['state'] == 'sending' ||
                                      (item['submitted'] == true &&
                                          item['state'] != 'failed')
                                  ? null
                                  : () => c.deliveries.cancel(
                                      item['id'] as String,
                                    ),
                            ),
                          ],
                        ),
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
                              : () {
                                  setState(
                                    () => c.routineDrafts.remove(draftKey),
                                  );
                                  c.saveContent();
                                },
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
                                  fileIcon(
                                    '${file['name']}',
                                    '${file['mime']}',
                                  ),
                                  size: 16,
                                ),
                                side: BorderSide.none,
                                backgroundColor: tone.bubble,
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: tone.glass ? 210 : 280,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${file['name']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        fileSize(file['size'] as num),
                                        style: TextStyle(
                                          color: tone.ink3,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                onDeleted: sending
                                    ? null
                                    : () {
                                        setState(
                                          () => c.attachmentDrafts[draftKey]
                                              ?.remove(file),
                                        );
                                        c.saveContent();
                                      },
                              ),
                          ],
                        ),
                      if (commandOperation?.status == 'running')
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
                                  onPressed: () =>
                                      followCommand(commandOperation!),
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
                      if (quoted != null)
                        QuoteChip(
                          text: quoted!,
                          tooltip: c.tr('取消', 'Cancel'),
                          onClear: () {
                            setState(() => quoted = null);
                            c.quotes.remove(draftKey);
                            c.saveContent();
                          },
                        ),
                      if (group != null && mentioning != null)
                        MentionCard(
                          query: mentioning,
                          members: members,
                          everyone: c.tr('所有成员', 'Everyone'),
                          onPick: (handle) {
                            final start = caret - mentioning.length - 1;
                            field.requestFocus();
                            input.value = TextEditingValue(
                              text:
                                  '${input.text.substring(0, start)}@$handle ${input.text.substring(caret)}',
                              selection: TextSelection.collapsed(
                                offset: start + handle.length + 2,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                PromptCard(
                  key: const ValueKey('composer-card'),
                  field: composerField,
                  tools: composerTools,
                  action: composerAction,
                  hasContent:
                      hasText ||
                      uploading ||
                      attached.isNotEmpty ||
                      quoted != null,
                  running: running,
                  holdSize: widget.historyFocused,
                ),
                if (c.prefs.chatDisplay['statusbar'] == true ||
                    c.prefs.chatDisplay['battery'] == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                    child: Row(
                      key: const ValueKey('chat-statusbar'),
                      children: [
                        if (c.prefs.chatDisplay['statusbar'] == true)
                          Expanded(
                            child: MetaText([
                              status ?? c.tr('已连接', 'Connected'),
                              '${c.tr('Bot 配置', 'Bot config')}: ${bot?['model'] ?? ''}',
                            ], style: Theme.of(context).textTheme.labelSmall),
                          )
                        else
                          const Spacer(),
                        if (c.prefs.chatDisplay['battery'] == true)
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

    return composer;
  }
}

/// Who an @ can call in a group, as a short card above the composer that
/// narrows while you type the name.
class MentionCard extends StatelessWidget {
  final String query, everyone;
  final List<Json> members;
  final ValueChanged<String> onPick;
  const MentionCard({
    super.key,
    required this.query,
    required this.members,
    required this.everyone,
    required this.onPick,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final words = query.toLowerCase();
    final rows = <(String, String, Widget)>[
      if ('everyone'.startsWith(words) || everyone.contains(words))
        (
          'everyone',
          everyone,
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tone.raised,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_outlined, size: 17, color: tone.ink2),
          ),
        ),
      for (final bot in members)
        if ('${bot['handle']}'.toLowerCase().contains(words) ||
            '${bot['displayName']}'.toLowerCase().contains(words))
          (
            '${bot['handle']}',
            '${bot['displayName']}',
            CatAvatar.of(bot, size: 28),
          ),
    ];
    if (rows.isEmpty) return const SizedBox(width: double.infinity);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 320,
            maxHeight: (tone.glass ? 48.0 : 42.0) * 5 + 12,
          ),
          child: Panel(
            lifted: true,
            child: ListView(
              key: const ValueKey('mention-card'),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final (handle, name, avatar) in rows)
                  InkWell(
                    key: ValueKey('mention-$handle'),
                    onTap: () => onPick(handle),
                    child: SizedBox(
                      height: tone.glass ? 48 : 42,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          avatar,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(fontSize: 14),
                            ),
                          ),
                          if (handle != 'everyone')
                            Text(
                              '@$handle',
                              style: text.bodySmall?.copyWith(
                                fontSize: 12,
                                color: tone.ink3,
                              ),
                            ),
                          const SizedBox(width: 14),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The words being answered, above the composer, until sent or removed.
class QuoteChip extends StatelessWidget {
  final String text, tooltip;
  final VoidCallback onClear;
  const QuoteChip({
    super.key,
    required this.text,
    required this.tooltip,
    required this.onClear,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Padding(
      key: const ValueKey('composer-quote'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tone.bubble,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                Icon(Icons.format_quote_rounded, size: 18, color: tone.ink3),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text.replaceAll(RegExp(r'\s+'), ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tone.ink2),
                  ),
                ),
                IconButton(
                  tooltip: tooltip,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
