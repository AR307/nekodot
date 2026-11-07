import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Isolated Release acceptance entrypoint, not included in product builds.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'language': 'zh',
    'theme': 'light',
    'notification-requested': true,
  });
  if (DesktopHost.supported) await DesktopHost.initialize();
  final client = NekodotClient(vault: MemoryVault());
  await client.login(
    const String.fromEnvironment('QA_EMAIL'),
    const String.fromEnvironment('QA_PASSWORD'),
  );
  await client.selectNode(const String.fromEnvironment('QA_NODE'));
  runApp(NekodotApp(client: client));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 23798);
  server.listen((request) async {
    if (request.uri.path == '/close') {
      request.response.write('closed');
      await request.response.close();
      await DesktopHost.quit();
      return;
    }
    final images = <Map<String, Object?>>[];
    void inspect(Element element) {
      final widget = element.widget;
      if (widget is RawImage && widget.image != null) {
        images.add({
          'width': widget.image!.width,
          'height': widget.image!.height,
        });
      }
      element.visitChildren(inspect);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(inspect);
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'rss': ProcessInfo.currentRss,
        'maxRss': ProcessInfo.maxRss,
        'open': client.node.messages.map(
          (id, rows) => MapEntry(id, rows.length),
        ),
        'visible': client.visibleConversation,
        'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
        'images': images,
      }),
    );
    await request.response.close();
  });
}
