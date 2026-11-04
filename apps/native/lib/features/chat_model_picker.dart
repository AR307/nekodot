import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

Future<String?> pickChatModel(
  BuildContext context,
  NekodotClient client,
  Json bot,
) {
  final source = bot['sourceId'];
  final catalog = source == null
      ? Future<Json>.value({'models': <String>[]})
      : client.rpc('models.options', {'sourceId': source});
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(client.tr('选择模型', 'Choose model')),
      children: [
        SizedBox(
          width: 320,
          child: FutureBuilder<Json>(
            future: catalog,
            builder: (context, snapshot) {
              final models = <String>{
                '${bot['model'] ?? ''}',
                ...((snapshot.data?['models'] as List?) ?? []).cast<String>(),
              }..remove('');
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const ShiningText(),
                  if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${snapshot.error}',
                        style: TextStyle(color: context.tone.danger),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final model in models)
                          ListTile(
                            title: Text(model),
                            trailing: model == bot['model']
                                ? const Icon(Icons.check, size: 18)
                                : null,
                            onTap: () => Navigator.pop(context, model),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(client.tr('Bot 模型设置', 'Bot model settings')),
        ),
      ],
    ),
  );
}
