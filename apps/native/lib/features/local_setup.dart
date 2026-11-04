import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../local/location.dart';
import '../local/runtime.dart';
import '../ui/design.dart';
import 'pairing.dart';

String localStepLabel(NekodotClient c, String id) => switch (id) {
  'node' => c.tr('准备 Node 运行环境', 'Prepare Node runtime'),
  'installer' => c.tr('获取 Hermes 安装程序', 'Fetch Hermes installer'),
  'prerequisites' => c.tr('安装基础组件', 'Install prerequisites'),
  'repository' => c.tr(
    '获取 Hermes $hermesVersion',
    'Fetch Hermes $hermesVersion',
  ),
  'venv' => c.tr('准备 Python', 'Prepare Python'),
  'python-deps' => c.tr('安装依赖', 'Install dependencies'),
  'config' => c.tr('初始化配置', 'Initialize configuration'),
  'products' => c.tr('构建 Hermes', 'Build Hermes'),
  'complete' => c.tr('完成安装', 'Finish installation'),
  'verify' => c.tr('检查 Hermes', 'Check Hermes'),
  'account' => c.tr('准备账号数据', 'Prepare account data'),
  'pair' => c.tr('绑定这台电脑', 'Pair this computer'),
  _ => c.tr('启动并连接', 'Start and connect'),
};

String localPhaseLabel(NekodotClient c, LocalPhase phase) => switch (phase) {
  LocalPhase.idle => c.tr('已停止', 'Stopped'),
  LocalPhase.installing => c.tr('正在安装', 'Installing'),
  LocalPhase.pairing => c.tr('正在绑定', 'Pairing'),
  LocalPhase.starting => c.tr('正在启动', 'Starting'),
  LocalPhase.online => c.tr('运行中', 'Running'),
  LocalPhase.offline => c.tr('正在重新连接', 'Reconnecting'),
  LocalPhase.stopping => c.tr('正在停止', 'Stopping'),
  LocalPhase.failed => c.tr('出错', 'Failed'),
};

/// Install failures carry the real tool output; only the cancel marker needs words.
String localErrorText(NekodotClient c, String error) =>
    error == 'cancelled' ? c.tr('已取消，可从中断处继续', 'Cancelled; retry continues from here') : error;

String _gigabytes(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);

