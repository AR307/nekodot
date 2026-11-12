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
    if (oldWidget.pending && !widget.pending) {
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
    final height = DesktopHost.supported ? 36.0 : 48.0;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ChatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.pending)
                Text(
                  '${data['title']}',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                )
              else
                Material(
                  color: Colors.transparent,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('connector-approval-summary'),
                    customBorder: shape,
                    onTap: () => setState(() => unfolded = !unfolded),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height),
                      child: Row(
                        children: [
                          Icon(
                            widget.unanswered
                                ? Icons.remove
                                : widget.denied
                                ? Icons.close
                                : Icons.check,
                            size: 16,
                            color: tone.ink2,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${data['title']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(widget.result, style: text.bodySmall),
                          const SizedBox(width: 4),
                          Icon(
                            unfolded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: tone.ink2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.pending || unfolded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            widget.bot == null
                                ? const CatAvatar(size: 36)
                                : CatAvatar.of(widget.bot!, size: 36),
                            if (widget.bot != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${widget.bot!['displayName']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                          color: tone.ink3,
                        ),
                      ),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConnectorIcon(
                              url: service['icon'] as String?,
                              size: 36,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${service['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: shape,
                    onTap: () => setState(() => expanded = !expanded),
                    child: SizedBox(
                      height: height,
                      child: Row(
                        children: [
                          Text(c.tr('详细信息', 'Details'), style: text.bodySmall),
                          const SizedBox(width: 4),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: tone.ink2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ('${data['account']}'.isNotEmpty)
                          SelectableText(
                            '${data['account']}',
                            style: text.bodySmall,
                          ),
                        for (final entry in object(data['arguments']).entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.key,
                                    style: text.bodySmall?.copyWith(
                                      color: tone.ink2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 5,
                                  child: SelectableText(
                                    entry.value is String
                                        ? entry.value as String
                                        : const JsonEncoder.withIndent('  ')
                                              .convert(entry.value),
                                    style: text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (widget.pending)
                  Row(
                    children: [
                      for (final (choice, label) in [
                        ('once', c.tr('允许', 'Allow')),
                        ('always', c.tr('总是允许', 'Always allow')),
                        ('deny', c.tr('拒绝', 'Deny')),
                      ])
                        Expanded(
                          child: Align(
                            alignment: choice == 'once'
                                ? Alignment.centerLeft
                                : choice == 'deny'
                                ? Alignment.centerRight
                                : Alignment.center,
                            child: TextButton(
                              key: ValueKey('connector-approval-$choice'),
                              style: TextButton.styleFrom(
                                minimumSize: Size(0, height),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: shape,
                              ),
                              onPressed:
                                  widget.sending == null &&
                                      widget.choices.contains(choice)
                                  ? () => widget.onRespond(choice)
                                  : null,
                              child: widget.sending == choice
                                  ? ShiningText(text: label)
                                  : Text(label),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
              ErrorNotice(widget.error, action: widget.retry),
            ],
          ),
        ),
      ),
    );
  }
}
