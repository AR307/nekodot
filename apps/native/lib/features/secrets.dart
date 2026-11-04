import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/secret_crypto.dart';
import '../ui/design.dart';

String secretState(NekodotClient c, String state) => switch (state) {
  'pending' => c.tr('等待保密交付', 'Waiting for confidential delivery'),
  'delivered' => c.tr('已交付 · 等待原生处理', 'Delivered · native processing'),
  'applied' => c.tr('已完成配置', 'Configuration applied'),
  'failed' => c.tr('配置或继续任务失败', 'Configuration or continuation failed'),
  'redelivery' => c.tr('需要重新交付', 'Delivery required again'),
  'cancelled' => c.tr('已取消', 'Cancelled'),
  'expired' => c.tr('请求已结束', 'Request ended'),
  _ => state,
};

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
  bool expanded = false, busy = false, save = false;
  String? savedId;
  final fields = <String, TextEditingController>{};
  NekodotClient get c => widget.client;
  Json get target => {
    'botId': widget.content['botId'],
    'requestId': widget.content['requestId'],
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(sync);
  }

  void sync() {
    final current = data;
    if (!expanded || current == null) return;
    final request = object(current['request']);
    final message = (c.node.messages[request['conversationId']] ?? [])
        .where(
          (m) =>
              m['kind'] == 'secret' &&
              m['content']['requestId'] == target['requestId'],
        )
        .firstOrNull;
    setState(() {
      if (message == null) return;
      final content = object(message['content']);
      if (!['pending', 'failed', 'redelivery'].contains(content['state'])) {
        clear();
      }
      data = {
        ...current,
        'request': {...request, ...content},
      };
    });
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
    if (widget.content['state'] != old.content['state'] && expanded) {
      if (![
        'pending',
        'failed',
        'redelivery',
      ].contains(widget.content['state'])) {
        clear();
      }
      unawaited(load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clear();
  }

  void clear() {
    for (final field in fields.values) {
      field.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(sync);
    nativeRoutes.unsubscribe(this);
    clear();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await c.rpc('secrets.get', target);
      if (!mounted) return;
      for (final field in objects(object(result['request'])['fields'])) {
        fields.putIfAbsent('${field['name']}', TextEditingController.new);
      }
      setState(() {
        data = result;
        error = '';
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> submit({bool cancel = false}) async {
    if (busy || !c.online) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (cancel) {
        await c.rpc('secrets.cancel', target);
      } else {
        final request = object(data!['request']);
        final values = {
          for (final field in objects(request['fields']))
            '${field['name']}': fields['${field['name']}']!.text,
        };
        if (savedId == null && values.values.any((v) => v.isEmpty)) {
          throw StateError(c.tr('请填写全部字段', 'Fill every requested field'));
        }
        final payload = savedId == null
            ? {
                'envelope': await encryptSecretDelivery(
                  nodeId: c.selectedNodeId!,
                  botId: '${target['botId']}',
                  requestId: '${target['requestId']}',
                  publicKey: '${data!['publicKey']}',
                  fields: values,
                ),
              }
            : {'credentialId': savedId};
        await c.rpc('secrets.submit', {...target, ...payload, 'save': save});
      }
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
    final request = data == null ? widget.content : object(data!['request']);
    final pending = [
      'pending',
      'redelivery',
      'failed',
    ].contains(request['state']);
    final bot = c.node.bots
        .where((b) => b['botId'] == widget.content['botId'])
        .firstOrNull;
    final definitions = objects(request['fields']);
    final saved = objects(data?['saved']);
    final destination = object(request['target'] ?? {});
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text('${request['service']}'),
              subtitle: Text(
                '${bot?['displayName'] ?? widget.content['botId']} · ${secretState(c, '${request['state']}')}',
              ),
              trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onTap: () {
                clear();
                setState(() => expanded = !expanded);
                if (expanded) unawaited(load());
              },
            ),
            Text('${request['purpose']}'),
            if (expanded) ...[
              const SizedBox(height: 10),
              if (data == null && error.isEmpty)
                const ShiningText(),
              if (data != null) ...[
                Text(
                  '${c.tr('接收方：', 'Recipient: ')}${bot?['displayName'] ?? target['botId']}',
                ),
                SelectableText(
                  '${destination['origin'] ?? destination['path'] ?? ''}',
                ),
                Text(
                  c.tr(
                    '客户端加密，只有所属 Node 解密。交付成功不代表登录或任务成功。',
                    'Encrypted on this device for the owning Node. Delivery does not mean login or task success.',
                  ),
                ),
                const SizedBox(height: 12),
                if (pending) ...[
                  if (saved.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(savedId),
                      isExpanded: true,
                      initialValue: savedId ?? '',
                      decoration: InputDecoration(
                        labelText: c.tr(
                          '此 Bot 的匹配资料',
                          'Matching credentials for this Bot',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(c.tr('重新填写', 'Enter new values')),
                        ),
                        for (final item in saved)
                          DropdownMenuItem(
                            value: '${item['credentialId']}',
                            child: Text(
                              '${item['service']} · ${item['lastUsedAt']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) {
                              clear();
                              setState(
                                () => savedId = value == '' ? null : value,
                              );
                            },
                    ),
                  if (savedId == null)
                    for (final field in definitions)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          key: ValueKey('secret-field-${field['name']}'),
                          controller: fields['${field['name']}'],
                          enabled: c.online && !busy,
                          obscureText:
                              field['kind'] == 'password' ||
                              field['kind'] == 'otp',
                          minLines: field['kind'] == 'private-key' ? 5 : 1,
                          maxLines: field['kind'] == 'private-key' ? 12 : 1,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          keyboardType: field['kind'] == 'private-key'
                              ? TextInputType.multiline
                              : TextInputType.visiblePassword,
                          decoration: InputDecoration(
                            labelText: '${field['label']}',
                          ),
                        ),
                      ),
                  if (!definitions.any((f) => f['kind'] == 'otp'))
                    CheckboxListTile(
                      key: const ValueKey('secret-save'),
                      value: save,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        c.tr('保存供此 Bot 后续使用', 'Save for this Bot to reuse'),
                      ),
                      subtitle: Text(
                        c.tr(
                          '仅限同一服务、用途与目标',
                          'Only this service, purpose and destination',
                        ),
                      ),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => save = value ?? false),
                    ),
                  Text(
                    c.tr(
                      '不保存仍会写入上方确认的配置。目标文件和网站登录状态可能继续保留。一次性验证码不会保存。',
                      'Not saving still writes the approved configuration. Target files and website sessions may persist. One-time codes are never saved.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('secret-submit'),
                        onPressed: busy || !c.online ? null : () => submit(),
                        icon: const Icon(Icons.lock_outline),
                        label: Text(c.tr('加密交付', 'Deliver encrypted')),
                      ),
                      TextButton(
                        onPressed: busy || !c.online
                            ? null
                            : () => submit(cancel: true),
                        child: Text(c.tr('取消请求', 'Cancel request')),
                      ),
                    ],
                  ),
                ],
                if ('${request['result'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${request['result']}'),
                  ),
              ],
              if (!c.online)
                Text(
                  c.tr(
                    '节点离线，恢复后请手动提交；不会自动发送。',
                    'Node is offline. Submit explicitly after reconnecting.',
                  ),
                ),
              if (busy) const ShiningText(),
              if (error.isNotEmpty)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ],
        ),
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
