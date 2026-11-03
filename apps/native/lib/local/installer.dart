import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'location.dart';
import 'owned_process.dart';
import 'system.dart';

/// Official Hermes v0.22.6 installers, fetched at the pinned commit and checked byte for byte.
const _installerSha256 = {
  'install.ps1':
      '4ab816db4cc94ca4984e11f19559cb106ff00f857c8dfec54874401cfca7f7b3',
  'install.sh':
      'abf338605dae6dd28d101673ac6aed7995c955745db46d47676bc591a7957209',
};
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

/// Runtime steps in order. Official Hermes stages keep their protocol names; `setup` and
/// `gateway` are never run (interactive configuration, system service installation).
const runtimeSteps = [
  'node',
  'installer',
  'prerequisites',
  'repository',
  'venv',
  'python-deps',
  'config',
  'products',
  'complete',
  'verify',
];

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
  OwnedProcess? _current;
  bool _cancelled = false;

  RuntimeInstaller(this.location, this.platform, this.web, this.progress);

  String get _scripts => joinPath(location.runtime, 'installer');
  Map<String, String> _environment(String home) => isolatedEnvironment({
    'HERMES_HOME': home,
    'UV_PYTHON_INSTALL_DIR': joinPath(location.owner, 'cache', 'uv-python'),
    'UV_CACHE_DIR': joinPath(location.owner, 'cache', 'uv'),
  });

  void cancel() {
    _cancelled = true;
    _current?.kill();
  }

  /// Installs or resumes the shared runtime; completed steps are kept across retries.
  Future<void> run() async {
    final done = await location.completed();
    await Directory(location.logs).create(recursive: true);
    for (final step in runtimeSteps) {
      if (_cancelled) throw InstallFailure(step, 'cancelled');
      if (done.contains(step) && step != 'installer' && step != 'verify') {
        progress(step, 'done', '');
        continue;
      }
      progress(step, 'running', '');
      switch (step) {
        case 'node':
          await _node();
        case 'installer':
          await _installer();
        case 'verify':
          await _verify();
        default:
          await stage(step, location.owner);
      }
      done.add(step);
      await location.record(done);
      progress(step, 'done', '');
    }
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

  Future<void> _installer() async {
    await Directory(_scripts).create(recursive: true);
    final name = Platform.isWindows ? 'install.ps1' : 'install.sh';
    final response = await web
        .get(
          Uri.parse(
            'https://raw.githubusercontent.com/NousResearch/hermes-agent/$hermesCommit/scripts/$name',
          ),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw InstallFailure('installer', 'HTTP ${response.statusCode}');
    }
    final digest = await Sha256().hash(response.bodyBytes);
    if (_hex(digest.bytes) != _installerSha256[name]) {
      throw const InstallFailure('installer', 'installer digest mismatch');
    }
    // Windows PowerShell 5.1 reads a -File script in the ANSI code page unless it has a BOM.
    final bom = Platform.isWindows ? const [0xEF, 0xBB, 0xBF] : const <int>[];
    await File(joinPath(_scripts, name))
        .writeAsBytes([...bom, ...response.bodyBytes]);
    await File(
      joinPath(_scripts, Platform.isWindows ? 'products.ps1' : 'products.sh'),
    ).writeAsBytes([
      ...bom,
      ...utf8.encode(Platform.isWindows ? _productsPs1 : _productsSh),
    ]);
  }

  /// Runs one official protocol-1 stage and reads its final JSON frame.
  Future<void> stage(String name, String home) async {
    final installer = joinPath(
      _scripts,
      Platform.isWindows ? 'install.ps1' : 'install.sh',
    );
    final List<String> command;
    if (name == 'products') {
      // The official stage also rewrites the user PATH / shell profiles; this runs the same
      // build through the installer's own functions without publishing a user command.
      command = Platform.isWindows
          ? [
              ..._powershell,
              joinPath(_scripts, 'products.ps1'),
              '-Installer',
              installer,
              '-HermesHome',
              home,
              '-InstallDir',
              location.checkout,
            ]
          : [
              'bash',
              joinPath(_scripts, 'products.sh'),
              installer,
              home,
              location.checkout,
            ];
    } else {
      command = Platform.isWindows
          ? [
              ..._powershell,
              installer,
              '-Stage',
              name,
              '-Json',
              '-NonInteractive',
              '-Commit',
              hermesCommit,
              '-Branch',
              'main',
              '-HermesHome',
              home,
              '-InstallDir',
              location.checkout,
            ]
          : [
              'bash',
              installer,
              '--stage',
              name,
              '--json',
              '--non-interactive',
              '--commit',
              hermesCommit,
              '--branch',
              'main',
              '--hermes-home',
              home,
              '--dir',
              location.checkout,
            ];
    }
    final log = File(joinPath(location.logs, 'install-$name.log'))
        .openWrite(mode: FileMode.append);
    log.writeln('--- ${DateTime.now().toIso8601String()} ${command.join(' ')}');
    try {
      final process = _current = await OwnedProcess.start(
        command.first,
        command.sublist(1),
        workingDirectory: location.runtime,
        environment: _environment(home),
        log: log,
      );
      process.lines.listen((line) {
        if (line.trim().isNotEmpty && !line.startsWith('{')) {
          progress(name, 'running', line.trim());
        }
      });
      final code = await process.exitCode;
      Map<String, dynamic>? frame;
      for (final line in process.tail.reversed) {
        try {
          final value = jsonDecode(line);
          if (value is Map<String, dynamic> &&
              value.containsKey('ok') &&
              value['stage'] == name) {
            frame = value;
            break;
          }
        } on FormatException {
          continue;
        }
      }
      if (_cancelled) throw InstallFailure(name, 'cancelled');
      if (frame?['ok'] != true || code != 0) {
        throw InstallFailure(
          name,
          '${frame?['reason'] ?? process.tail.where((l) => l.trim().isNotEmpty).lastOrNull ?? 'exit $code'}',
        );
      }
    } finally {
      _current = null;
      await log.close();
    }
  }

  Future<void> _verify() async {
    if (!await File(location.launcher).exists()) {
      throw InstallFailure(
        'verify',
        'Hermes launcher missing: ${location.launcher}',
      );
    }
    final result = await runOwned(
      location.launcher,
      ['--version'],
      workingDirectory: location.owner,
      environment: _environment(location.owner),
    );
    if (result.code != 0) throw InstallFailure('verify', result.output);
  }

  Future<void> _download(
    String step,
    Uri url,
    File target,
    String sha256,
  ) async {
    if (await target.exists() &&
        _hex((await _hashFile(target)).bytes) == sha256) {
      return;
    }
    final partial = File('${target.path}.part');
    final response = await web.send(http.Request('GET', url));
    if (response.statusCode != 200) {
      throw InstallFailure(step, 'HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    final sink = partial.openWrite();
    final hash = Sha256().newHashSink();
    var received = 0;
    await for (final chunk in response.stream) {
      if (_cancelled) {
        await sink.close();
        throw InstallFailure(step, 'cancelled');
      }
      sink.add(chunk);
      hash.add(chunk);
      received += chunk.length;
      if (total > 0) progress(step, 'running', '${received * 100 ~/ total}%');
    }
    await sink.close();
    hash.close();
    if (_hex((await hash.hash()).bytes) != sha256) {
      throw InstallFailure(step, 'download digest mismatch');
    }
    await partial.rename(target.path);
  }

  static List<String> get _powershell => [
    windowsTool(r'WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
  ];
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

/// Loads install.ps1's definitions (it stops before running anything when dot-sourced) and
/// runs its own source completion, without Publish-UserCommand.
const _productsPs1 = r'''
param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$HermesHome,
  [Parameter(Mandatory = $true)][string]$InstallDir
)
$ErrorActionPreference = "Stop"
. $Installer -HermesHome $HermesHome -InstallDir $InstallDir -NonInteractive -Json
Initialize-ResolvedPaths
$env:UV_NO_CONFIG = "1"
try {
  Invoke-SourceCompletion $false
  Emit-Frame $true "products" $false
  exit 0
} catch {
  Write-Err "$_"
  Emit-Frame $false "products" $false "$_"
  exit 1
}
''';

/// POSIX counterpart; completed in the macOS/Linux module.
const _productsSh = r'''
#!/usr/bin/env bash
printf '%s\n' '{"ok":false,"stage":"products","skipped":false,"reason":"not available on this platform yet"}'
exit 1
''';
