import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

class SubscriptionPage extends StatelessWidget {
  final NekodotClient client;
  final String botId;
  const SubscriptionPage({
    super.key,
    required this.client,
    required this.botId,
  });

  @override
  Widget build(BuildContext context) => AppPage(
    title: client.tr('Nous 订阅', 'Nous subscription'),
    body: AsyncPane(
      load: () => client.rpc('subscription.get', {'botId': botId}),
      builder: (context, data, reload) => PageList(
        children: [
          Text(
            client.tr(
              '当前 Bot profile 的原生账号状态。套餐变更在官方门户完成；App 不代扣费。',
              'Native account state for this Bot profile. Plan changes happen in the official portal; the App never charges on your behalf.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data['logged_in'] == true
                ? '${data['org_name'] ?? ''}'
                : client.tr(
                    '该 profile 尚未登录 Nous',
                    'This profile is not signed in to Nous',
                  ),
          ),
          if (data['error'] != null && '${data['error']}'.isNotEmpty)
            ErrorNotice('${data['error']}'),
          if (data['current'] is Map)
            ListTile(
              title: Text(
                '${data['current']['name'] ?? data['current']['tier_name'] ?? ''}',
              ),
              subtitle: Text('${data['current']['renews_display'] ?? ''}'),
            ),
          for (final tier in objects(data['tiers']))
            ListTile(
              title: Text('${tier['name']}'),
              subtitle: Text('${tier['dollars_per_month_display']} / month'),
              trailing: tier['is_current'] == true
                  ? const Icon(Icons.check)
                  : null,
            ),
          if (data['portal_url'] is String &&
              Uri.tryParse(data['portal_url'])?.scheme == 'https')
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(data['portal_url']),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(
                client.tr('打开官方订阅门户', 'Open official subscription portal'),
              ),
            ),
        ],
      ),
    ),
  );
}
