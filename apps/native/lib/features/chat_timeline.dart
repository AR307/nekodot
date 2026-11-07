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
  final ValueChanged<String> onRetry, onError, onQuote;
  final ValueChanged<bool>? onFocusChanged;

  /// Whether a message arrived while the page was open and has not been shown
  /// yet; such a message enters with a short motion.
  final bool Function(ChatMessage message) fresh;

  /// The first message the page opened with. From it on, the conversation is
  /// laid out downward, so nothing that arrives pushes up what is above;
  /// older messages loaded later go above it. Null until messages are shown.
  final int? since;
  const ChatTimeline({
    this.onFocusChanged,
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
    required this.onQuote,
    required this.fresh,
    required this.since,
  });

  /// A pause this long between two messages puts the time between them.
  static const pause = Duration(minutes: 30);
  static const _earlier = ValueKey('chat-earlier'),
      _thinking = ValueKey('chat-thinking');
  @override
  Widget build(BuildContext context) {
    final c = client,
        id = conversationId,
        messages = view.messages,
        members = view.members,
        bot = view.bot,
        group = view.group,
        working = view.working,
        cut = since;
    // Steps do not fold across the two runs, so loading older messages never
    // changes the size of what is already shown.
    final earlier = groupMessages([
      for (final m in messages)
        if (cut != null && m.seq < cut) m,
    ]);
    final current = groupMessages([
      for (final m in messages)
        if (cut == null || m.seq >= cut) m,
    ]);
    final items = [...earlier, ...current];
    final thinking = view.thinking && messages.isNotEmpty;
    // The bar floats over the top and the composer over the bottom.
    final head = MediaQuery.paddingOf(context).top + 6,
        bottom = composerHeight + 2;

    Widget entry(int at) {
      final item = items[at],
          m = item.first,
          previous = at == 0 ? null : items[at - 1].last,
          author = members.where((b) => b['botId'] == m.author.id).firstOrNull,
          at0 = DateTime.parse(m.createdAt).toLocal(),
          apart =
              previous == null ||
              at0.difference(DateTime.parse(previous.createdAt).toLocal()) >=
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
                    working: working && at == items.length - 1,
                    continued:
                        !apart &&
                        previous.kind != 'system' &&
                        previous.author.id == m.author.id &&
                        previous.author.type == m.author.type,
                    onRetry: onRetry,
                    onQuote: onQuote,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final thinkingRow = Align(
      key: _thinking,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: EntryMotion(
          play: true,
          child: ThinkingRow(
            key: const ValueKey('thinking-row'),
            bot: bot,
            line: workingLine(c, '${bot?['displayName'] ?? 'Bot'}', view.turn),
          ),
        ),
      ),
    );
    final more = (c.node.messages[id]?.length ?? 0) < 50
        ? const SizedBox.shrink()
        : Center(
            child: IconButton(
              tooltip: c.tr('加载更早消息', 'Load earlier messages'),
              onPressed: () async {
                try {
                  await c.loadMessages(id, before: messages.first.seq);
                } catch (e) {
                  onError('$e');
                }
              },
              icon: const Icon(Icons.expand_less),
            ),
          );
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight;
        final list = PrimaryScrollController(
          controller: scroll,
          child: Focus(
            key: const ValueKey('chat-history-focus'),
            onFocusChange: onFocusChanged,
            child: CustomScrollView(
              key: const ValueKey('chat-messages'),
              controller: scroll,
              reverse: true,
              center: _earlier,
              // In a reversed viewport the center belongs at the bottom.
              // Keeping it at the top leaves reopened history above the bar.
              anchor: 0,
              slivers: [
                // From the first line the page opened with, downward.
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, bottom),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => index < current.length
                          ? entry(earlier.length + index)
                          : thinkingRow,
                      childCount: current.length + (thinking ? 1 : 0),
                      findChildIndexCallback: (key) {
                        if (key == _thinking) return current.length;
                        final index = current.indexWhere(
                          (item) => ValueKey(item.first.messageId) == key,
                        );
                        return index < 0 ? null : index;
                      },
                    ),
                  ),
                ),
                // Older lines loaded later, upward; the oldest can scroll
                // clear of the bar.
                SliverPadding(
                  key: _earlier,
                  padding: EdgeInsets.fromLTRB(14, head, 14, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => index < earlier.length
                          ? entry(earlier.length - 1 - index)
                          : more,
                      childCount: earlier.length + 1,
                      findChildIndexCallback: (key) {
                        final index = earlier.indexWhere(
                          (item) => ValueKey(item.first.messageId) == key,
                        );
                        return index < 0 ? null : earlier.length - 1 - index;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        final top = head - 6;
        if (top == 0 || !height.isFinite || height <= top) return list;
        // Lines fade out as they pass under the floating bar, so nothing shows
        // around its pills.
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

/// Holds a conversation at its latest line while you are near it, so what is
/// added below stays in view; once you scroll further up, nothing moves under
/// you.
class LatestScrollController extends ScrollController {
  /// How close to the latest line still counts as being at it.
  static const near = 64.0;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _LatestPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _LatestPosition extends ScrollPositionWithSingleContext {
  _LatestPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  /// Near the latest line as of the last scroll; a conversation opens there.
  bool following = true;

  @override
  void didUpdateScrollPositionBy(double delta) {
    following =
        !hasContentDimensions ||
        pixels - minScrollExtent <= LatestScrollController.near;
    super.didUpdateScrollPositionBy(delta);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!following ||
        activity!.isScrolling ||
        (pixels - minScrollExtent).abs() < 1) {
      return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
    }
    // Lines changed below the latest one: follow them within this layout, so
    // no frame shows the old place.
    correctPixels(minScrollExtent);
    super.applyContentDimensions(minScrollExtent, maxScrollExtent);
    return false;
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
