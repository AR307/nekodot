import 'package:flutter/material.dart';

import 'design.dart';

@immutable
class AIApprovalOption {
  final String id, label;
  final String? detail, resultLabel;
  final bool destructive;
  const AIApprovalOption({
    required this.id,
    required this.label,
    this.detail,
    this.resultLabel,
    this.destructive = false,
  });
}

/// Shared by private and group chats. A choice is final only after submission
/// succeeds; server updates can resolve a card at any time.
class AIApproval extends StatefulWidget {
  final String question;
  final List<AIApprovalOption> options;
  final String? resolvedId, resolvedLabel;
  final bool disabled;
  final Widget? child;
  final Future<void> Function(AIApprovalOption)? onDecide;
  const AIApproval({
    super.key,
    required this.question,
    required this.options,
    this.resolvedId,
    this.resolvedLabel,
    this.disabled = false,
    this.child,
    this.onDecide,
  });

  @override
  State<AIApproval> createState() => _AIApprovalState();
}

class _AIApprovalState extends State<AIApproval> {
  String? submittedId, busyId, error;
  bool get resolved =>
      widget.resolvedId != null ||
      widget.resolvedLabel != null ||
      submittedId != null;

  Future<void> decide(AIApprovalOption option) async {
    if (widget.disabled || resolved || busyId != null) {
      return;
    }
    setState(() {
      busyId = option.id;
      error = null;
    });
    try {
      await widget.onDecide?.call(option);
      if (mounted) setState(() => submittedId = option.id);
    } catch (reason) {
      if (mounted) setState(() => error = '$reason');
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    final chosenId = widget.resolvedId ?? submittedId;
    AIApprovalOption? chosen;
    for (final option in widget.options) {
      if (option.id == chosenId) chosen = option;
    }
    final resultColor = chosen?.destructive == true
        ? tone.danger
        : chosen != null
        ? tone.base
        : tone.ink2;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.surface,
        border: Border.all(color: tone.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            widget.question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tone.ink,
            ),
          ),
          if (widget.child != null) ...[
            const SizedBox(height: 4),
            DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, height: 1.6, color: tone.ink2),
              child: widget.child!,
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSize(
            duration: duration,
            alignment: Alignment.topCenter,
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: duration,
              child: resolved
                  ? Semantics(
                      key: const ValueKey('resolved'),
                      liveRegion: true,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: chosen?.destructive == true
                              ? tone.danger.withValues(alpha: .1)
                              : chosen != null
                              ? tone.ink
                              : tone.bubble,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              chosen != null ? Icons.check : Icons.close,
                              size: 16,
                              color: resultColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.resolvedLabel ??
                                        chosen?.resultLabel ??
                                        chosen?.label ??
                                        '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: resultColor,
                                    ),
                                  ),
                                  if (chosen?.detail != null)
                                    Text(
                                      chosen!.detail!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: resultColor.withValues(
                                          alpha: .75,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      key: const ValueKey('options'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, option)
                            in widget.options.indexed) ...[
                          if (index > 0) const SizedBox(height: 6),
                          OutlinedButton(
                            onPressed: widget.disabled || busyId != null
                                ? null
                                : () => decide(option),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: option.destructive
                                  ? tone.danger
                                  : tone.ink,
                              side: BorderSide(
                                color: option.destructive
                                    ? tone.danger.withValues(alpha: .3)
                                    : tone.line,
                              ),
                              minimumSize: const Size.fromHeight(44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(option.label),
                                      if (option.detail != null)
                                        Text(
                                          option.detail!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: tone.ink2,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (busyId == option.id)
                                  const SizedBox.square(
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (error != null && !resolved) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: tone.danger, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
