import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/local/installer.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/system.dart';

const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const evidenceFolder = String.fromEnvironment('QA_EVIDENCE_DIR');
const legacyPython = String.fromEnvironment('QA_LEGACY_PYTHON');
const pythonHome = String.fromEnvironment('QA_PYTHON_HOME');
const copyRoot = String.fromEnvironment('QA_COPY_ROOT');
const pmHome = String.fromEnvironment('QA_PM_HOME');

/// Real legacy Win32 file I/O against the backend package's approved copy-only
/// patch, followed by preparing an account through the packaged launcher.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Hermes installation beyond Windows MAX_PATH', (tester) async {
    expect(Platform.isWindows, isTrue);
    final report = <String, Object?>{};
    await Directory(evidenceFolder).create(recursive: true);
    void note(String key, Object? value) {
      report[key] = value;
      debugPrint('QA $key: ${jsonEncode(value)}');
    }

    final location = LocalLocation(runtimeFolder, dataFolder);
    const suffix =
        'accounts/dba6baf7-727f-4b6d-82c4-2b8d31a4a453/hermes/installs/'
        '90eec3eeb3c038e1/environments/3e64519d253a4bcca91e3e026b98e5cc/'
        'workspace';
    const copyScript = '''
import json, pathlib, shutil, sys
checkout, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
relative = pathlib.Path('plugins/config_backends/remote/vendor/conformance/config-resolution')
sys.path.insert(0, str(checkout))
try:
    if sys.argv[3] == 'fixed':
        from pm.workspace import _copy_core_inputs
        _copy_core_inputs(checkout, target)
    else:
        shutil.copytree(checkout / relative, target / relative)
    from pm.filesystem import long_root
    files = list(long_root(target / relative).glob('*.json'))
    print(json.dumps({'ok': True, 'files': len(files), 'longest': max(len(str(p)) for p in files)}))
except shutil.Error as error:
    failures = error.args[0]
    print(json.dumps({'ok': False, 'count': len(failures), 'winerror3': any('[WinError 3]' in item[2] for item in failures), 'longest': max(len(item[1]) for item in failures)}))
''';
    for (final fixed in [false, true]) {
      final target = copyRoot + (fixed ? '/fixed/' : '/plain/') + suffix;
      final result = await tester.runAsync(
        () => Process.run(
          legacyPython,
          [
            '-X',
            'utf8',
            '-c',
            copyScript,
            location.checkout,
            target.replaceAll('/', Platform.pathSeparator),
            fixed ? 'fixed' : 'plain',
          ],
          environment: isolatedEnvironment({'PYTHONHOME': pythonHome}),
          includeParentEnvironment: false,
        ),
      );
      expect(result!.exitCode, 0, reason: result.stderr.toString());
      final value =
          jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      note(fixed ? 'extendedCopy' : 'ordinaryCopy', value);
      expect(value['ok'], fixed);
      if (fixed) {
        expect(value['files'], greaterThan(40));
        expect(value['longest'], greaterThan(260));
      } else {
        expect(value['winerror3'], isTrue);
      }
    }

    final web = http.Client();
    addTearDown(web.close);
    final installer = RuntimeInstaller(
      location,
      LocalPlatform.windows,
      web,
      (step, state, detail) => debugPrint('QA install $step $state $detail'),
      origin: Uri.parse(const String.fromEnvironment('RELAY_URL')),
    );
    await tester.runAsync(() async {
      await installer.run();
      await Directory(pmHome).create(recursive: true);
      await installer.prepareAccount(pmHome);
      note('runtimeAccountPreparation', 'passed');
      await installer.prepareAccount(pmHome);
      note('runtimeAccountRetry', 'passed');
      await File('$evidenceFolder/windows-long-path-install.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
