import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientPreferences extends ChangeNotifier {
  String language = 'zh', theme = 'system';

  /// The desktop sidebar's width once the user has dragged it.
  double? sidebarWidth;
  final chatDisplay = <String, bool>{
    'focus': false,
    'density': false,
    'timestamps': false,
    'statusbar': false,
    'battery': false,
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? 'zh';
    theme = prefs.getString('theme') ?? 'system';
    sidebarWidth = prefs.getDouble('sidebar-width');
    for (final key in chatDisplay.keys) {
      chatDisplay[key] = prefs.getBool('chat-$key') ?? false;
    }
  }

  Future<void> update({String? locale, String? appearance}) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale != null) {
      language = locale;
      await prefs.setString('language', locale);
    }
    if (appearance != null) {
      theme = appearance;
      await prefs.setString('theme', appearance);
    }
    notifyListeners();
  }

  Future<void> setChatDisplay(String key, bool enabled) async {
    chatDisplay[key] = enabled;
    await (await SharedPreferences.getInstance()).setBool('chat-$key', enabled);
    notifyListeners();
  }

  Future<void> setSidebarWidth(double width) async {
    sidebarWidth = width;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(
      'sidebar-width',
      width,
    );
  }
}
