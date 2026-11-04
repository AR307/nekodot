import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class WindowsFileActions {
  static const channel = MethodChannel('app.nekodot/files');
  static Future<void> invoke(String action, String path) =>
      channel.invokeMethod<void>(action, {'path': path});
}

Future<void> openAttachment(String path, {bool chooseApp = false}) async {
  if (Platform.isWindows) {
    await WindowsFileActions.invoke(chooseApp ? 'openWith' : 'open', path);
  } else {
    if (!await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    )) {
      throw const FileSystemException('Could not open file');
    }
  }
}
