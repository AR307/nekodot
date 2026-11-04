import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'owned_process.dart';

/// The desktop systems a local node supports in this release.
enum LocalPlatform { windows, macos, linux }

class LocalSupport {
  final LocalPlatform? platform;
  final String reason;
  const LocalSupport(this.platform, [this.reason = '']);
  bool get supported => platform != null;
}

Future<LocalSupport> localSupport() async {
  final abi = Abi.current();
  if (abi == Abi.windowsX64) return const LocalSupport(LocalPlatform.windows);
  if (abi == Abi.macosArm64) return const LocalSupport(LocalPlatform.macos);
  if (abi == Abi.linuxX64) {
    final release = await File('/etc/os-release')
        .readAsString()
        .catchError((_) => '');
    final ubuntu2404 =
        RegExp(r'^ID=ubuntu$', multiLine: true).hasMatch(release) &&
        RegExp(r'^VERSION_ID="?24\.04"?$', multiLine: true).hasMatch(release);
    return ubuntu2404
        ? const LocalSupport(LocalPlatform.linux)
        : const LocalSupport(null, 'linux-distribution');
  }
  return LocalSupport(null, abi.toString());
}

/// Where the tiny pointer file lives; everything large goes to user-chosen folders.
Future<Directory> appSupportDirectory() async => Platform.isWindows
    ? Directory('${Platform.environment['LOCALAPPDATA']}\\app.nekodot.client')
    : await getApplicationSupportDirectory();

String joinPath(String base, String a, [String? b, String? c]) =>
    [base, a, ?b, ?c].join(Platform.pathSeparator);

/// The nearest existing directory at or above [path].
Directory existingAncestor(String path) {
  var directory = Directory(path).absolute;
  while (!directory.existsSync() && directory.parent.path != directory.path) {
    directory = directory.parent;
  }
  return directory;
}

/// Free bytes for the volume holding [path], or null when the system cannot tell.
Future<int?> freeBytes(String path) async {
  final directory = existingAncestor(path).path;
  if (Platform.isWindows) {
    return using((arena) {
      final free = arena<Uint64>();
      final ok = _getDiskFreeSpaceEx(
        directory.toNativeUtf16(allocator: arena),
        free,
        nullptr,
        nullptr,
      );
      return ok == 0 ? null : free.value;
    });
  }
  final result = await Process.run('df', ['-Pk', directory]);
  final lines = '${result.stdout}'.trim().split('\n');
  if (result.exitCode != 0 || lines.length < 2) return null;
  final available = int.tryParse(lines.last.split(RegExp(r'\s+'))[3]);
  return available == null ? null : available * 1024;
}

/// Local fixed disks only: network, removable and optical volumes can disappear under a node.
bool isFixedDisk(String path) {
  if (!Platform.isWindows) return true;
  final match = RegExp(r'^([A-Za-z]):[\\/]').firstMatch(path);
  if (match == null) return false;
  return using(
    (arena) =>
        _getDriveType('${match[1]}:\\'.toNativeUtf16(allocator: arena)) == 3,
  );
}

/// Makes a folder nekoDOT created readable only by this user (plus SYSTEM and Administrators on
/// Windows, matching the DACL Hermes gives its own private directories).
Future<void> makePrivate(Directory directory) async {
  if (!Platform.isWindows) {
    await Process.run('chmod', ['700', directory.path]);
    return;
  }
  final who = await runOwned(_system32('whoami.exe'), [
    '/user',
    '/fo',
    'csv',
    '/nh',
  ]);
  final sid = RegExp(r'"(S-1-[0-9-]+)"').firstMatch(who.output)?[1];
  if (who.code != 0 || sid == null) {
    throw const FileSystemException('Cannot read the user SID');
  }
  final acl = await runOwned(_system32('icacls.exe'), [
    directory.path,
    '/inheritance:r',
    '/grant:r',
    '*$sid:(OI)(CI)F',
    '*S-1-5-18:(OI)(CI)F',
    '*S-1-5-32-544:(OI)(CI)F',
  ]);
  if (acl.code != 0) {
    throw FileSystemException('Cannot restrict folder access', directory.path);
  }
}

String _system32(String name) =>
    '${Platform.environment['SystemRoot']}\\System32\\$name';
String windowsTool(String name) => _system32(name);

final _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : null;
final _getDiskFreeSpaceEx = _kernel32!
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      )
    >('GetDiskFreeSpaceExW');
final _getDriveType = _kernel32!
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('GetDriveTypeW');
