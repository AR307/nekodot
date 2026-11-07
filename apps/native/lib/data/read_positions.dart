import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local reading positions. No messages or cross-device receipts.
class ReadPositions extends ChangeNotifier {
  SharedPreferences? _prefs;
  String _prefix = '';
  final _values = <String, int>{};

  Future<void> load(String account) async {
    _prefs = await SharedPreferences.getInstance();
    _prefix = 'read:$account:';
    _values.clear();
    for (final key in _prefs!.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      _values[key.substring(_prefix.length)] = _prefs!.getInt(key)!;
    }
    notifyListeners();
  }

  Future<void> baseline(String node, int seq) async {
    if (_values.containsKey(node)) return;
    _values[node] = seq;
    await _prefs?.setInt('$_prefix$node', seq);
  }

  bool unread(String node, String conversation, int seq) =>
      (seq > latest(node, conversation) ? seq : latest(node, conversation)) >
      (_values['$node:$conversation'] ?? _values[node] ?? seq);

  int latest(String node, String conversation) =>
      _values['incoming:$node:$conversation'] ?? 0;

  int position(String node, String conversation) =>
      _values['$node:$conversation'] ?? _values[node] ?? 0;

  Future<void> received(String node, String conversation, int seq) async {
    final key = 'incoming:$node:$conversation';
    if (seq <= (_values[key] ?? _values[node] ?? seq)) return;
    _values[key] = seq;
    notifyListeners();
    await _prefs?.setInt('$_prefix$key', seq);
  }

  Future<void> viewed(String node, String conversation, int seq) async {
    final key = '$node:$conversation';
    if (seq <= (_values[key] ?? _values[node] ?? 0)) return;
    _values[key] = seq;
    notifyListeners();
    await _prefs?.setInt('$_prefix$key', seq);
  }
}
