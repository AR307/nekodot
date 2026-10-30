import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../ui/design.dart';

class PairingPage extends StatefulWidget {
  final NekodotClient client;
  const PairingPage({super.key, required this.client});
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  Json? code;
  String error = '';
  Timer? timer;
  bool busy = false;
  late final previous = objects(widget.client.me?['nodes'])
      .map((x) => x['nodeId'])
      .toSet();
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    generate();
    timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final me = await c.request('/me');
        if (!mounted) return;
        final added = objects(me['nodes'])
            .where(
              (x) => !previous.contains(x['nodeId']) && x['online'] == true,
            )
            .firstOrNull;
        c.me = me;
        if (added != null) {
          await c.selectNode(added['nodeId'] as String);
          if (mounted) Navigator.pop(context);
        } else {
          setState(() {});
        }
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    });
  }

  Future<void> generate({bool extend = false}) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final value = await c.request(
        extend ? '/pairing-codes/${code!['code']}/extend' : '/pairing-codes',
        method: 'POST',
        body: {},
      );
      if (mounted) setState(() => code = {...?code, ...value});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = code == null
        ? 0
        : DateTime.parse(code!['expiresAt'] as String)
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 999999);
    return Scaffold(
      appBar: AppBar(title: Text(c.tr('添加电脑', 'Add computer'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.tr('让 Bot 有一个工作的地方。', 'Give your Bots a place to work.'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  c.tr(
                    '在 Linux x64 服务器或已启用 systemd 的 WSL2 终端运行下方命令。不要在 Windows PowerShell 中运行。',
                    'Run this command in a Linux x64 server or a systemd-enabled WSL2 terminal, not Windows PowerShell.',
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          '${code?['installCommand'] ?? c.tr('正在生成命令…', 'Preparing command…')}',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: code == null
                              ? null
                              : () => Clipboard.setData(
                                  ClipboardData(
                                    text: code!['installCommand'] as String,
                                  ),
                                ),
                          icon: const Icon(Icons.copy),
                          label: Text(c.tr('复制安装命令', 'Copy install command')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  c.tr(
                    '等待电脑上线 · 剩余 ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                    'Waiting for computer · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} remaining',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: busy || code == null
                          ? null
                          : () => generate(extend: true),
                      child: Text(c.tr('延长 30 分钟', 'Add 30 minutes')),
                    ),
                    TextButton(
                      onPressed: busy ? null : generate,
                      child: Text(c.tr('生成新码', 'Generate new code')),
                    ),
                  ],
                ),
                ErrorNotice(error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
