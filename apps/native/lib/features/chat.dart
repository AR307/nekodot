import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_details.dart';
import 'bot_editor.dart';
import 'sessions.dart';
import 'flowchart.dart';

import 'chat_presentation.dart';
import 'chat_timeline.dart';
import 'chat_composer.dart';

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
  final scroll = LatestScrollController();
  final composer = GlobalKey<ChatComposerState>();
  double composerHeight = 76;
  String? focusedMessage;
  final focusedKey = GlobalKey();

  /// Messages newer than [baseline] arrived while the page was open; each
  /// enters with a short motion the first time it is shown.
  int? baseline, seenSeq;
  final shown = <String>{};

  /// Reading further up than the latest messages, and whether more arrived.
  bool away = false, missed = false;

  /// Messages from this sequence on arrived after the page opened; a turn
  /// still under way when it opened counts as arriving.
  int? since;
  NekodotClient get c => widget.client;
  String get id => widget.conversationId;
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
    c.visibleConversation = id;
    scroll.addListener(onScroll);
    unawaited(
      c
          .loadMessages(id)
          .then((_) {
            if (!mounted) return;
            final loaded = c.node.messages[id] ?? const [];
            baseline = loaded.fold<int>(
              0,
              (top, m) => m.seq > top ? m.seq : top,
            );
          })
          .catchError((Object e) {
            if (mounted) composer.currentState?.showError('$e');
          }),
    );
  }

  bool fresh(ChatMessage m) {
    final start = baseline;
    return start != null && m.seq > start && shown.add(m.messageId);
  }

  void onScroll() {
    final position = scroll.position;
    final far =
        position.pixels - position.minScrollExtent >
        LatestScrollController.near;
    if (far != away) {
      setState(() {
        away = far;
        if (!far) missed = false;
      });
    }
  }

  Future<void> toLatest() async {
    if (!scroll.hasClients) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      await scroll.animateTo(
        scroll.position.minScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    // What arrived during the motion lies below where it ended.
    if (mounted &&
        scroll.hasClients &&
        !scroll.position.isScrollingNotifier.value) {
      scroll.jumpTo(scroll.position.minScrollExtent);
    }
  }

  @override
  void dispose() {
    nativeRoutes.unsubscribe(this);
    if (c.visibleConversation == id) c.visibleConversation = null;
    scroll.dispose();
    super.dispose();
  }

  Future<void> focusFlowMessage(String messageId) async {
    await c.loadMessages(id, around: messageId);
    if (!mounted) return;
    setState(() => focusedMessage = messageId);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !scroll.hasClients) return;
    scroll.jumpTo(scroll.position.minScrollExtent);
    await WidgetsBinding.instance.endOfFrame;
    while (mounted &&
        focusedKey.currentContext == null &&
        scroll.offset < scroll.position.maxScrollExtent) {
      await scroll.animateTo(
        (scroll.offset + scroll.position.viewportDimension * .8).clamp(
          scroll.position.minScrollExtent,
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.node, c.node.conversation(id)]),
    builder: (context, child) {
      final conversation = c.node.conversations
          .where((x) => x['conversationId'] == id)
          .firstOrNull;
      if (conversation == null) return const SizedBox.shrink();
      final view = ChatPresentation(
        c.node,
        conversation,
        focus: c.prefs.chatDisplay['focus'] == true,
      );
      final bot = view.bot,
          group = view.group,
          members = view.members,
          title = view.title,
          working = view.working,
          status = view.status(c),
          chain = view.activity.chain,
          memberAvatars = view.memberAvatars,
          messages = view.messages,
          tone = context.tone;
      void openDetails() {
        if (group != null) {
          openPage(
            context,
            BotEditor(client: c, group: true, existing: group),
            form: true,
          );
        } else if (bot != null) {
          if (widget.onDetails != null) {
            widget.onDetails!(bot);
          } else {
            popPage(context, BotDetails(client: c, bot: bot));
          }
        }
      }

      final textTheme = Theme.of(context).textTheme;
      // Floating controls sit on the surface with a soft shadow, over the
      // messages, which scroll beneath them and fade out under the bar.
      Widget floating(Widget child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: tone.surface,
          shape: const StadiumBorder(),
          shadows: tone.rest,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
      final titlePill = Tooltip(
        message: c.tr('详情', 'Details'),
        child: floating(
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: openDetails,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                tone.glass ? 7 : 5,
                14,
                tone.glass ? 7 : 5,
              ),
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
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: tone.glass ? 15 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (chain != null) ...[
                    const SizedBox(width: 8),
                    ChainDots(count: chain.count, max: chain.max),
                  ],
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      final actions = floating(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
        ),
      );
      final header = AppBar(
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tone.base,
                tone.base.withValues(alpha: .8),
                tone.base.withValues(alpha: 0),
              ],
              stops: const [0, .6, 1],
            ),
          ),
          child: tone.glass ? const SizedBox.expand() : const WindowDrag(),
        ),
        automaticallyImplyLeading: false,
        leadingWidth: widget.embedded ? 0 : 60,
        leading: widget.embedded
            ? null
            : Center(
                child: floating(
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
        centerTitle: true,
        titleSpacing: 8,
        title: titlePill,
        actions: [
          actions,
          const SizedBox(width: 12),
          if (widget.reserveControls)
            SizedBox(width: WindowChrome.reserved(context)),
        ],
      );

      // Something new arrived while you were reading further up.
      final newest = messages.lastOrNull?.seq;
      if (newest != null && newest > (seenSeq ?? newest)) missed = away;
      seenSeq = newest;
      if (since == null && messages.isNotEmpty) {
        final asked = messages.lastIndexWhere((m) => m.author.type == 'user');
        since = working && asked + 1 < messages.length
            ? messages[asked + 1].seq
            : messages.last.seq + 1;
      }
      final still = MediaQuery.disableAnimationsOf(context);
      final asked = messages
          .where(
            (m) =>
                m.author.type == 'user' &&
                '${m.content['text'] ?? ''}'.trim().isNotEmpty,
          )
          .lastOrNull;
      // Without the quoted lines it answers, if it quoted any.
      final lastAsked = asked == null
          ? null
          : '${asked.content['text']}'
                .split('\n')
                .where((line) => !line.startsWith('>'))
                .join(' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
      return Scaffold(
        extendBodyBehindAppBar: true,
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
              ChatTimeline(
                client: c,
                conversationId: id,
                view: view,
                scroll: scroll,
                composerHeight: composerHeight,
                focusedMessage: focusedMessage,
                focusedKey: focusedKey,
                onRetry: (text) => composer.currentState?.editDraft(text),
                onError: (value) => composer.currentState?.showError(value),
                onQuote: (words) => composer.currentState?.quote(words),
                fresh: fresh,
                since: since,
              ),
            // While you read further up, what you last asked stays in sight
            // under the bar; tapping it returns to the latest.
            if (lastAsked != null)
              Builder(
                builder: (context) => Positioned(
                  top: MediaQuery.paddingOf(context).top + 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IgnorePointer(
                      ignoring: !away,
                      child: AnimatedOpacity(
                        opacity: away ? 1 : 0,
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: AnimatedSlide(
                          offset: away ? Offset.zero : const Offset(0, -.3),
                          duration: still
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: AskedPill(text: lastAsked, onTap: toLatest),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: composerHeight + 6,
              child: Center(
                child: IgnorePointer(
                  ignoring: !away,
                  child: AnimatedOpacity(
                    opacity: away ? 1 : 0,
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: AnimatedScale(
                      scale: away ? 1 : .8,
                      duration: still
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: LatestButton(
                        tooltip: c.tr('回到最新', 'Jump to latest'),
                        missed: missed,
                        onPressed: toLatest,
                      ),
                    ),
                  ),
                ),
              ),
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
                child: ChatComposer(
                  key: composer,
                  client: c,
                  conversationId: id,
                  view: view,
                  onSent: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (scroll.hasClients) {
                        scroll.jumpTo(scroll.position.minScrollExtent);
                      }
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Floats above the composer while you read further up; a dot says that
/// something new arrived meanwhile.
class LatestButton extends StatelessWidget {
  final String tooltip;
  final bool missed;
  final VoidCallback onPressed;
  const LatestButton({
    super.key,
    required this.tooltip,
    required this.missed,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tone.surface,
            shape: BoxShape.circle,
            boxShadow: tone.lift,
          ),
          child: IconButton(
            key: const ValueKey('chat-latest'),
            tooltip: tooltip,
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_downward),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: AnimatedScale(
            scale: missed ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: tone.ink,
                shape: BoxShape.circle,
                border: Border.all(color: tone.surface, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What you last asked, as a quiet pill under the bar.
class AskedPill extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const AskedPill({super.key, required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tone.surface,
          shape: const StadiumBorder(),
          shadows: tone.rest,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('chat-asked'),
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.south_rounded, size: 14, color: tone.ink3),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tone.ink2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
