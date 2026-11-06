import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'location.dart';
import 'owned_process.dart';
import 'system.dart';

const _nodeArchives = {
  LocalPlatform.windows: (
    'node-v24.22.1-win-x64.zip',
    'd2046d28c2c3dcd211ac5145c0bf30e2047ef9dfb306693c8c6e2eccd8b95fa5',
  ),
  LocalPlatform.macos: (
    'node-v24.22.1-darwin-arm64.tar.gz',
    '89c682593d76cd44233fa53b1563264e7de9cbb189cad169135c5b4fadfbc0a7',
  ),
  LocalPlatform.linux: (
    'node-v24.22.1-linux-x64.tar.gz',
    'eb6728e77c576a35162c122c45ccadf224d89ff00abc8dae46cc2897c6002d7c',
  ),
};

/// Download, extract, then use Hermes's portable backend launcher. No source build.
const runtimeSteps = ['node', 'repository', 'python-deps', 'verify'];

class InstallFailure implements Exception {
  final String step, detail;
  const InstallFailure(this.step, this.detail);
  @override
  String toString() => '$step: $detail';
}

/// Environment for anything nekodot starts: the user's own Hermes and uv settings never leak in.
Map<String, String> isolatedEnvironment(Map<String, String> extra) => {
  for (final entry in Platform.environment.entries)
    if (!RegExp(
      r'^(HERMES_|NEKODOT_|UV_)',
      caseSensitive: false,
    ).hasMatch(entry.key))
      entry.key: entry.value,
  ...extra,
};

class RuntimeInstaller {
  final LocalLocation location;
  final LocalPlatform platform;
  final http.Client web;
  final void Function(String step, String state, String detail) progress;
  final Uri origin;
  OwnedProcess? _current;
  bool _cancelled = false;
  final _abort = Completer<void>();

  RuntimeInstaller(
    this.location,
    this.platform,
    this.web,
    this.progress, {
    required this.origin,
  });

  Map<String, String> _environment(String home) => isolatedEnvironment({
    'HERMES_HOME': home,
    'HERMES_RUNTIME_DIR': location.tools,
    'UV_CACHE_DIR': location.cache,
  });

  void cancel() {
    _cancelled = true;
    if (!_abort.isCompleted) _abort.complete();
    _current?.kill();
  }

  Future<void> run() async {
    final done = await location.completed();
    await Directory(location.logs).create(recursive: true);
    for (final step in runtimeSteps) {
      if (_cancelled) throw InstallFailure(step, 'cancelled');
      if (done.contains(step) && step != 'verify') {
        progress(step, 'done', '');
        continue;
      }
      progress(step, 'running', '');
      try {
        switch (step) {
          case 'node':
            await _node();
          case 'repository':
            await _runtimeDownload();
          case 'python-deps':
            await _extract();
          case 'verify':
            await prepareAccount(location.owner);
        }
      } catch (_) {
        // Aborting the HTTP stream can surface as RequestAborted or a closed
        // file sink. Both are the same user action, not an installation fault.
        if (_cancelled) throw InstallFailure(step, 'cancelled');
        rethrow;
      }
      done.add(step);
      await location.record(done);
      progress(step, 'done', '');
    }
  }

  String get _archive => joinPath(
    location.runtime,
    'downloads',
    'hermes-$hermesRuntimeVersion.tar.gz',
  );

