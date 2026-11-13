import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../ui/design.dart';

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
  final void Function(String words, String? taskId) onQuote;
  final ValueChanged<bool>? onFocusChanged;

  /// What stands under the latest message and scrolls with the conversation.
  final Widget? footer;

  /// Whether a message arrived while the page was open and has not been shown
  /// yet; such a message enters with a short motion.
  final bool Function(ChatMessage message) fresh;

  /// The first message the page opened with. From it on, the conversation is
  /// laid out downward, so nothing that arrives pushes up what is above;
  /// older messages loaded later go above it. Null until messages are shown.
  final int? since;
  const ChatTimeline({
    this.onFocusChanged,
    this.footer,
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
  static const _earlier = ValueKey('chat-earlier');
  @override
  Widget build(BuildContext context) {
    final c = client,
        id = conversationId,
        messages = view.messages,
        members = view.members,
        group = view.group,
        working = view.working,
        cut = since;
    // Loading older messages must not move the current reading position.
    final earlier = [
      for (final m in messages)
        if (cut != null && m.seq < cut) m,
    ];
    final current = [
      for (final m in messages)
        if (cut == null || m.seq >= cut) m,
    ];
    final items = [...earlier, ...current];
    // The bar floats over the top and the composer over the bottom.
    final head = MediaQuery.paddingOf(context).top + 6,
        bottom = composerHeight + 2;

    Widget entry(int at) {
      final m = items[at],
          previous = at == 0 ? null : items[at - 1],
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
                  key: m.messageId == focusedMessage ? focusedKey : null,
                  child: MessageTile(
                    client: c,
                    message: m,
                    bot: author,
                    showName: group != null,
                    working: working && at == items.length - 1,
                    continued:
                        !apart &&
                        previous.kind != 'system' &&
                        previous.author.id == m.author.id &&
                        previous.author.type == m.author.type,
                    onRetry: onRetry,
                    onQuote: (words) => onQuote(words, m.taskId),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                      (context, index) => index == current.length
                          ? footer!
                          : entry(earlier.length + index),
                      childCount: current.length + (footer == null ? 0 : 1),
                      findChildIndexCallback: (key) {
                        final index = current.indexWhere(
                          (item) => ValueKey(item.messageId) == key,
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
                          (item) => ValueKey(item.messageId) == key,
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
        if (!height.isFinite || height <= 0) return list;
        final bottomEnd = ((height - composerHeight) / height).clamp(0.0, 1.0);
        final bottomStart = ((height - composerHeight - 12) / height).clamp(
          0.0,
          bottomEnd,
        );
        // History stays clear of the fixed activity line and floating input.
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              top == 0 ? Colors.black : Colors.transparent,
              top == 0 ? Colors.black : Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [
              0,
              ((top - 24) / height).clamp(0.0, bottomStart),
              ((top + 8) / height).clamp(0.0, bottomStart),
              bottomStart,
              bottomEnd,
              1,
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
