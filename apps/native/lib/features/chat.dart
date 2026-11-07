import 'dart:async';

import 'package:flutter/material.dart';

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
  final scroll = ScrollController();
  final composer = GlobalKey<ChatComposerState>();
  double composerHeight = 76;
  String? focusedMessage;
  final focusedKey = GlobalKey();
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
    unawaited(
      c.loadMessages(id).catchError((Object e) {
        if (mounted) composer.currentState?.showError('$e');
      }),
    );
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
      final glassHeader = AppBar(
        flexibleSpace: const Frost(),
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 12 : 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: c.tr('详情', 'Details'),
            child: InkWell(
              customBorder: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
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
                                  ChainDots(count: chain.count, max: chain.max),
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
                    shape: const RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    shadows: tone.rest,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      customBorder: const RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
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
                              ChainDots(count: chain.count, max: chain.max),
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
                      if (scroll.hasClients) scroll.jumpTo(0);
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
