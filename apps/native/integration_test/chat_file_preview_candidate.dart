import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Native acceptance only: actual app, real isolated account, no product hooks.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'language': 'zh',
    'theme': 'light',
    'notification-requested': true,
  });
  await DesktopHost.initialize();
  await windowManager.setTitle('nekodot · Files QA');
  final client = NekodotClient(vault: MemoryVault());
  await client.login(
    const String.fromEnvironment('QA_EMAIL'),
    const String.fromEnvironment('QA_PASSWORD'),
  );
  await client.selectNode(const String.fromEnvironment('QA_NODE'));
  runApp(NekodotApp(client: client));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 23797);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'conversation': client.visibleConversation,
        'attachments': client.attachmentDrafts.map(
          (id, files) => MapEntry(
            id,
            files.map((f) => {'name': f['name'], 'size': f['size']}).toList(),
          ),
        ),
        'deliveryCount': client.deliveries.items.length,
        'rss': ProcessInfo.currentRss,
      }),
    );
    await request.response.close();
  });
}
