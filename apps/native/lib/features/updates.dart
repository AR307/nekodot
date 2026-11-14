import 'dart:io';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/updates.dart';
import '../ui/design.dart';

class UpdatesPage extends StatefulWidget {
  final NekodotClient client;
  const UpdatesPage({super.key, required this.client});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  InstalledVersion? current;
  ProductRelease? latest;
  Json? relay;
  InstalledVersion? publishedRelay;
  bool busy = false, checked = false, permissionNeeded = false;
  double? progress;
  String error = '';
  File? package;
  NekodotClient get c => widget.client;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final installed = await InstalledVersion.read();
      if (mounted) setState(() => current = installed);
      final result = await c.account.request('/releases');
      final release = result['latest']?['artifacts']?[clientPlatform] == null
          ? null
          : ProductRelease(object(result['latest']), c.account.origin);
      if (mounted) {
        setState(() {
          current = installed;
          latest = release;
          relay = object(result['relay']);
          publishedRelay = result['latest'] == null
              ? null
              : InstalledVersion(
                  result['latest']['version'] as String,
                  result['latest']['artifacts']['relay']['build'] as int,
                );
          checked = true;
          package = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    setState(() {
      busy = true;
      error = '';
      progress = 0;
    });
    try {
      final file = await downloadUpdate(latest!, (value) {
        if (mounted) setState(() => progress = value);
      });
      if (mounted) setState(() => package = file);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> install() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (!await canInstallUpdate()) {
        if (mounted) setState(() => permissionNeeded = true);
        return;
      }
      if (mounted) setState(() => permissionNeeded = false);
      await installUpdate(package!);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: c.tr('版本与更新', 'Versions & updates'),
    body: PageList(
      children: [
        PanelGroup(
          children: [
            ListTile(
              leading: const Icon(Symbols.system_update),
              title: Text(c.tr('当前客户端', 'Installed client')),
              subtitle: Text(current?.toString() ?? '…'),
            ),
            ListTile(
              title: Text(c.tr('最新发布', 'Latest release')),
              subtitle: Text(
                latest == null
                    ? c.tr(
                        checked ? '此系统尚未发布安装包' : '等待检查',
                        checked
                            ? 'No release for this platform'
                            : 'Waiting for check',
                      )
                    : '${latest!.version} (${latest!.build})',
              ),
              trailing: TextButton(
                onPressed: busy ? null : check,
                child: Text(c.tr('检查更新', 'Check updates')),
              ),
            ),
          ],
        ),
        if (latest != null && current != null) ...[
          const SizedBox(height: 16),
          Text(
            latest!.newerThan(current!)
                ? c.tr('有新版本可用', 'Update available')
                : c.tr(
                    '当前已是最新版本或更新的候选版本',
                    'Up to date or running a newer candidate',
                  ),
          ),
          if (latest!.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(latest!.notes),
            ),
          if (latest!.newerThan(current!)) ...[
            Text(
              c.tr(
                '更新保留登录与设置，服务器任务和聊天历史不受影响。安装需要系统确认。',
                'Updates keep your login and settings. Server tasks and history are unaffected. Installation requires system confirmation.',
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              Text('${(progress! * 100).toStringAsFixed(0)}%'),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('download-update'),
              onPressed: busy
                  ? null
                  : package == null
                  ? download
                  : install,
              child: Text(
                package == null
                    ? c.tr('下载安装包', 'Download update')
                    : c.tr(
                        Platform.isWindows ? '退出并安装' : '打开系统安装器',
                        Platform.isWindows
                            ? 'Quit & install'
                            : 'Open system installer',
                      ),
              ),
            ),
            if (permissionNeeded) ...[
              Text(
                c.tr(
                  '请允许 nekodot 安装应用，返回后再次点击安装。不会自动开启权限。',
                  'Allow app installation for nekodot, then return and tap install again. Permission is never enabled automatically.',
                ),
              ),
              TextButton(
                onPressed: openInstallPermission,
                child: Text(
                  c.tr('打开安装权限设置', 'Open install permission settings'),
                ),
              ),
            ],
          ],
        ],
        const SizedBox(height: 24),
        PanelGroup(
          children: [
            ListTile(
              title: Text(c.tr('连接的 Relay', 'Connected Relay')),
              subtitle: Text(c.account.origin.host),
            ),
            ListTile(
              title: Text(c.tr('服务端版本', 'Server version')),
              subtitle: Text(
                relay == null
                    ? '—'
                    : '${relay!['version']} (${relay!['build']})',
              ),
            ),
            ListTile(
              title: Text(c.tr('最新 Relay', 'Latest Relay')),
              subtitle: Text(publishedRelay?.toString() ?? '—'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          c.tr(
            'Relay 由服务器管理员更新，不会因普通客户端操作重启。管理员可在部署目录运行：',
            'Relay updates are managed by the server operator, not ordinary app accounts. Run in the deployment directory:',
          ),
        ),
        const SelectableText(
          'python3 update-relay.py --check\npython3 update-relay.py --apply',
        ),
        ErrorNotice(error),
      ],
    ),
  );
}
