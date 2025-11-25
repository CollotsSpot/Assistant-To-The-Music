import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyAuthServerUrl = 'auth_server_url';
  static const String _keyWebSocketPort = 'websocket_port';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUsername = 'username';
  static const String _keyPassword = 'password';
  static const String _keyBuiltinPlayerId = 'builtin_player_id';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyUseMaterialTheme = 'use_material_theme';
  static const String _keyAdaptiveTheme = 'adaptive_theme';
  static const String _keyCustomColor = 'custom_color';

  static Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl);
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, url);
  }

  // Get authentication server URL (returns null if not set, meaning use server URL)
  static Future<String?> getAuthServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthServerUrl);
  }

  // Set authentication server URL (null means use same as server URL)
  static Future<void> setAuthServerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_keyAuthServerUrl);
    } else {
      await prefs.setString(_keyAuthServerUrl, url);
    }
  }

  // Get custom WebSocket port (null means use default logic)
  static Future<int?> getWebSocketPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyWebSocketPort);
  }

  // Set custom WebSocket port (null to use default logic)
  static Future<void> setWebSocketPort(int? port) async {
    final prefs = await SharedPreferences.getInstance();
    if (port == null) {
      await prefs.remove(_keyWebSocketPort);
    } else {
      await prefs.setInt(_keyWebSocketPort, port);
    }
  }

  // Get authentication token for stream requests
  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken);
  }

  // Set authentication token for stream requests
  static Future<void> setAuthToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_keyAuthToken);
    } else {
      await prefs.setString(_keyAuthToken, token);
    }
  }

  // Get username for authentication
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  // Set username for authentication
  static Future<void> setUsername(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    if (username == null || username.isEmpty) {
      await prefs.remove(_keyUsername);
    } else {
      await prefs.setString(_keyUsername, username);
    }
  }

  // Get password for authentication
  static Future<String?> getPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPassword);
  }

  // Set password for authentication
  static Future<void> setPassword(String? password) async {
    final prefs = await SharedPreferences.getInstance();
    if (password == null || password.isEmpty) {
      await prefs.remove(_keyPassword);
    } else {
      await prefs.setString(_keyPassword, password);
    }
  }

  // Get built-in player ID (persistent UUID for this device)
  static Future<String?> getBuiltinPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBuiltinPlayerId);
  }

  // Set built-in player ID
  static Future<void> setBuiltinPlayerId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBuiltinPlayerId, id);
  }

  // Theme settings
  static Future<String?> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  static Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  static Future<bool> getUseMaterialTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseMaterialTheme) ?? false;
  }

  static Future<void> saveUseMaterialTheme(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseMaterialTheme, enabled);
  }

  static Future<bool> getAdaptiveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAdaptiveTheme) ?? true; // Default to true
  }

  static Future<void> saveAdaptiveTheme(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdaptiveTheme, enabled);
  }

  static Future<String?> getCustomColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomColor);
  }

  static Future<void> saveCustomColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomColor, color);
  }

  static Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
