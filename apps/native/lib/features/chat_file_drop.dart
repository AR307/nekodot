import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../ui/design.dart';

/// The visible chat is one drop target. It copies files into the normal draft;
/// dragging text or a directory does not attach it or send a message.
class ChatFileDrop extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Future<void> Function(List<DropItemFile>) onFiles;
  const ChatFileDrop({
    super.key,
    required this.child,
    required this.onFiles,
    this.enabled = true,
  });

  @override
  State<ChatFileDrop> createState() => _ChatFileDropState();
}

class _ChatFileDropState extends State<ChatFileDrop> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && (ModalRoute.isCurrentOf(context) ?? true);
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => setState(() => hovering = true),
      onDragExited: (_) => setState(() => hovering = false),
      onDragDone: (details) async {
        setState(() => hovering = false);
        if (enabled) {
          await widget.onFiles(
            details.files.whereType<DropItemFile>().toList(),
          );
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (enabled && hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('chat-drop-highlight'),
                  decoration: ShapeDecoration(
                    color: context.tone.base.withValues(alpha: .88),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: context.tone.ink3, width: .5),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: ShapeDecoration(
                        color: context.tone.raised,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Icon(
                        Symbols.add,
                        size: 28,
                        color: context.tone.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
