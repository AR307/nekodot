import 'package:flutter/material.dart';

import 'design.dart';

class PromptCard extends StatefulWidget {
  final Widget field, tools, action;
  final bool hasContent, running;
  final bool holdSize;
  const PromptCard({
    super.key,
    required this.field,
    required this.tools,
    required this.action,
    required this.hasContent,
    required this.running,
    this.holdSize = false,
  });
  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  bool focused = false, expanded = false;
  @override
  Widget build(BuildContext context) {
    // Moving focus from the input to selected chat text must not move the
    // words under the pointer by collapsing the composer mid-selection.
    expanded =
        widget.hasContent || widget.running || (widget.holdSize && expanded);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final card = Focus(
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: ShapeDecoration(
          color: context.tone.surface,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: focused ? context.tone.ink3 : context.tone.line,
              width: .5,
            ),
          ),
        ),
        child: SizeMotion(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final toolbar = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.tools,
                  Flexible(child: widget.action),
                ],
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Flex(
                    direction: expanded ? Axis.vertical : Axis.horizontal,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: widget.field,
                        ),
                      ),
                      SizedBox(height: expanded ? 4 : 0),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * (expanded ? 1 : .6),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: expanded ? null : 1,
                          heightFactor: 1,
                          child: toolbar,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    // Toolbar presses belong to the field, so mouse-down must not unfocus it
    // and remove the expanded controls before their click can complete.
    return TextFieldTapRegion(child: card);
  }
}
