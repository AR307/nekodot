import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Screenshots of the local-desktop journey go to a private acceptance folder.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory(
      Platform.environment['NEKODOT_QA_SCREENSHOTS'] ?? '../../.runtime/local-desktop/evidence',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
);
