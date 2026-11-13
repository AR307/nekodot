import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/account.dart';
import '../ui/design.dart';

/// The device captures audio; Hermes owns detection, transcription and settings.
class VoicePage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final ValueChanged<String>? onTranscript;
  const VoicePage({
    super.key,
    required this.client,
    required this.botId,
    this.onTranscript,
  });
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with WidgetsBindingObserver {
  final recorder = AudioRecorder(), transcript = TextEditingController();
  final audio = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? microphone;
  Timer? feedTimer;
  Json status = {};
  String? listenerId;
  String error = '';
  bool busy = false, recording = false, feeding = false;
  bool foreground = true;
  int captureGeneration = 0;
  NekodotClient get c => widget.client;
  Json get target => {'botId': widget.botId};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final result = await c.rpc('voice.status', target);
      if (mounted) setState(() => status = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<bool> capture() async {
    final generation = captureGeneration;
    if (!await recorder.hasPermission()) {
      throw RelayError(
        c.tr(
          '需要麦克风权限。请在系统设置中允许后重试。',
          'Microphone permission is required. Allow it in system settings and try again.',
        ),
      );
    }
    if (!mounted || !foreground || generation != captureGeneration) {
      return false;
    }
    audio.clear();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (!mounted || !foreground || generation != captureGeneration) {
      await recorder.stop();
      return false;
    }
    microphone = stream.listen(
      audio.add,
      onError: (Object e) {
        if (mounted) setState(() => error = '$e');
        unawaited(stop());
      },
    );
    return true;
  }

  Future<void> stop() async {
    captureGeneration++;
    feedTimer?.cancel();
    feedTimer = null;
    final owned = listenerId;
    listenerId = null;
    await microphone?.cancel();
    microphone = null;
    await recorder.stop();
    if (owned != null && c.online) {
      await c.rpc('voice.stop', {...target, 'listenerId': owned});
    }
    if (mounted) setState(() => recording = false);
  }

  Future<void> startWake() async {
    final generation = captureGeneration;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.rpc('voice.start', target);
      if (!mounted || !foreground || generation != captureGeneration) {
        if (result['started'] == true && c.online) {
          await c.rpc('voice.stop', {
            ...target,
            'listenerId': result['listenerId'],
          });
        }
        return;
      }
      if (result['started'] != true) {
        throw RelayError('${result['hint'] ?? result['reason']}');
      }
      listenerId = '${result['listenerId']}';
      if (!await capture()) return;
      feedTimer = Timer.periodic(
        const Duration(milliseconds: 160),
        (_) => unawaited(feed()),
      );
    } catch (e) {
      await stop();
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> feed() async {
    if (feeding || listenerId == null || audio.isEmpty) return;
    final owned = listenerId;
    feeding = true;
    try {
      final result = await c.rpc('voice.feed', {
        ...target,
        'listenerId': owned,
        'pcm': base64Encode(audio.takeBytes()),
      });
      if (!mounted || !foreground || listenerId != owned) return;
      if (result['fed'] != true) throw RelayError('${result['reason']}');
      if (result['detected'] != null) {
        await stop();
        await startRecording();
      }
    } catch (e) {
      await stop();
      if (mounted) setState(() => error = '$e');
    } finally {
      feeding = false;
    }
  }

  Future<void> startRecording() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await stop();
      if (!await capture()) return;
      if (mounted) setState(() => recording = true);
    } catch (e) {
      await stop();
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transcribe() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await stop();
      final pcm = audio.takeBytes();
      if (pcm.isEmpty) {
        throw RelayError(c.tr('没有录到声音', 'No audio was recorded'));
      }
      // PCM capture stays in memory; this standard WAV header supplies native STT's upload format.
      final header = ByteData(44);
      void text(int at, String value) =>
          Uint8List.view(header.buffer)
              .setRange(at, at + value.length, value.codeUnits);
      text(0, 'RIFF');
      header.setUint32(4, 36 + pcm.length, Endian.little);
      text(8, 'WAVEfmt ');
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, 1, Endian.little);
      header.setUint32(24, 16000, Endian.little);
      header.setUint32(28, 32000, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      text(36, 'data');
      header.setUint32(40, pcm.length, Endian.little);
      final wav =
          (BytesBuilder(copy: false)
                ..add(header.buffer.asUint8List())
                ..add(pcm))
              .takeBytes();
      var operation = await c.rpc('voice.transcribe', {
        ...target,
        'audio': 'data:audio/wav;base64,${base64Encode(wav)}',
      });
      while (operation['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        operation = await c.rpc('operations.get', {
          'operationId': operation['operationId'],
        });
      }
      if (operation['status'] != 'done') {
        throw RelayError('${operation['detail']}');
      }
      final result = objects(operation['results']).first['native'];
      if (mounted) {
        setState(() => transcript.text = '${result['transcript'] ?? ''}');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (widget.onTranscript != null) {
      widget.onTranscript!(transcript.text.trim());
      Navigator.pop(context);
      return;
    }
    final dm = c.node.conversations.firstWhere(
      (row) => row['kind'] == 'dm' && row['botId'] == widget.botId,
    );
    setState(() => busy = true);
    try {
      await c.send('${dm['conversationId']}', transcript.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) foreground = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      foreground = false;
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop().whenComplete(recorder.dispose));
    transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(c.tr('语音与唤醒', 'Voice & wake word'))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.tr(
              '使用当前设备的麦克风。识别和唤醒由此 Bot 的 Hermes 原生配置负责；只在本页前台采音，离开或进入后台即停止。',
              'Uses this device’s microphone with the Bot’s native Hermes detection and transcription. Audio capture stops when this page closes or the App enters the background.',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: MetaText([
              '${status['phrase'] ?? 'Hermes'}',
              '${status['provider'] ?? ''}',
            ]),
            subtitle: Text(
              '${status['hint'] ?? c.tr('正在读取原生状态…', 'Reading native status…')}',
            ),
            trailing: IconButton(
              onPressed: busy ? null : refresh,
              icon: const Icon(Symbols.refresh),
            ),
          ),
          if (error.isNotEmpty)
            Text(error, style: TextStyle(color: context.tone.danger)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy || !c.online || status['available'] != true
                ? null
                : listenerId == null
                ? startWake
                : stop,
            icon: Icon(listenerId == null ? Symbols.hearing : Symbols.stop),
            label: Text(
              listenerId == null
                  ? c.tr('启用本机语音唤醒', 'Listen for wake word')
                  : c.tr('停止监听', 'Stop listening'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy || !c.online
                ? null
                : recording
                ? transcribe
                : startRecording,
            icon: Icon(recording ? Symbols.stop : Symbols.mic),
            label: Text(
              recording
                  ? c.tr('停止并识别', 'Stop & transcribe')
                  : c.tr('录制一句话', 'Record a message'),
            ),
          ),
          if (busy) const ShiningText(),
          const SizedBox(height: 20),
          TextField(
            controller: transcript,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: c.tr(
                '识别结果（发送前可编辑）',
                'Transcript (edit before sending)',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy || !c.online || transcript.text.trim().isEmpty
                ? null
                : send,
            child: Text(c.tr('发送给 Bot', 'Send to Bot')),
          ),
        ],
      ),
    ),
  );
}
