import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'connector_icon.dart';

/// A connector operation stays in the chat; decisions use the native approval.
class ConnectorApprovalCard extends StatefulWidget {
  final NekodotClient client;
  final Json? bot;
  final Json details;
  final bool pending, denied, unanswered;
  final String? sending;
  final List<String> choices;
  final String result, error;
  final Future<void> Function(String) onRespond;
  final Widget? retry;
  const ConnectorApprovalCard({
    super.key,
    required this.client,
    required this.bot,
    required this.details,
    required this.pending,
    required this.sending,
    required this.choices,
    required this.result,
    required this.denied,
    required this.unanswered,
    required this.onRespond,
    required this.error,
    this.retry,
  });

  @override
  State<ConnectorApprovalCard> createState() => _ConnectorApprovalCardState();
}

class _ConnectorApprovalCardState extends State<ConnectorApprovalCard> {
  bool expanded = false;
  bool unfolded = false;

  @override
  void didUpdateWidget(ConnectorApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.sending == null && widget.sending != null) ||
        (oldWidget.pending && !widget.pending)) {
      unfolded = false;
      expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client, data = widget.details;
    final service = object(data['service']);
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final sending = widget.pending && widget.sending != null;
    final choosing = widget.pending && !sending;
    final showDetails = choosing ? expanded : unfolded;
    final sendingLabel = switch (widget.sending) {
      'once' => c.tr('允许一次', 'Allow once'),
      'always' => c.tr('总是允许', 'Always allow'),
      'deny' => c.tr('拒绝', 'Deny'),
      _ => widget.result,
    };
    final height = DesktopHost.supported ? 36.0 : 48.0;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final titleStyle = text.bodyMedium?.copyWith(
      fontWeight: Theme.of(context).brightness == Brightness.dark
          ? FontWeight.w500
          : FontWeight.w600,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (choosing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('${data['title']}', style: titleStyle),
          )
        else
          Semantics(
            expanded: unfolded,
            child: Material(
              color: Colors.transparent,
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('connector-approval-summary'),
                onTap: () => setState(() => unfolded = !unfolded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: ConnectorIcon(
                          url: service['icon'] as String?,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data['title']}',
                              maxLines: unfolded ? null : 1,
                              overflow: unfolded ? null : TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  sending
                                      ? Symbols.more_horiz
                                      : widget.unanswered
                                      ? Symbols.remove
                                      : widget.denied
                                      ? Symbols.close
                                      : Symbols.check,
                                  size: 14,
                                  color: tone.ink2,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: sending
                                      ? ShiningText(
                                          text: sendingLabel,
                                          style: text.bodySmall,
                                        )
                                      : Text(
                                          widget.result,
                                          style: text.bodySmall,
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        turns: unfolded ? .5 : 0,
                        duration: motion,
                        child: Icon(
                          Symbols.expand_more,
                          size: 18,
                          color: tone.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (choosing || unfolded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            widget.bot == null
                                ? const CatAvatar(size: 28)
                                : CatAvatar.of(widget.bot!, size: 28),
                            if (widget.bot != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '${widget.bot!['displayName']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Symbols.arrow_forward,
                          size: 16,
                          color: tone.ink3,
                        ),
                      ),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConnectorIcon(
                              url: service['icon'] as String?,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${service['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (choosing)
                  Semantics(
                    expanded: expanded,
                    child: TextButton(
                      key: const ValueKey('connector-approval-details'),
                      style: TextButton.styleFrom(
                        minimumSize: Size(0, height),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: shape,
                        foregroundColor: tone.ink2,
                        textStyle: text.bodySmall,
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed: () => setState(() => expanded = !expanded),
                      child: Row(
                        children: [
                          Expanded(child: Text(c.tr('详细信息', 'Details'))),
                          AnimatedRotation(
                            turns: expanded ? .5 : 0,
                            duration: motion,
                            child: const Icon(Symbols.expand_more, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (showDetails) _ApprovalDetails(details: data),
                if (choosing) ...[
                  const SizedBox(height: 8),
                  Row(
                    spacing: 8,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (choice, label) in [
                        ('once', c.tr('允许', 'Allow')),
                        ('always', c.tr('总是允许', 'Always allow')),
                        ('deny', c.tr('拒绝', 'Deny')),
                      ])
                        Expanded(
                          flex: choice == 'always' ? 4 : 3,
                          child: TextButton(
                            key: ValueKey('connector-approval-$choice'),
                            style: TextButton.styleFrom(
                              minimumSize: Size(0, height),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              backgroundColor: tone.bubble,
                              foregroundColor: tone.ink,
                              textStyle: text.labelLarge,
                              shape: shape,
                              visualDensity: VisualDensity.standard,
                            ),
                            onPressed: widget.choices.contains(choice)
                                ? () => widget.onRespond(choice)
                                : null,
                            child: Text(label, textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (widget.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ErrorNotice(widget.error, action: widget.retry),
          ),
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ChatCard(
          padding: EdgeInsets.zero,
          child: motion == Duration.zero
              ? content
              : AnimatedSize(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// Keep exact provider fields readable, without framing each parameter.
class _ApprovalDetails extends StatelessWidget {
  final Json details;
  const _ApprovalDetails({required this.details});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if ((details['account'] as String?)?.isNotEmpty == true)
                SelectableText('${details['account']}', style: text.bodySmall),
              for (final entry in object(details['arguments']).entries)
                Flex(
                  direction: stacked ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: stacked ? 4 : 16,
                  children: [
                    SizedBox(
                      width: stacked ? null : 80,
                      child: Text(entry.key, style: text.bodySmall),
                    ),
                    Flexible(
                      flex: stacked ? 0 : 1,
                      child: SelectableText(
                        entry.value is String
                            ? entry.value as String
                            : const JsonEncoder.withIndent('  ')
                                  .convert(entry.value),
                        style: text.bodySmall?.copyWith(
                          color: context.tone.ink,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
