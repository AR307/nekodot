import '../data/chat_models.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import '../ui/message_markdown.dart';
import '../ui/message_selection.dart';
import '../ui/chat_notice.dart';
import 'files.dart';
import 'routines.dart';
import 'secrets.dart';
import 'work.dart';

/// One line of a bubble is a pill; longer bubbles keep the same round corners.
const _bubbleRadius = 18.0;

class MessageTile extends StatefulWidget {
  final NekodotClient client;
  final ChatMessage message;

  final Json? bot;
  final bool continued, showName, working;
  final ValueChanged<String> onRetry;

  /// Takes words selected in the message into the composer as a quote.
  final ValueChanged<String>? onQuote;
  const MessageTile({
    super.key,
    required this.client,
    required this.message,
    this.bot,
    this.continued = false,
    this.showName = false,
    this.working = false,
    required this.onRetry,
    this.onQuote,
  });
  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool hovered = false, focused = false;

  NekodotClient get client => widget.client;
  ChatMessage get message => widget.message;
  Json? get bot => widget.bot;
  bool get showName => widget.showName;
  bool get continued => widget.continued;
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
        body = object(m.content),
        user = m.author.type == 'user',
        kind = m.kind;
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
        '/stop' =>
          raw == 'Stop requested' ? c.tr('已请求停止', 'Stop requested') : raw,
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
            FileCard(client: c, fileId: '$fileId', messageId: m.messageId),
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
        streaming = m.status == 'streaming',
        stopped = m.status == 'failed' || m.status == 'cancelled';
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
              messageId: m.messageId,
            ),
          ),
    ];
    final card = const {
      'secret',
      'routine',
      'question',
      'approval',
    }.contains(kind);
    Widget? content;
    if (kind == 'secret') {
      content = SecretCard(
        key: ValueKey(m.messageId),
        client: c,
        content: body,
      );
    } else if (kind == 'routine') {
      content = RoutineCard(client: c, content: body);
    } else if (kind == 'question' || kind == 'approval') {
      content = ControlCard(key: ValueKey(m.messageId), client: c, message: m);
    } else if (text.trim().isNotEmpty ||
        streaming ||
        stopped ||
        body['queue'] != null ||
        body['routine'] != null) {
      content = MessageSelection(
        quoteLabel: c.tr('引用回复', 'Quote in reply'),
        onQuote: widget.onQuote,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body['queue'] == 'cancelled')
              Text(
                c.tr('已取消排队', 'Queue entry cancelled'),
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
                        ? '${c.node.conversations.firstWhere((row) => row['conversationId'] == m.conversationId)['botId']}'
                        : '${m.author.id}',
                    routineId: '${body['routine']['routineId']}',
                    executionId: '${body['routine']['executionId']}',
                  ),
                ),
                icon: const Icon(Icons.webhook, size: 16),
                key: ValueKey('routine-result-${m.messageId}'),
                style: user
                    ? TextButton.styleFrom(foregroundColor: tone.base)
                    : null,
                label: Text(c.tr('查看例行任务执行', 'View routine run')),
              ),
            MessageMarkdown(
              data: '$text${streaming ? ' •' : ''}',
              color: user ? tone.base : null,
            ),
            if (stopped)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  m.status == 'cancelled'
                      ? c.tr('已停止', 'Stopped')
                      : switch (body['failureCode']) {
                          'run_start' => c.tr(
                            '无法开始，请检查模型来源后重试',
                            "Couldn't start. Check the model source and try again",
                          ),
                          'timeout' => c.tr(
                            '启动超时，请重试',
                            'Timed out while starting. Try again',
                          ),
                          _ =>
                            body['failureReason'] as String? ??
                                c.tr('已中断', 'Interrupted'),
                        },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: m.status == 'cancelled' ? tone.ink3 : tone.danger,
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
                            'messageId': m.messageId,
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
    if (content != null && c.prefs.chatDisplay['timestamps'] == true) {
      final at = DateTime.parse(m.createdAt).toLocal();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
            key: ValueKey('message-time-${m.messageId}'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: user ? tone.base.withValues(alpha: .7) : tone.ink3,
            ),
          ),
          content,
        ],
      );
    }
    final compact = c.prefs.chatDisplay['density'] == true;
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
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: ShapeDecoration(
                    color: tone.ink,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(_bubbleRadius),
                    ),
                  ),
                  child: content,
                ),
              ...attachments,
            ],
          ),
        ),
      );
    }
    // Beside the bubble on hover, so it never adds a line under each reply. A
    // phone has no hover; its text is selected and copied in place instead.
    final copy = !tone.glass && !card && !streaming && text.trim().isNotEmpty
        ? Opacity(
            opacity: hovered || focused ? 1 : 0,
            child: IgnorePointer(
              ignoring: !hovered && !focused,
              child: CopyButton(
                key: ValueKey('copy-${m.messageId}'),
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
    final bubble = content == null || card
        ? content
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: tone.bubble,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(_bubbleRadius),
              ),
            ),
            child: content,
          );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?name,
        if (bubble != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: bubble,
                ),
              ),
              if (copy != null) ...[const SizedBox(width: 4), copy],
            ],
          ),
        ...attachments,
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        top: continued || compact ? 3 : 12,
        right: tone.glass ? 28 : 8,
      ),
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
      constraints: BoxConstraints.tightFor(
        width: context.tone.glass ? 48 : 28,
        height: context.tone.glass ? 48 : 26,
      ),
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
  final ChatMessage message;
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
    final question = widget.message.kind == 'question';
    try {
      await widget.client.continueAction(
        question ? 'questions.respond' : 'approvals.respond',
        {
          'messageId': widget.message.messageId,
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
        data = object(m.content),
        question = m.kind == 'question',
        pending = m.status == 'streaming' && sent == null,
        multi = data['multiSelect'] == true,
        open = sending == null,
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
      // Keep the original approval and its answer available in the chat.
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
              label: [
                pending
                    ? c.tr('等你确认', 'Needs your OK')
                    : answered == null
                    ? c.tr('未回答', 'Not answered')
                    : label(answered),
                command,
              ],
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
                decoration: ShapeDecoration(
                  color: tone.bubble,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                      OutlinedButton(
                        key: ValueKey('choice-${m.messageId}-$index'),
                        style: optionStyle(context),
                        onPressed: !open ? null : () => respond('$choice'),
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
                key: ValueKey('choice-${m.messageId}-$index'),
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
                  key: ValueKey('answer-${m.messageId}'),
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
