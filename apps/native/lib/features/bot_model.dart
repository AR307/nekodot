import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'model_selection.dart';

class BotModelPage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const BotModelPage({super.key, required this.client, required this.botId});
  @override
  State<BotModelPage> createState() => _BotModelPageState();
}

class _BotModelPageState extends State<BotModelPage> {
  final contextLength = TextEditingController();
  String? source;
  String model = '', error = '';
  bool busy = false;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    final bot = c.node.bots.firstWhere((b) => b['botId'] == widget.botId);
    source = bot['sourceId'] as String?;
    model = '${bot['model']}';
    contextLength.text = '${bot['modelSettings']?['contextLength'] ?? ''}';
  }

  @override
  void dispose() {
    contextLength.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (source == null || model.isEmpty) {
        throw RelayError(c.tr('请选择模型', 'Choose a model'));
      }
      final value = contextLength.text.trim();
      final length = value.isEmpty ? null : int.tryParse(value);
      if (value.isNotEmpty && (length == null || length <= 0)) {
        throw RelayError(c.tr('请输入正整数', 'Enter a positive integer'));
      }
      await c.rpc('bots.update', {
        'botId': widget.botId,
        'sourceId': source,
        'model': model,
        'modelSettings': {'contextLength': length},
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: c.tr('模型与压缩', 'Model & compression'),
    body: PageList(
      children: [
        ModelSelection(
          client: c,
          sourceId: source,
          model: model,
          enabled: !busy,
          onChanged: (id, value) => setState(() {
            source = id;
            model = value;
          }),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: c.tr('最大上下文', 'Maximum context'),
          child: TextField(
            key: const ValueKey('model-context-length'),
            controller: contextLength,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: c.tr('自动', 'Automatic')),
          ),
        ),
        ErrorNotice(error),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('save-bot-model'),
          onPressed: busy || model.isEmpty ? null : save,
          child: Text(c.tr('保存', 'Save')),
        ),
      ],
    ),
  );
}
