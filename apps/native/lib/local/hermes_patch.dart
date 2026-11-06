import 'dart:io';

import 'location.dart';
import 'system.dart';

/// Approved install-only fix for v0.22.6: extend paths at the copy syscall,
/// never in HERMES_HOME, environment records, or profile identity comparisons.
Future<void> patchWindowsHermesWorkspace(LocalLocation location) async {
  if (!Platform.isWindows) return;
  final file = File(joinPath(location.checkout, 'pm', 'workspace.py'));
  final source = await file.readAsString();
  const replacements = {
    'from pm import paths':
        'from pm import paths\nfrom pm.filesystem import long_root',
    'shutil.copytree(entry, target,':
        'shutil.copytree(long_root(entry), long_root(target),',
    'shutil.copy2(entry, target)':
        'shutil.copy2(long_root(entry), long_root(target))',
    'shutil.copytree(plugin_dir, member,':
        'shutil.copytree(long_root(plugin_dir), long_root(member),',
    'shutil.copytree(replay, root,':
        'shutil.copytree(long_root(replay), long_root(root),',
  };
  var patched = source;
  for (final entry in replacements.entries) {
    if (patched.contains(entry.value)) continue;
    if (!patched.contains(entry.key)) {
      throw FileSystemException(
        'Hermes workspace patch does not match',
        file.path,
      );
    }
    patched = patched.replaceAll(entry.key, entry.value);
  }
  if (patched == source) return;
  final backup = File(joinPath(location.logs, 'workspace-before-long-path.py'));
  if (!await backup.exists()) await backup.writeAsString(source);
  await file.writeAsString(patched);
}
