import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/sandbox/host.dart';
import '../data/sandboxes.dart';
import '../ui/design.dart';

/// The two providers, as people know them.
String sandboxProviderName(String provider) =>
    provider == 'vercel' ? 'Vercel Sandbox' : 'Daytona';

/// Puts a new computer into a cloud sandbox made with the user's own account:
/// the form, then creating, installing and connecting. One step of adding a
/// computer; [onStage] says which part it is in (0 form, 1 installing,
/// 2 connecting) and [onDone] that the computer is online.
class SandboxSetupPage extends StatefulWidget {
  final NekodotClient client;
  final ValueChanged<int> onStage;
  final VoidCallback onDone;
  const SandboxSetupPage({
    super.key,
    required this.client,
    required this.onStage,
    required this.onDone,
  });
  @override
  State<SandboxSetupPage> createState() => _SandboxSetupPageState();
}

class _SandboxSetupPageState extends State<SandboxSetupPage> {
  NekodotClient get c => widget.client;
  String provider = 'daytona', plan = 'pro';
  SandboxSize size = SandboxSize.standard;
  final apiKey = TextEditingController(),
      token = TextEditingController(),
      team = TextEditingController(),
      project = TextEditingController(),
      name = TextEditingController();
  String invalid = '';
  SandboxInstall? install;