/// Desktop "Add computer": run here, or connect a remote server as before.
class RunLocationPage extends StatelessWidget {
  final NekodotClient client;
  const RunLocationPage({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    final c = client;
    final local = localRuntime!;
    return AppPage(
      title: c.tr('添加电脑', 'Add computer'),
      body: PageList(
        children: [
          PanelGroup(
            children: [
              ListTile(
                key: const ValueKey('run-here'),
                leading: const Icon(Icons.laptop_outlined),
                title: Text(c.tr('在这台电脑运行', 'Run on this computer')),
                subtitle: local.support.supported
                    ? null
                    : Text(c.tr('此系统暂不支持', 'Not supported on this system')),
                enabled: local.support.supported,
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalSetupPage(client: c),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('connect-server'),
                leading: const Icon(Icons.dns_outlined),
                title: Text(c.tr('连接远程服务器', 'Connect a remote server')),
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => PairingPage(client: c),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Choose the two folders, then install, pair and start the node on this computer.
class LocalSetupPage extends StatefulWidget {
  final NekodotClient client;
  const LocalSetupPage({super.key, required this.client});
  @override
  State<LocalSetupPage> createState() => _LocalSetupPageState();
}

class _LocalSetupPageState extends State<LocalSetupPage> {
  final local = localRuntime!;
  NekodotClient get c => widget.client;
  FolderCheck? runtime, data;
  bool started = false;

  @override
  void initState() {
    super.initState();
    local.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    local.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (started && local.phase == LocalPhase.online) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final location = local.location ?? await LocalLocation.defaults();
    final checks = await Future.wait([
      checkFolder(location.runtime, FolderKind.runtime),
      checkFolder(location.data, FolderKind.data),
    ]);
    if (mounted) {
      setState(() {
        runtime = checks[0];
        data = checks[1];
      });
    }
  }

  Future<void> _choose(FolderKind kind) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: kind == FolderKind.runtime
          ? c.tr('选择运行环境目录', 'Choose the runtime folder')
          : c.tr('选择数据目录', 'Choose the data folder'),
    );
    if (path == null) return;
    final check = await checkFolder(path, kind);
    if (mounted) {
      setState(
        () => kind == FolderKind.runtime ? runtime = check : data = check,
      );
    }
  }

  String _problem(String problem, FolderKind kind) => switch (problem) {
    'relative' => c.tr('请选择完整路径', 'Choose a full path'),
    'install-dir' => c.tr('不能放在应用安装目录内', 'Cannot be inside the app folder'),
    'not-fixed' => c.tr('请选择本机固定磁盘', 'Choose a local fixed disk'),
    'not-empty' => c.tr(
      '请选择空文件夹或已有的 nekodot 目录',
      'Choose an empty or existing nekodot folder',
    ),
    _ => c.tr(
      '空间不足，至少需要 ${_gigabytes(kind == FolderKind.runtime ? runtimeSpace : dataSpace)} GB',
      'Not enough space: needs ${_gigabytes(kind == FolderKind.runtime ? runtimeSpace : dataSpace)} GB',
    ),
  };

  Widget _folder(FolderKind kind, FolderCheck? check) {
    final problem = check?.problem;
    final free = check?.free;
    return ListTile(
      key: ValueKey('folder-${kind.name}'),
      title: Text(
        kind == FolderKind.runtime
            ? c.tr('运行环境目录', 'Runtime folder')
            : c.tr('数据目录', 'Data folder'),
      ),
      subtitle: Text(
        [
          check?.path ?? '…',
          if (problem != null)
            _problem(problem, kind)
          else if (check?.existing == true)
            c.tr('使用已有内容', 'Reusing existing content')
          else if (free != null)
            c.tr('可用 ${_gigabytes(free)} GB', '${_gigabytes(free)} GB free'),
        ].join('\n'),
        style: problem == null
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      isThreeLine: true,
      trailing: TextButton(
        onPressed: local.busy ? null : () => _choose(kind),
        child: Text(c.tr('更改', 'Change')),
      ),
    );
  }

  Widget _step(LocalStep step) {
    final tone = context.tone;
    final icon = switch (step.state) {
      'done' => Icon(Icons.check, size: 18, color: tone.ink),
      'running' => const Breathing(size: 8),
      'failed' => Icon(
        Icons.close,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      ),
      _ => StatusDot(on: false, size: 8),
    };
    return ListTile(
      dense: true,
      leading: SizedBox(width: 20, child: Center(child: icon)),
      title: Text(localStepLabel(c, step.id)),
      subtitle: step.detail.isEmpty || step.state == 'done'
          ? null
          : Text(
              localErrorText(c, step.detail),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }

  Future<void> _start() async {
    started = true;
    await local.setup(LocalLocation(runtime!.path, data!.path));
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        runtime?.problem == null &&
        data?.problem == null &&
        runtime != null &&
        data != null;
    final showSteps = local.steps.any((s) => s.state != 'pending');
    return AppPage(
      title: c.tr('在这台电脑运行', 'Run on this computer'),
      body: PageList(
        children: [
          PanelGroup(
            children: [
              _folder(FolderKind.runtime, runtime),
              _folder(FolderKind.data, data),
            ],
          ),
          if (showSteps) ...[
            const SizedBox(height: 14),
            PanelGroup(children: [for (final step in local.steps) _step(step)]),
          ],
          const SizedBox(height: 16),
          ErrorNotice(localErrorText(c, local.error)),
          const SizedBox(height: 8),
          if (local.busy)
            OutlinedButton(
              key: const ValueKey('cancel-local'),
              onPressed: local.phase == LocalPhase.installing
                  ? local.cancelSetup
                  : null,
              child: Text(c.tr('取消', 'Cancel')),
            )
          else
            FilledButton(
              key: const ValueKey('start-local'),
              onPressed: ready ? _start : null,
              child: Text(
                local.phase == LocalPhase.failed
                    ? c.tr('重试', 'Retry')
                    : c.tr('安装并启动', 'Install and start'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings card for the node on this computer.
class LocalComputerPanel extends StatelessWidget {
  final NekodotClient client;
  const LocalComputerPanel({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    final local = localRuntime;
    if (local == null || local.location == null || local.userId == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: local,
      builder: (context, _) {
        final c = client;
        final location = local.location!;
        Widget folder(String title, String path) => ListTile(
          title: Text(title),
          subtitle: Text(path),
          trailing: IconButton(
            tooltip: c.tr('打开', 'Open'),
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => launchUrl(Uri.file(path)),
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PanelGroup(
            children: [
              ListTile(
                key: const ValueKey('local-status'),
                leading: local.busy
                    ? const Breathing(size: 8)
                    : StatusDot(on: local.phase == LocalPhase.online),
                title: Text(c.tr('这台电脑', 'This computer')),
                subtitle: Text(
                  local.error.isEmpty
                      ? localPhaseLabel(c, local.phase)
                      : local.error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: local.nodeId == null || local.busy
                    ? null
                    : local.running
                    ? TextButton(
                        onPressed: local.stop,
                        child: Text(c.tr('停止', 'Stop')),
                      )
                    : TextButton(
                        onPressed: local.start,
                        child: Text(c.tr('启动', 'Start')),
                      ),
                onTap: local.nodeId == null || local.phase == LocalPhase.failed
                    ? () => pushPage(context, LocalSetupPage(client: c))
                    : null,
              ),
              folder(c.tr('运行环境目录', 'Runtime folder'), location.runtime),
              folder(
                c.tr('数据目录', 'Data folder'),
                location.account(local.userId!),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Asked before quitting while the local node is working: quitting interrupts it.
Future<bool> confirmLocalQuit(BuildContext context, NekodotClient c) async {
  final local = localRuntime;
  if (local == null || !local.working) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(
        c.tr(
          '这台电脑上的任务正在运行，退出会中断它们。',
          'Tasks are running on this computer. Quitting interrupts them.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(c.tr('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(c.tr('退出', 'Quit')),
        ),
      ],
    ),
  );
  return confirmed == true;
}
