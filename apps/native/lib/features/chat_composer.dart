import '../data/chat_models.dart';

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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

class ChatComposer extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final ChatPresentation view;
  final VoidCallback onSent;
  const ChatComposer({
    super.key,
    required this.client,
    required this.conversationId,
    required this.view,
    required this.onSent,
  });
  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  final input = TextEditingController();
  bool sending = false;
  String error = '';
  String? pendingId, pendingText;
  String? commandBotId;
  List<Json> commands = [];
  bool loadingCommands = false;
  CommandOperation? commandOperation;
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
  Json? get routineDraft => c.routineDrafts[draftKey];

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
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void editDraft(String text) {
    input.text = text;
    setState(() {});
  }

  void showError(String value) {
    setState(() => error = value);
  }

  Future<void> send() async {
    final text = input.text.trim();
    if ((text.isEmpty && attached.isEmpty) ||
        sending ||
        uploading ||
        (commandOperation?.status == 'running' &&
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
        final operation = CommandOperation.fromJson(result);
        setState(() {
          commandOperation = operation;
          submittedCommand = text;
          commandNodeId = nodeId;
        });
        pendingId = null;
        pendingText = null;
        if (sideCommand && input.text.trim() == text) input.clear();
        unawaited(followCommand(operation));
      } else {
        pendingId = null;
        pendingText = null;
      }
      await c.loadMessages(id);
      widget.onSent();
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

  Future<void> followCommand(CommandOperation operation) async {
    try {
      while (operation.status == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        operation = CommandOperation.fromJson(
          await c.rpc('operations.get', {
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
      await c.loadMessages(id);
      if (!mounted || commandNodeId != c.selectedNodeId) return;
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

  Future<void> stop() async {
    try {
      await c.rpc('runs.stop', {'conversationId': id});
      if (mounted) setState(() => error = '');
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
        state = widget.view.state,
        running = widget.view.running,
        waiting = widget.view.waiting,
        status = widget.view.status(c);
    final hasText = input.text.trim().isNotEmpty || attached.isNotEmpty;
    final queueCommand =
        state != 'unknown' && RegExp(r'^/queue(?:\s|$)').hasMatch(input.text);
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
        !(commandOperation?.status == 'running' &&
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
                        : () =>
                              setState(() => c.routineDrafts.remove(draftKey)),
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
                if (c.prefs.chatDisplay['statusbar'] == true ||
                    c.prefs.chatDisplay['battery'] == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                    child: Row(
                      key: const ValueKey('chat-statusbar'),
                      children: [
                        if (c.prefs.chatDisplay['statusbar'] == true)
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
