import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'work.dart';

import 'chat_presentation.dart';
import 'chat_message.dart';
import 'time_labels.dart';

class ChatTimeline extends StatelessWidget {
  final NekodotClient client;
  final String conversationId;
  final ChatPresentation view;
  final ScrollController scroll;
  final double composerHeight;
  final String? focusedMessage;
  final GlobalKey focusedKey;
  final ValueChanged<String> onRetry, onError;

  /// Whether a message arrived while the page was open and has not been shown
  /// yet; such a message enters with a short motion.
  final bool Function(ChatMessage message) fresh;
  const ChatTimeline({
    super.key,
    required this.client,
    required this.conversationId,
    required this.view,
    required this.scroll,
    required this.composerHeight,
    required this.focusedMessage,
    required this.focusedKey,
    required this.onRetry,
    required this.onError,
    required this.fresh,
  });

  /// A pause this long between two messages puts the time between them.
  static const pause = Duration(minutes: 30);
  @override
  Widget build(BuildContext context) {
    final c = client,
        id = conversationId,
        items = view.items,
        messages = view.messages,
        members = view.members,
        bot = view.bot,
        group = view.group,
        working = view.working;
    final lead = view.thinking && messages.isNotEmpty ? 1 : 0;
    final top = MediaQuery.paddingOf(context).top;
    final list = PrimaryScrollController(
      controller: scroll,
      child: Focus(
        key: const ValueKey('chat-history-focus'),
        child: ListView.builder(
          key: const ValueKey('chat-messages'),
          controller: scroll,
          reverse: true,
          // The bar floats over the top, so the oldest lines can scroll clear
          // of it.
          padding: EdgeInsets.fromLTRB(
            14,
            MediaQuery.paddingOf(context).top + 6,
            14,
            composerHeight + 2,
          ),
          itemCount: items.length + 1 + lead,
          findChildIndexCallback: (key) {
            final index = items.indexWhere(
              (item) => ValueKey(item.first.messageId) == key,
            );
            return index < 0 ? null : items.length - 1 - index + lead;
          },
          itemBuilder: (context, position) {
            if (position < lead) {
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: EntryMotion(
                    play: true,
                    child: ThinkingRow(
                      key: const ValueKey('thinking-row'),
                      bot: bot,
                      line: workingLine(
                        c,
                        '${bot?['displayName'] ?? 'Bot'}',
                        view.turn,
                      ),
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
                              before: messages.first.seq,
                            );
                          } catch (e) {
                            onError('$e');
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
                    .where((b) => b['botId'] == m.author.id)
                    .firstOrNull,
                at0 = DateTime.parse(m.createdAt).toLocal(),
                apart =
                    previous == null ||
                    at0.difference(
                          DateTime.parse(previous.createdAt).toLocal(),
                        ) >=
                        pause;
            return Align(
              key: ValueKey(m.messageId),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (apart)
                      Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 2),
                        child: Text(
                          dividerTime(c, at0),
                          key: ValueKey('divider-${m.messageId}'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.tone.ink3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    EntryMotion(
                      play: fresh(m),
                      own: m.author.type == 'user',
                      child: KeyedSubtree(
                        key: item.any((m) => m.messageId == focusedMessage)
                            ? focusedKey
                            : null,
                        child: MessageTile(
                          client: c,
                          message: m,
                          steps: isWorkGroup(item) ? item : null,
                          // Still going while only its questions follow it.
                          live:
                              working &&
                              items
                                  .skip(at + 1)
                                  .every(
                                    (later) => const {
                                      'approval',
                                      'question',
                                    }.contains(later.first.kind),
                                  ),
                          bot: author,
                          showName: group != null,
                          working: working && index == 0,
                          continued:
                              !apart &&
                              previous.kind != 'system' &&
                              previous.author.id == m.author.id &&
                              previous.author.type == m.author.type,
                          onRetry: onRetry,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (top == 0) return list;
    // Lines fade out as they pass under the floating bar, so nothing shows
    // around its pills.
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight;
        if (!height.isFinite || height <= top) return list;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.transparent,
              Colors.black,
            ],
            stops: [
              0,
              ((top - 24) / height).clamp(0.0, 1.0),
              ((top + 8) / height).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: list,
        );
      },
    );
  }
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
