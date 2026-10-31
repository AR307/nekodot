import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../ui/design.dart';

class NodeUpdateNotice extends StatefulWidget {
  final NekodotClient client;
  final String command;
  const NodeUpdateNotice({
    super.key,
    required this.client,
    required this.command,
  });

  @override
  State<NodeUpdateNotice> createState() => _NodeUpdateNoticeState();
}

class _NodeUpdateNoticeState extends State<NodeUpdateNotice> {
  bool copied = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.client.tr('这台电脑需要更新一次', 'This computer needs one update'),
            ),
            const SizedBox(height: 8),
            SelectableText(
              widget.command,
              style: const TextStyle(
                fontFamily: monoFont,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconAction(
                tooltip: widget.client.tr(
                  copied ? '已复制' : '复制命令',
                  copied ? 'Copied' : 'Copy command',
                ),
                icon: copied ? Icons.check : Icons.copy_outlined,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.command));
                  if (mounted) setState(() => copied = true);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
