import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/platform/file_actions.dart';

/// Runs inside the real Windows runner, so the native `app.nekodot/files` channel is the
/// product code. Each "attachment" only writes a marker file if it is ever executed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows never runs bot-delivered programs on Open and marks every copy',
    (tester) async {
      final folder = Directory(
        '${Directory.systemTemp.path}/nekodot-file-safety',
      );
      await folder.create(recursive: true);
      final marker = File('${folder.path}\\ran.txt');
      expect(
        marker.existsSync(),
        isFalse,
        reason: 'Preserve any prior failure evidence',
      );
      final payloads = {
        'payload.bat': '@echo ran> "${marker.path}"\r\n',
        'PAYLOAD.CMD': '@echo ran> "${marker.path}"\r\n',
        'payload.ps1': 'Set-Content -Path "${marker.path}" -Value ran\r\n',
        'payload.vbs':
            'CreateObject("Scripting.FileSystemObject").CreateTextFile("${marker.path}")\r\n',
        'payload.hta':
            '<script>new ActiveXObject("Scripting.FileSystemObject").CreateTextFile("${marker.path}")</script>',
        'shortcut.url': '[InternetShortcut]\r\nURL=file:///${marker.path}\r\n',
      };
      for (final entry in payloads.entries) {
        final copy = File('${folder.path}\\${entry.key}');
        await copy.writeAsString(entry.value, flush: true);
        await expectLater(
          WindowsFileActions.invoke('open', copy.path),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code for ${entry.key}',
              'blocked_type',
            ),
          ),
        );
        // Mark of the Web is written before the decision, for every action.
        final zone = await File('${copy.path}:Zone.Identifier').readAsString();
        expect(zone, contains('ZoneId=3'), reason: entry.key);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(marker.existsSync(), isFalse, reason: 'no payload may execute');
    },
    skip: !Platform.isWindows,
  );
}