  @override
  void dispose() {
    install?.stop();
    install?.removeListener(_changed);
    for (final field in [apiKey, token, team, project, name]) {
      field.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final now = install!;
    widget.onStage(switch (now.step) {
      SandboxStep.connect || SandboxStep.done => 2,
      _ => 1,
    });
    setState(() {});
    if (now.step == SandboxStep.done) {
      c.selectNode(now.record!.nodeId!).then((_) => widget.onDone());
    }
  }

  Map<String, String>? credentials() => switch (provider) {
    'daytona' when apiKey.text.trim().isNotEmpty => {
      'apiKey': apiKey.text.trim(),
    },
    'vercel'
        when token.text.trim().isNotEmpty &&
            team.text.trim().isNotEmpty &&
            project.text.trim().isNotEmpty =>
      {
        'token': token.text.trim(),
        'teamId': team.text.trim(),
        'projectId': project.text.trim(),
        'sessionMinutes': plan == 'pro' ? '1440' : '45',
      },
    _ => null,
  };

  void start() {
    final given = credentials();
    final computer = SandboxInstall.validName(
      name.text.isEmpty ? sandboxProviderName(provider) : name.text,
    );
    if (given == null || computer == null) {
      setState(
        () => invalid = given == null
            ? c.tr('请填写完整', 'Fill in every field')
            : c.tr('名称最多 40 个字', 'Use a name of up to 40 characters'),
      );
      return;
    }
    final next = SandboxInstall(
      c.sandboxes,
      c.sandboxes.makeHost(provider, given),
    )..addListener(_changed);
    setState(() {
      invalid = '';
      install = next;
    });
    widget.onStage(1);
    next.run(name: computer, size: size, credentials: given);
  }

  /// Back to the form; a sandbox that was made is deleted first.
  Future<void> discard() async {
    final failed = install!;
    setState(() => failed.error = '');
    try {
      if (failed.record != null) await c.sandboxes.remove(failed.record!);
      failed.removeListener(_changed);
      setState(() => install = null);
      widget.onStage(0);
    } catch (e) {
      setState(() => failed.error = '$e');
    }
  }

  String failure(String error) => switch (error) {
    'daytona_network' => c.tr(
      '这个 Daytona 账号的沙箱连不上 nekodot：Tier 1 和 Tier 2 只能访问白名单上的网站，需要 Tier 3。',
      'This Daytona account’s sandboxes cannot reach nekodot: Tier 1 and 2 only reach allow-listed sites. Tier 3 is needed.',
    ),
    'unauthorized' => c.tr(
      '密钥无效或没有权限',
      'The key is invalid or not allowed to do this',
    ),
    'install_timeout' => c.tr(
      '安装 45 分钟还没结束',
      'The installation did not finish in 45 minutes',
    ),
    'not_online' => c.tr(
      '安装完成了，但这台电脑 5 分钟内没有连上',
      'Installed, but the computer did not connect within 5 minutes',
    ),
    'stopped' => c.tr('已停止', 'Stopped'),
    _ => error,
  };

  Widget field(
    String label,
    TextEditingController controller, {
    String? key,
    bool secret = false,
    String? hint,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        key: key == null ? null : ValueKey(key),
        controller: controller,
        obscureText: secret,
        enableSuggestions: !secret,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint),
      ),
      const SizedBox(height: 16),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final running = install;
    return running == null ? _form(context) : _progress(context, running);
  }

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageList(
      children: [
        Text(c.tr('沙箱账号', 'Sandbox account'), style: text.titleLarge),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Segment<String>(
            key: const ValueKey('sandbox-provider'),
            value: provider,
            options: const {
              'daytona': Text('Daytona'),
              'vercel': Text('Vercel Sandbox'),
            },
            onChanged: (value) => setState(() => provider = value),
          ),
        ),
        const SizedBox(height: 20),
        if (provider == 'daytona')
          field('API Key', apiKey, key: 'sandbox-daytona-key', secret: true)
        else ...[
          field(
            'Access Token',
            token,
            key: 'sandbox-vercel-token',
            secret: true,
          ),
          field('Team ID', team, key: 'sandbox-vercel-team', hint: 'team_…'),
          field(
            'Project ID',
            project,
            key: 'sandbox-vercel-project',
            hint: 'prj_…',
          ),
          Text(c.tr('套餐', 'Plan'), style: text.labelLarge),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Segment<String>(
              key: const ValueKey('sandbox-vercel-plan'),
              value: plan,
              options: {
                'pro': Text(c.tr('Pro（24 小时）', 'Pro (24 h)')),
                'hobby': Text(c.tr('Hobby（45 分钟）', 'Hobby (45 min)')),
              },
              onChanged: (value) => setState(() => plan = value),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(c.tr('规格', 'Size'), style: text.labelLarge),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Segment<SandboxSize>(
            key: const ValueKey('sandbox-size'),
            value: size,
            options: {
              for (final option in SandboxSize.values)
                option: Text(
                  c.tr(
                    '${option.cpu} 核 ${option.memoryGb} GB',
                    '${option.cpu} CPU ${option.memoryGb} GB',
                  ),
                ),
            },
            onChanged: (value) => setState(() => size = value),
          ),
        ),
        const SizedBox(height: 16),
        field(
          c.tr('电脑名称', 'Computer name'),
          name,
          key: 'sandbox-name',
          hint: sandboxProviderName(provider),
        ),
        if (invalid.isNotEmpty) ErrorNotice(invalid),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('sandbox-create'),
            onPressed: start,
            child: Text(c.tr('创建并安装', 'Create and install')),
          ),
        ),
      ],
    );
  }

  Widget _progress(BuildContext context, SandboxInstall running) {
    final tone = context.tone, text = Theme.of(context).textTheme;
    final failed = running.step == SandboxStep.failed;
    final reached = switch (failed ? running.failedAt : running.step) {
      SandboxStep.create => 0,
      SandboxStep.install => 1,
      SandboxStep.connect => 2,
      SandboxStep.done || SandboxStep.failed => 3,
    };
    final rows = [
      c.tr('创建沙箱', 'Create the sandbox'),
      c.tr('安装', 'Install'),
      c.tr('等待连接', 'Wait for it to connect'),
    ];
    return PageList(
      children: [
        Text(
          sandboxProviderName(running.host.provider),
          style: text.titleLarge,
        ),
        const SizedBox(height: 16),
        PanelGroup(
          children: [
            for (final (i, row) in rows.indexed)
              ListTile(
                key: ValueKey('sandbox-step-$i'),
                leading: SizedBox.square(
                  dimension: 20,
                  child: i < reached
                      ? const Icon(Symbols.check, size: 18)
                      : i == reached && failed
                      ? Icon(Symbols.error, size: 18, color: tone.danger)
                      : i == reached
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : null,
                ),
                title: i == reached && !failed
                    ? ShiningText(text: row)
                    : Text(
                        row,
                        style: TextStyle(
                          color: i <= reached ? tone.ink : tone.ink3,
                        ),
                      ),
              ),
          ],
        ),
        if (running.log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Panel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                running.log,
                key: const ValueKey('sandbox-log'),
                minLines: 1,
                maxLines: 8,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  height: 1.5,
                  color: tone.ink2,
                ),
              ),
            ),
          ),
        ],
        if (failed) ...[
          ErrorNotice(failure(running.error)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: const ValueKey('sandbox-discard'),
              onPressed: discard,
              child: Text(
                running.record == null
                    ? c.tr('重新填写', 'Edit')
                    : c.tr('删除沙箱并重新填写', 'Delete the sandbox and edit'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The sandboxes this device made, with their state and what can be done
/// with them: wake one that stopped, or delete it with its computer.
class SandboxesPanel extends StatefulWidget {
  final NekodotClient client;
  const SandboxesPanel({super.key, required this.client});
  @override
  State<SandboxesPanel> createState() => _SandboxesPanelState();
}

class _SandboxesPanelState extends State<SandboxesPanel> {
  NekodotClient get c => widget.client;
  final states = <String, SandboxState?>{};
  final busy = <String>{};
  String error = '';

  @override
  void initState() {
    super.initState();
    c.sandboxes.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    c.sandboxes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    for (final record in c.sandboxes.records) {
      c.sandboxes
          .hostFor(record)
          .state(record.id)
          .then(
            (state) {
              if (mounted) setState(() => states[record.id] = state);
            },
            onError: (_) {
              if (mounted) {
                setState(() => states[record.id] = SandboxState.failed);
              }
            },
          );
    }
    if (mounted) setState(() {});
  }

  Future<void> act(SandboxRecord record, Future<void> Function() action) async {
    setState(() {
      busy.add(record.id);
      error = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy.remove(record.id));
      _refresh();
    }
  }

  Future<void> delete(SandboxRecord record) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          c.tr(
            '删除「${record.name}」的沙箱？里面的 Dot、对话和文件都会消失，这台电脑也会从账号中移除。无法撤销。',
            'Delete the sandbox of “${record.name}”? Its Dots, chats and files go with it, and the computer leaves your account. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.tr('取消', 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('sandbox-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.tr('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await act(record, () async {
      await c.sandboxes.remove(record);
      await c.refreshMe();
    });
  }

  String stateText(SandboxState? state) => switch (state) {
    null => '',
    SandboxState.running => c.tr('运行中', 'Running'),
    SandboxState.starting => c.tr('启动中', 'Starting'),
    SandboxState.stopped => c.tr('已停止', 'Stopped'),
    SandboxState.gone => c.tr('已不存在', 'Gone'),
    SandboxState.failed => c.tr('出错', 'Error'),
  };

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelGroup(
          children: [
            for (final record in c.sandboxes.records)
              ListTile(
                key: ValueKey('sandbox-${record.id}'),
                leading: const Icon(Symbols.cloud),
                title: Text(record.name),
                subtitle: Row(
                  children: [
                    Text(
                      sandboxProviderName(record.provider),
                      style: TextStyle(color: tone.ink3),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      stateText(states[record.id]),
                      style: TextStyle(color: tone.ink3),
                    ),
                  ],
                ),
                trailing: busy.contains(record.id)
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (record.nodeId != null &&
                              states[record.id] != SandboxState.gone)
                            IconButton(
                              key: ValueKey('sandbox-wake-${record.id}'),
                              tooltip: c.tr('唤醒', 'Wake'),
                              icon: const Icon(Symbols.power_settings_new),
                              onPressed: () =>
                                  act(record, () => c.sandboxes.wake(record)),
                            ),
                          IconButton(
                            key: ValueKey('sandbox-delete-${record.id}'),
                            tooltip: c.tr('删除', 'Delete'),
                            icon: const Icon(Symbols.delete),
                            onPressed: () => delete(record),
                          ),
                        ],
                      ),
              ),
          ],
        ),
        if (error.isNotEmpty) ErrorNotice(error),
      ],
    );
  }
}