  Future<void> _runtimeDownload() async {
    final target = switch (platform) {
      LocalPlatform.windows => 'win32-x64',
      LocalPlatform.macos => 'darwin-arm64',
      LocalPlatform.linux => 'linux-x64',
    };
    final path = '/downloads/hermes/$hermesRuntimeVersion/$target';
    final response = await http.Response.fromStream(
      await web.send(
        http.AbortableRequest(
          'GET',
          origin.resolve('$path.json'),
          abortTrigger: _abort.future,
        ),
      ),
    ).timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw InstallFailure('repository', 'HTTP ${response.statusCode}');
    }
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    if (manifest['version'] != hermesRuntimeVersion ||
        manifest['target'] != target) {
      throw const InstallFailure(
        'repository',
        'Runtime version or platform mismatch',
      );
    }
    await Directory(joinPath(location.runtime, 'downloads'))
        .create(recursive: true);
    await _download(
      'repository',
      origin.resolve('$path.tar.gz'),
      File(_archive),
      null,
      bytes: manifest['bytes'] as int,
    );
  }

  Future<void> _extract() async {
    // A previous interrupted extraction is retained; only a new staging directory is used.
    if (await File(joinPath(location.payload, 'manifest.json')).exists()) {
      return;
    }
    final staging = Directory(
      '${location.payload}.extract-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    final log = File(joinPath(location.logs, 'install-runtime.log'))
        .openWrite(mode: FileMode.append);
    try {
      _current = await OwnedProcess.start(
        Platform.isWindows ? windowsTool('tar.exe') : 'tar',
        ['-xzf', _archive, '-C', staging.path],
        workingDirectory: location.runtime,
        environment: _environment(location.owner),
        log: log,
      );
      final code = await _current!.exitCode;
      if (_cancelled) throw const InstallFailure('python-deps', 'cancelled');
      if (code != 0) {
        throw InstallFailure('python-deps', _current!.tail.join('\n'));
      }
      await staging.rename(location.payload);
    } finally {
      _current = null;
      await log.close();
    }
  }

  Future<void> prepareAccount(String home) async {
    await Directory(home).create(recursive: true);
    final config = File(joinPath(home, 'config.yaml'));
    if (!await config.exists()) {
      await File(joinPath(location.checkout, 'cli-config.yaml.example'))
          .copy(config.path);
    }
    final cache = joinPath(home, 'cache');
    // Hermes deliberately ignores UV_CACHE_DIR for its own PM. Share only its
    // download cache through the documented home layout, never environments.
    if (!await Directory(cache).exists()) {
      final shared = Directory(joinPath(location.runtime, 'cache'));
      await shared.create(recursive: true);
      if (Platform.isWindows) {
        String quote(String value) => "'${value.replaceAll("'", "''")}'";
        final result = await runOwned(
          windowsTool('WindowsPowerShell/v1.0/powershell.exe'),
          [
            '-NoProfile',
            '-Command',
            'New-Item -ItemType Junction -Path ${quote(cache)} -Target ${quote(shared.path)} | Out-Null',
          ],
        );
        if (result.code != 0) throw InstallFailure('account', result.output);
      } else {
        await Link(cache).create(shared.path);
      }
    }
    // A fresh account uses the shipped baseline. Hermes creates a private PM generation
    // only when that account adds dependencies; no all-extras install or frontend build.
    final result = await runOwned(
      location.launcher,
      ['--version'],
      workingDirectory: home,
      environment: _environment(home),
    );
    if (result.code != 0) throw InstallFailure('account', result.output);
  }

  Future<void> _node() async {
    if (await File(location.nodeExecutable).exists()) return;
    final (name, sha) = _nodeArchives[platform]!;
    final downloads = Directory(joinPath(location.runtime, 'downloads'));
    await downloads.create(recursive: true);
    final archive = File(joinPath(downloads.path, name));
    await _download(
      'node',
      Uri.parse('https://nodejs.org/dist/v$nodeVersion/$name'),
      archive,
      sha,
    );
    final parent = Directory(joinPath(location.runtime, 'node'));
    final staging = Directory(
      joinPath(parent.path, '.extract-${Random().nextInt(1 << 32)}'),
    );
    await staging.create(recursive: true);
    final tar = Platform.isWindows ? windowsTool('tar.exe') : 'tar';
    final result = await runOwned(tar, [
      Platform.isWindows ? '-xf' : '-xzf',
      archive.path,
      '-C',
      staging.path,
    ]);
    if (result.code != 0) throw InstallFailure('node', result.output);
    final extracted = Directory(
      joinPath(staging.path, name.replaceAll(RegExp(r'\.(zip|tar\.gz)$'), '')),
    );
    await extracted.rename(location.nodeRoot);
    if (!await File(location.nodeExecutable).exists()) {
      throw const InstallFailure(
        'node',
        'node executable missing after extraction',
      );
    }
  }

  Future<void> _download(
    String step,
    Uri url,
    File target,
    String? sha256, {
    int? bytes,
  }) async {
    if (bytes != null &&
        await target.exists() &&
        await target.length() == bytes) {
      return;
    }
    if (sha256 != null &&
        await target.exists() &&
        _hex((await _hashFile(target)).bytes) == sha256) {
      return;
    }
    final partial = File('${target.path}.part');
    final offset = bytes != null && await partial.exists()
        ? await partial.length()
        : 0;
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: _abort.future,
    );
    if (offset > 0 && offset < bytes!) {
      request.headers['Range'] = 'bytes=$offset-';
    }
    final response = await web
        .send(request)
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw InstallFailure(step, 'HTTP ${response.statusCode}');
    }
    final resumed = response.statusCode == 206;
    if (resumed &&
        !('${response.headers['content-range']}').startsWith(
          'bytes $offset-',
        )) {
      throw InstallFailure(step, 'Invalid download range');
    }
    final total = bytes ?? response.contentLength ?? 0;
    final sink = partial.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    final hash = sha256 == null ? null : Sha256().newHashSink();
    var received = resumed ? offset : 0;
    var lastPercent = -1;
    try {
      await sink.addStream(
        response.stream.timeout(const Duration(seconds: 60)).map((chunk) {
          if (_cancelled) throw InstallFailure(step, 'cancelled');
          hash?.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final percent = received * 100 ~/ total;
            if (percent != lastPercent) {
              lastPercent = percent;
              progress(step, 'running', '$percent%');
            }
          }
          return chunk;
        }),
      );
    } finally {
      await sink.close();
      hash?.close();
    }
    if (bytes != null && received != bytes) {
      throw InstallFailure(step, 'Incomplete download');
    }
    if (sha256 != null && _hex((await hash!.hash()).bytes) != sha256) {
      throw InstallFailure(step, 'download digest mismatch');
    }
    await partial.rename(target.path);
  }
}

Future<Hash> _hashFile(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return sink.hash();
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
