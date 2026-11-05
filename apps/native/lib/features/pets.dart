import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class PetsPage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final String? hatchPrompt;
  const PetsPage({
    super.key,
    required this.client,
    required this.botId,
    this.hatchPrompt,
  });
  @override
  State<PetsPage> createState() => _PetsPageState();
}

class _PetsPageState extends State<PetsPage> {
  late final prompt = TextEditingController(text: widget.hatchPrompt ?? '');
  final name = TextEditingController();
  Json? operation, generated;
  String error = '', provider = '';
  int revision = 0;
  bool get busy => operation?['status'] == 'running';
  @override
  void dispose() {
    prompt.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> action(String action, [Json params = const {}]) async {
    setState(() => error = '');
    try {
      var op = await widget.client.rpc('pets.manage', {
        'botId': widget.botId,
        'action': action,
        ...params,
      });
      if (!mounted) return;
      setState(() => operation = op);
      while (op['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        op = await widget.client.rpc('operations.get', {
          'operationId': op['operationId'],
        });
        if (mounted) setState(() => operation = op);
      }
      if (op['status'] != 'done') throw RelayError('${op['detail']}');
      if (!mounted) return;
      setState(() {
        if (action == 'generate') {
          generated = Map<String, dynamic>.from(
            objects(op['results']).first['native'],
          );
        }
        if (action == 'hatch') generated = null;
        revision++;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('Hermes 宠物', 'Hermes pets'),
    body: AsyncPane(
      key: ValueKey(revision),
      load: () => widget.client.rpc('pets.list', {'botId': widget.botId}),
      builder: (context, data, reload) {
        final pets = objects(data['pets']);
        final generation = data['generation'] as Map;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.client.tr(
                '此 Bot 的原生宠物目录、选择与生成。不会替换 Bot 头像。',
                'Native pet gallery, selection and generation for this Bot. This does not replace its Bot avatar.',
              ),
            ),
            if (error.isNotEmpty) ErrorNotice(error),
            if (busy) ...[const ShiningText(), Text('${operation?['detail']}')],
            if (data['enabled'] == true)
              ListTile(
                title: Text('${data['active']}'),
                subtitle: Text(widget.client.tr('当前启用', 'Currently enabled')),
                trailing: TextButton(
                  onPressed: busy ? null : () => action('disable'),
                  child: Text(widget.client.tr('停用', 'Disable')),
                ),
              ),
            ExpansionTile(
              title: Text(widget.client.tr('生成新宠物', 'Hatch a pet')),
              initiallyExpanded: widget.hatchPrompt != null,
              children: [
                if (generation['available'] != true)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.client.tr(
                        'Hermes 当前未配置可生成宠物的图像服务。请先在该 Bot 的原生设置中配置。',
                        'Hermes has no reference-capable image provider configured. Configure this Bot’s native image provider first.',
                      ),
                    ),
                  ),
                TextField(
                  controller: prompt,
                  decoration: InputDecoration(
                    labelText: widget.client.tr('描述', 'Description'),
                  ),
                  minLines: 2,
                  maxLines: 5,
                ),
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: widget.client.tr('宠物名称', 'Pet name'),
                  ),
                ),
                if (objects(generation['providers']).isNotEmpty)
                  MenuSelect<String>(
                    value: provider.isEmpty ? null : provider,
                    label: widget.client.tr('图像服务', 'Image provider'),
                    options: [
                      for (final row in objects(generation['providers']))
                        (
                          '${row['id'] ?? row['name']}',
                          '${row['label'] ?? row['name'] ?? row['id']}',
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() => provider = value),
                  ),
                FilledButton(
                  onPressed: busy || generation['available'] != true
                      ? null
                      : () => action('generate', {
                          'prompt': prompt.text,
                          'count': 2,
                          if (provider.isNotEmpty) 'provider': provider,
                        }),
                  child: Text(widget.client.tr('生成候选', 'Generate drafts')),
                ),
                if (generated != null)
                  for (final draft in objects(generated!['drafts']))
                    ListTile(
                      leading: Image.memory(
                        base64Decode('${draft['dataUri']}'.split(',').last),
                        width: 64,
                        height: 64,
                      ),
                      title: Text(
                        widget.client.tr(
                          '候选 ${draft['index']}',
                          'Draft ${draft['index']}',
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => action('hatch', {
                                'token': generated!['token'],
                                'index': draft['index'],
                                'name': name.text,
                                'prompt': prompt.text,
                                if (provider.isNotEmpty) 'provider': provider,
                              }),
                        child: Text(widget.client.tr('孵化', 'Hatch')),
                      ),
                    ),
              ],
            ),
            for (final pet in pets)
              ListTile(
                key: ValueKey('pet-${pet['slug']}'),
                leading: _PetThumbnail(
                  client: widget.client,
                  botId: widget.botId,
                  pet: pet,
                ),
                title: Text('${pet['displayName']}'),
                subtitle: Text(
                  '${pet['slug']} · ${pet['installed'] == true ? widget.client.tr('已安装', 'Installed') : widget.client.tr('原生目录', 'Native catalog')}',
                ),
                trailing: TextButton(
                  onPressed: busy
                      ? null
                      : () => action('select', {'slug': pet['slug']}),
                  child: Text(widget.client.tr('选择', 'Select')),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _PetThumbnail extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Json pet;
  const _PetThumbnail({
    required this.client,
    required this.botId,
    required this.pet,
  });
  @override
  State<_PetThumbnail> createState() => _PetThumbnailState();
}

class _PetThumbnailState extends State<_PetThumbnail> {
  late final image = widget.client.rpc('pets.thumbnail', {
    'botId': widget.botId,
    'slug': widget.pet['slug'],
    'url': widget.pet['spritesheetUrl'] ?? '',
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: image,
    builder: (context, snapshot) {
      final uri = snapshot.data?['dataUri'];
      return uri is String
          ? Image.memory(
              base64Decode(uri.split(',').last),
              width: 48,
              height: 48,
              fit: BoxFit.contain,
            )
          : const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.pets_outlined),
            );
    },
  );
}
