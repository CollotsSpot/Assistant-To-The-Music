import 'package:shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyDefaultServer = 'music.serverscloud.org';

  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? _keyDefaultServer;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, url);
  }

  static Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
