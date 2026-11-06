import 'dart:convert';
import 'dart:io';

import 'system.dart';

const hermesVersion = 'v0.22.6';
const hermesCommit = 'f0d94882e89ab8d4098b5bb2f166adfb9ee0a0ab';
const hermesRuntimeVersion = 'v0.22.6-r1';
const nodeVersion = '24.22.1';

/// Free space a fresh runtime needs (Python, Node, Chromium, computer-use driver, built products).
const runtimeSpace = 6 * 1024 * 1024 * 1024;
const dataSpace = 1024 * 1024 * 1024;

const runtimeMarker = 'nekodot-runtime.json';
const dataMarker = 'nekodot-data.json';

/// The two folders the user chose. Only this pointer stays in the system app-data folder.
class LocalLocation {
  final String runtime, data;
  const LocalLocation(this.runtime, this.data);

  static Future<File> _pointer() async =>
      File(joinPath((await appSupportDirectory()).path, 'local-runtime.json'));

  static Future<LocalLocation?> load() async {
    final file = await _pointer();
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return LocalLocation(value['runtime'] as String, value['data'] as String);
  }

  static Future<LocalLocation> defaults() async {
    final base = (await appSupportDirectory()).path;
    return LocalLocation(joinPath(base, 'runtime'), joinPath(base, 'data'));
  }

  Future<void> save() async {
    final file = await _pointer();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'runtime': runtime, 'data': data}));
  }

  String get owner => joinPath(runtime, 'bootstrap-home');
  String get payload =>
      joinPath(runtime, 'hermes-runtimes', hermesRuntimeVersion);
  String get checkout => joinPath(payload, 'hermes-agent');
  String get tools => joinPath(payload, 'tools');
  String get cache => joinPath(runtime, 'cache', 'uv');
  String get logs => joinPath(runtime, 'logs');
  String get nodeRoot =>
      joinPath(runtime, 'node', 'node-v$nodeVersion-${_nodeTarget()}');
  String get nodeExecutable => Platform.isWindows
      ? joinPath(nodeRoot, 'node.exe')
      : joinPath(nodeRoot, 'bin', 'node');
  String get launcher => Platform.isWindows
      ? joinPath(payload, 'bin', 'hermes.exe')
      : joinPath(payload, 'bin', 'hermes');
  File get manifest => File(joinPath(runtime, runtimeMarker));
  String account(String userId) => joinPath(data, 'accounts', userId);

  Future<Set<String>> completed() async {
    if (!await manifest.exists()) return {};
    final value =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    if (value['hermes']?['runtime'] != hermesRuntimeVersion) return {};
    return {...(value['done'] as List? ?? []).cast<String>()};
  }

  Future<void> record(Set<String> done) => manifest.writeAsString(
    jsonEncode({
      'schema': 1,
      'hermes': {
        'version': hermesVersion,
        'commit': hermesCommit,
        'runtime': hermesRuntimeVersion,
      },
      'node': nodeVersion,
      'done': [...done],
    }),
  );
}

String _nodeTarget() => Platform.isWindows
    ? 'win-x64'
    : Platform.isMacOS
    ? 'darwin-arm64'
    : 'linux-x64';

enum FolderKind { runtime, data }

/// Why a folder cannot be used; `null` problem means it can.
class FolderCheck {
  final String path;
  final int? free;
  final String? problem;
  final bool existing;
  const FolderCheck(this.path, this.free, this.problem, this.existing);
}

Future<FolderCheck> checkFolder(String path, FolderKind kind) async {
  final marker = kind == FolderKind.runtime ? runtimeMarker : dataMarker;
  final free = await freeBytes(path);
  FolderCheck fail(String problem) => FolderCheck(path, free, problem, false);
  if (!File(path).isAbsolute) return fail('relative');
  final installed = File(Platform.resolvedExecutable).parent.absolute.path
      .toLowerCase();
  final chosen = Directory(path).absolute.path.toLowerCase();
  if (chosen == installed ||
      chosen.startsWith(installed + Platform.pathSeparator)) {
    return fail('install-dir');
  }
  if (!isFixedDisk(path)) return fail('not-fixed');
  final directory = Directory(path);
  final existing = await File(joinPath(path, marker)).exists();
  if (!existing &&
      await directory.exists() &&
      !await directory.list().isEmpty) {
    return fail('not-empty');
  }
  final need = kind == FolderKind.runtime ? runtimeSpace : dataSpace;
  if (!existing && free != null && free < need) return fail('space');
  return FolderCheck(path, free, null, existing);
}

/// Creates the folder privately and writes its marker, which also proves it is writable.
Future<void> prepareFolder(String path, FolderKind kind) async {
  final directory = Directory(path);
  final marker = File(
    joinPath(path, kind == FolderKind.runtime ? runtimeMarker : dataMarker),
  );
  if (await marker.exists()) return;
  final fresh = !await directory.exists() || await directory.list().isEmpty;
  await directory.create(recursive: true);
  if (fresh) await makePrivate(directory);
  await marker.writeAsString(
    kind == FolderKind.runtime
        ? jsonEncode({'schema': 1, 'done': []})
        : jsonEncode({'schema': 1}),
  );
}
