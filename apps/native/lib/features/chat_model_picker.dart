import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

/// The Bot's models on the menu card at [anchor]: its own model and its
/// source's catalog, then a row for the Bot's model settings. Gives the model
/// picked, an empty string for the settings, or null when dismissed.
Future<String?> pickChatModel(
  BuildContext anchor,
  NekodotClient c,
  Json bot,
) async {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
    Offset.zero & overlay.size,
  );
  final source = bot['sourceId'];
  final current = '${bot['model'] ?? ''}';
  final listed = source == null
      ? const <String>[]
      : ((await c.rpc('models.options', {'sourceId': source}))['models']
                as List)
            .cast<String>();
  if (!anchor.mounted) return null;
  final models = <String>{current, ...listed}..remove('');
  return showMenu<String>(
    context: anchor,
    position: position,
    constraints: menuConstraints,
    initialValue: current,
    items: [
      for (final model in models)
        menuItem(
          anchor,
          key: ValueKey('model-$model'),
          value: model,
          icon: Icons.memory_outlined,
          label: model,
          trailing: model == current ? const Icon(Icons.check) : null,
        ),
      menuDivider,
      menuItem(
        anchor,
        key: const ValueKey('model-settings'),
        value: '',
        icon: Icons.tune,
        label: c.tr('Bot 模型设置', 'Bot model settings'),
      ),
    ],
  );
}
