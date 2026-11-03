import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/client.dart';
import 'desktop.dart';

const _channel = MethodChannel('app.nekodot/updates');

class InstalledVersion {
  final String version;
  final int build;
  const InstalledVersion(this.version, this.build);
  static Future<InstalledVersion> read() async {
    final info = (await _channel.invokeMapMethod<String, dynamic>('version'))!;
    return InstalledVersion(info['version'] as String, info['build'] as int);
  }

  @override
  String toString() => '$version ($build)';
}

class ProductRelease {
  final String version, notes;
  final int build, size;
  final Uri download;
  ProductRelease(Json json, Uri origin)
    : version = json['version'] as String,
      build =
          json['artifacts'][Platform.isWindows ? 'windows' : 'android']['build']
              as int,
      notes = json['notes'] as String,
      size =
          (json['artifacts'][Platform.isWindows ? 'windows' : 'android']['size']
                  as num)
              .toInt(),
      download = origin.resolve(
        '/downloads/${json['artifacts'][Platform.isWindows ? 'windows' : 'android']['path']}',
      ) {
    if (json['schema'] != 1 || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const FormatException('Invalid release metadata');
    }
    if (download.origin != origin.origin ||
        (download.scheme != 'https' &&
            !['127.0.0.1', 'localhost'].contains(download.host))) {
      throw const FormatException(
        'Updates require the configured HTTPS server',
      );
    }
  }

  bool newerThan(InstalledVersion current) {
    final next = version.split('.').map(int.parse).toList();
    final installed = current.version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (next[i] != installed[i]) return next[i] > installed[i];
    }
    return build > current.build;
  }
}

/// Downloads incrementally to the app cache, without keeping the package in RAM.
Future<File> downloadUpdate(
  ProductRelease release,
  void Function(double) progress,
) async {
  final directory = await getTemporaryDirectory();
  final folder = Directory('${directory.path}/updates');
  await folder.create(recursive: true);
  final file = File(
    '${folder.path}/nekodot-${release.version}-${release.build}.${Platform.isWindows ? 'exe' : 'apk'}',
  );
  final client = http.Client();
  final sink = file.openWrite();
  try {
    final response = await client
        .send(http.Request('GET', release.download)..followRedirects = false)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Download HTTP ${response.statusCode}');
    }
    var received = 0;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 60),
    )) {
      sink.add(chunk);
      received += chunk.length;
      progress((received / release.size).clamp(0, 1));
    }
    if (received != release.size) {
      throw const HttpException('Download interrupted; please retry');
    }
    await sink.flush();
    return file;
  } finally {
    await sink.close();
    client.close();
  }
}

Future<bool> canInstallUpdate() async =>
    !Platform.isAndroid ||
    await _channel.invokeMethod<bool>('canInstall') == true;

Future<void> openInstallPermission() =>
    _channel.invokeMethod('installPermission');

Future<void> installUpdate(File file) async {
  if (Platform.isWindows) {
    await Process.start(file.path, [], mode: ProcessStartMode.detached);
    await DesktopHost.quit();
  } else {
    await _channel.invokeMethod('install', {'path': file.path});
  }
}
