import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

/// The sandbox a Dot set up and works in: its commands, files, browser and
/// screen run there. Nothing shows while it works on its own computer.
class WorkplaceTile extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const WorkplaceTile({super.key, required this.client, required this.botId});
  @override
  State<WorkplaceTile> createState() => _WorkplaceTileState();
}

class _WorkplaceTileState extends State<WorkplaceTile> {
  NekodotClient get c => widget.client;
  Json? workplace;
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool home = false}) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.rpc('bots.workplace', {
        'botId': widget.botId,
        if (home) 'home': true,
      });
      if (!mounted) return;
      final value = result['workplace'];
      setState(() => workplace = value == null ? null : object(value));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = workplace;
    if (place == null) return ErrorNotice(error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('bot-workplace'),
          leading: const Icon(Symbols.cloud),
          title: Text(c.tr('在沙箱里干活', 'Works in a sandbox')),
          subtitle: Text('${place['label']}'),
          trailing: TextButton(
            key: const ValueKey('bot-workplace-home'),
            onPressed: busy ? null : () => load(home: true),
            child: Text(c.tr('回到它的电脑', 'Back to its computer')),
          ),
        ),
        ErrorNotice(error),
      ],
    );
  }
}
