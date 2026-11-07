import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'json.dart';

/// Last confirmed product data, never an alternative server or credential store.
class LocalContent {
  final Directory directory;
  Future<void> _writes = Future.value();
  LocalContent(this.directory);
  static String key(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  static Future<LocalContent> open(String origin, String userId) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/content/${key(origin)}/${key(userId)}');
    await dir.create(recursive: true);
    return LocalContent(dir);
  }

  File file(String name) => File('${directory.path}/$name');
  Future<Json?> read(String name) async {
    await _writes;
    final f = file('$name.json');
    if (!await f.exists()) return null;
    return object(jsonDecode(await f.readAsString()));
  }

  Future<void> write(String name, Json value) {
    final text = jsonEncode(value);
    final work = _writes.then((_) async {
      final target = file('$name.json');
      await target.parent.create(recursive: true);
      final staged = file('$name.pending');
      await staged.writeAsString(text, flush: true);
      await staged.rename(target.path);
    });
    _writes = work.catchError((Object _) {});
    return work;
  }
}
