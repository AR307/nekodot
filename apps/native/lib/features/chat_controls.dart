import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../ui/design.dart';
import 'chat_message.dart';
import 'chat_presentation.dart';

/// Opens what the Dot is waiting on over the chat: a sheet from the bottom on
/// a phone, a centered card on a desktop. With [messageId] it shows that one
/// approval or question, answered or not.
Future<void> openControls(
  BuildContext context,
  NekodotClient client,
  String conversationId, {
  String? messageId,
}) {
  final controls = ChatControls(
    client: client,
    conversationId: conversationId,
    messageId: messageId,
  );
  if (context.tone.glass) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheet).height * .8,
            ),
            child: controls,
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialog).height * .8,
        ),
        child: controls,
      ),
    ),
  );
}

class ChatControls extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final String? messageId;
  const ChatControls({
    super.key,
    required this.client,
    required this.conversationId,
    this.messageId,
  });
  @override
  State<ChatControls> createState() => _ChatControlsState();
}

class _ChatControlsState extends State<ChatControls> {
  NekodotClient get c => widget.client;
  late final node = c.node;
  late final updates = Listenable.merge([
    c,
    node,
    node.conversation(widget.conversationId),
  ]);
  ModalRoute<void>? route;

  @override
  void initState() {
    super.initState();
    updates.addListener(changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    updates.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    // Nothing left to answer: get out of the way. Once it is already leaving,
    // another pop would close the chat underneath instead.
    if (widget.messageId == null && shown.isEmpty) {
      if (route?.isCurrent ?? false) Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  List<ChatMessage> get shown {
    final loaded = node.messages[widget.conversationId] ?? const [];
    return widget.messageId == null
        ? pendingControls(loaded)
        : loaded.where((m) => m.messageId == widget.messageId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cards = shown;
    // A handful at most, so all of them are built and none hides unbuilt
    // below the fold.
    return SingleChildScrollView(
      key: const ValueKey('chat-controls'),
      padding: EdgeInsets.fromLTRB(16, context.tone.glass ? 0 : 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, message) in cards.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            ControlCard(
              key: ValueKey(message.messageId),
              client: c,
              message: message,
            ),
          ],
        ],
      ),
    );
  }
}
