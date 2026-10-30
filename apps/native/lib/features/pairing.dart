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
  bool busy = false, copied = false;
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
    final tone = context.tone;
    final seconds = code == null
        ? 0
        : DateTime.parse(code!['expiresAt'] as String)
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 999999);
    return AppPage(
      title: c.tr('添加电脑', 'Add computer'),
      body: PageList(
        children: [
          Row(
            children: [
              Text(
                'Linux x64 · WSL2',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              const Breathing(size: 8),
              const SizedBox(width: 8),
              Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 13,
                  color: tone.ink2,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: c.tr('延长 30 分钟', 'Add 30 minutes'),
                onPressed: busy || code == null
                    ? null
                    : () => generate(extend: true),
                icon: const Icon(Icons.more_time),
              ),
              IconButton(
                tooltip: c.tr('生成新码', 'Generate new code'),
                onPressed: busy ? null : generate,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Panel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: code == null
                        ? const Breathing()
                        : SelectableText(
                            code!['installCommand'] as String,
                            style: const TextStyle(
                              fontFamily: monoFont,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: c.tr('复制', 'Copy'),
                    onPressed: code == null
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: code!['installCommand'] as String,
                              ),
                            );
                            if (mounted) setState(() => copied = true);
                          },
                    icon: Icon(copied ? Icons.check : Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          ),
          ErrorNotice(error),
        ],
      ),
    );
  }
}
