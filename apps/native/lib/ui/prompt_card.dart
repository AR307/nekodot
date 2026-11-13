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
    expanded = widget.hasContent || (widget.holdSize && expanded);
    final tone = context.tone;
    final card = Focus(
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: Motion.still(context) ? Duration.zero : Motion.tint,
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: ShapeDecoration(
          color: tone.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(tone.glass ? 28 : Tone.r16),
            side: BorderSide(
              color: focused ? tone.ink3 : tone.line,
              width: Tone.hair,
            ),
          ),
        ),
        child: SizeMotion(
          duration: Motion.fold.duration,
          curve: Motion.fold,
          alignment: Alignment.bottomCenter,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // One line: attach, the field, then what sends. With words in
              // it the field takes the first line and the controls the next.
              // The field keeps its place in the tree either way, so typing
              // is never interrupted by the change.
              return Padding(
                padding: EdgeInsets.fromLTRB(expanded ? 16 : 6, 4, 8, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      if (!expanded) widget.tools,
                      Expanded(
                        child: Flex(
                          direction: expanded ? Axis.vertical : Axis.horizontal,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: expanded ? 0 : 4,
                                  right: 8,
                                ),
                                child: widget.field,
                              ),
                            ),
                            SizedBox(height: expanded ? 4 : 0),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    constraints.maxWidth * (expanded ? 1 : .6),
                              ),
                              child: expanded
                                  ? Row(
                                      children: [
                                        Transform.translate(
                                          offset: const Offset(-10, 0),
                                          child: widget.tools,
                                        ),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: widget.action,
                                          ),
                                        ),
                                      ],
                                    )
                                  : widget.action,
                            ),
                          ],
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
