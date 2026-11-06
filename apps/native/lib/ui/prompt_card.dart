import 'package:flutter/material.dart';

import 'design.dart';

class PromptCard extends StatefulWidget {
  final Widget field, tools, action;
  final bool hasContent, running;
  const PromptCard({
    super.key,
    required this.field,
    required this.tools,
    required this.action,
    required this.hasContent,
    required this.running,
  });
  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final expanded = focused || widget.hasContent || widget.running;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    final card = Focus(
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(maxWidth: expanded ? 480 : 320),
        decoration: BoxDecoration(
          color: context.tone.surface,
          border: Border.all(
            color: focused ? context.tone.ink3 : context.tone.line,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizeMotion(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: expanded ? 68 : 46),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        expanded ? 16 : 96,
                        8,
                      ),
                      child: widget.field,
                    ),
                  ),
                  if (expanded) const SizedBox(height: 44),
                ],
              ),
              Positioned(
                left: expanded ? 8 : null,
                right: 7,
                bottom: 7,
                child: Row(
                  children: [
                    if (expanded) const Spacer(),
                    widget.tools,
                    widget.action,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Toolbar presses belong to the field, so mouse-down must not unfocus it
    // and remove the expanded controls before their click can complete.
    return TextFieldTapRegion(child: card);
  }
}
