import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/secret_crypto.dart';
import '../ui/design.dart';

String secretState(NekodotClient c, String state) => switch (state) {
  'pending' => c.tr('等待提交', 'Waiting'),
  'delivered' => c.tr('已交付', 'Delivered'),
  'applied' => c.tr('已完成', 'Done'),
  'failed' => c.tr('没有成功，请重新提交', 'Did not work, submit again'),
  'redelivery' => c.tr('需要重新提交', 'Submit again'),
  'cancelled' => c.tr('已取消', 'Cancelled'),
  'expired' => c.tr('已结束', 'Ended'),
  _ => state,
};

/// A Bot asking for one key or password: its name, the field with its submit,
/// and whether the Bot may reuse it. The value is encrypted here for the
/// owning node and never shown in the chat.
class SecretCard extends StatefulWidget {
  final NekodotClient client;
  final Json content;
  const SecretCard({super.key, required this.client, required this.content});
  @override
  State<SecretCard> createState() => _SecretCardState();
}

class _SecretCardState extends State<SecretCard>
    with WidgetsBindingObserver, RouteAware {
  Json? data;
  String error = '';
  bool busy = false, save = false;
  final fields = <String, TextEditingController>{};
  NekodotClient get c => widget.client;
  late final updates = c.node.summaries;
  Json get target => {
    'botId': widget.content['botId'],
    'requestId': widget.content['requestId'],
  };
  static bool open(Object? state) =>
      const ['pending', 'failed', 'redelivery'].contains(state);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(sync);
    updates.addListener(sync);
    if (open(widget.content['state'])) unawaited(load());
  }

  void sync() {
    final current = data;
    if (current == null) return;
    final request = object(current['request']);
    final message = (c.node.messages[request['conversationId']] ?? [])
        .where(
          (m) =>
              m.kind == 'secret' &&
              m.content['requestId'] == target['requestId'],
        )
        .firstOrNull;
    if (message == null) return;
    final content = object(message.content);
    if (!open(content['state'])) clear();
    setState(
      () => data = {
        ...current,
        'request': {...request, ...content},
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) nativeRoutes.subscribe(this, route);
  }

  @override
  void didPushNext() {
    clear();
  }

  @override
  void didUpdateWidget(SecretCard old) {
    super.didUpdateWidget(old);
    if (widget.content['state'] != old.content['state']) {
      if (!open(widget.content['state'])) clear();
      if (open(widget.content['state']) || data != null) unawaited(load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clear();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  /// Typed values never outlive the card's moment on screen.
  void clear() {
    for (final field in fields.values) {
      field.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(sync);
    updates.removeListener(sync);
    nativeRoutes.unsubscribe(this);
    for (final field in fields.values) {
      field
        ..removeListener(changed)
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await c.rpc('secrets.get', target);
      if (!mounted) return;
      for (final field in objects(object(result['request'])['fields'])) {
        fields.putIfAbsent(
          '${field['name']}',
          // The submit button follows whatever is in the field.
          () => TextEditingController()..addListener(changed),
        );
      }
      setState(() {
        data = result;
        error = '';
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> submit({String? savedId}) async {
    if (busy || !c.online) return;
    final request = object(data!['request']);
    final definitions = objects(request['fields']);
    if (savedId == null &&
        fields['${definitions.first['name']}']!.text.isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final payload = savedId != null
          ? {'credentialId': savedId}
          : {
              'envelope': await encryptSecretDelivery(
                nodeId: c.selectedNodeId!,
                botId: '${target['botId']}',
                requestId: '${target['requestId']}',
                publicKey: '${data!['publicKey']}',
                fields: {
                  for (final field in definitions)
                    '${field['name']}': fields['${field['name']}']!.text,
                },
              ),
            };
      await c.rpc('secrets.submit', {...target, ...payload, 'save': save});
      clear();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final request = data == null ? widget.content : object(data!['request']);
    final pending = open(request['state']);
    final definitions = objects(request['fields']);
    final saved = objects(data?['saved']);
    final ready = c.online && !busy;
    final title = Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: tone.ink2),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${request['service']}',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    // Delivered or ended: the name, and how it ended, as an answered question.
    if (!pending) {
      final done = const ['delivered', 'applied'].contains(request['state']);
      return ChatCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  done ? Icons.check : Icons.remove,
                  size: 16,
                  color: tone.ink3,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    secretState(c, '${request['state']}'),
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final Json? field = data == null || definitions.isEmpty
        ? null
        : definitions.first;
    final kind = field?['kind'];
    return ChatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 10),
          if (field == null && error.isEmpty) const ShiningText(),
          if (field != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('secret-field-${field['name']}'),
                    controller: fields['${field['name']}'],
                    enabled: ready,
                    obscureText: kind == 'password' || kind == 'otp',
                    minLines: kind == 'private-key' ? 4 : 1,
                    maxLines: kind == 'private-key' ? 10 : 1,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: kind == 'private-key'
                        ? TextInputType.multiline
                        : TextInputType.visiblePassword,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(hintText: '${field['label']}'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('secret-submit'),
                  style: optionStyle(context),
                  onPressed:
                      ready && fields['${field['name']}']!.text.isNotEmpty
                      ? () => submit()
                      : null,
                  child: Text(c.tr('提交', 'Submit')),
                ),
              ],
            ),
            if (!definitions.any((f) => f['kind'] == 'otp'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  customBorder: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: ready ? () => setState(() => save = !save) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('secret-save'),
                        value: save,
                        visualDensity: VisualDensity.compact,
                        onChanged: ready
                            ? (value) => setState(() => save = value ?? false)
                            : null,
                      ),
                      Text(
                        c.tr('允许 Bot 复用', 'Let the Bot reuse it'),
                        style: text.bodySmall,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            if (saved.isNotEmpty)
              TextButton(
                key: const ValueKey('secret-saved'),
                onPressed: ready
                    ? () => submit(savedId: '${saved.first['credentialId']}')
                    : null,
                child: Text(c.tr('用已保存的', 'Use the saved one')),
              ),
          ],
          if (request['state'] != 'pending' &&
              '${request['result'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${request['result']}',
                style: text.bodySmall?.copyWith(color: tone.danger),
              ),
            ),
          ErrorNotice(error),
        ],
      ),
    );
  }
}

class BotSecretsPage extends StatelessWidget {
  final NekodotClient client;
  final String botId;
  const BotSecretsPage({super.key, required this.client, required this.botId});
  @override
  Widget build(BuildContext context) => AppPage(
    title: client.tr('保密资料', 'Confidential information'),
    body: AsyncPane(
      load: () => client.rpc('secrets.list', {'botId': botId}),
      builder: (context, data, reload) {
        final entries = objects(data['credentials']);
        return PageList(
          children: [
            Text(
              client.tr(
                '只显示此 Bot 的资料元数据，不回显完整值。停用不会撤销已写入的配置或网站会话。',
                'Only this Bot’s metadata is displayed. Disabling does not undo target configurations or website sessions.',
              ),
            ),
            if (entries.isEmpty)
              Text(client.tr('尚未保存保密资料', 'No saved credentials')),
            for (final entry in entries)
              Panel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry['service']}',
                        key: ValueKey('saved-secret-${entry['credentialId']}'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${entry['purpose']}'),
                      SelectableText(
                        '${object(entry['target'])['origin'] ?? object(entry['target'])['path']}',
                      ),
                      Text(
                        '${entry['enabled'] == true ? client.tr('已保存', 'Saved') : client.tr('已停用', 'Disabled')} · ${client.tr('最近使用', 'Last used')}: ${entry['lastUsedAt']}',
                      ),
                      if (entry['enabled'] == true)
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: () async {
                                try {
                                  final request = await client.rpc(
                                    'secrets.replace',
                                    {
                                      'botId': botId,
                                      'credentialId': entry['credentialId'],
                                    },
                                  );
                                  if (!context.mounted) return;
                                  await pushPage(
                                    context,
                                    AppPage(
                                      title: client.tr(
                                        '替换保密资料',
                                        'Replace credential',
                                      ),
                                      body: PageList(
                                        children: [
                                          SecretCard(
                                            client: client,
                                            content: request,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  reload();
                                } catch (e) {
                                  if (context.mounted) {
                                    showNotice(context, '$e');
                                  }
                                }
                              },
                              child: Text(
                                client.tr('重新交付 / 替换', 'Re-deliver / replace'),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await client.rpc('secrets.disable', {
                                    'botId': botId,
                                    'credentialId': entry['credentialId'],
                                  });
                                  reload();
                                } catch (e) {
                                  if (context.mounted) {
                                    showNotice(context, '$e');
                                  }
                                }
                              },
                              child: Text(client.tr('停用', 'Disable')),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
