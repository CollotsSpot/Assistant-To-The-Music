import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyAuthServerUrl = 'auth_server_url';
  static const String _keyWebSocketPort = 'websocket_port';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyMaAuthToken = 'ma_auth_token'; // Music Assistant native auth token
  static const String _keyAuthCredentials = 'auth_credentials'; // NEW: Serialized auth strategy credentials
  static const String _keyUsername = 'username';
  static const String _keyPassword = 'password';
  static const String _keyBuiltinPlayerId = 'local_player_id'; // Unified with DeviceIdService
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyUseMaterialTheme = 'use_material_theme';
  static const String _keyAdaptiveTheme = 'adaptive_theme';
  static const String _keyCustomColor = 'custom_color';
  static const String _keyLastFmApiKey = 'lastfm_api_key';
  static const String _keyTheAudioDbApiKey = 'theaudiodb_api_key';
  static const String _keyEnableLocalPlayback = 'enable_local_playback';
  static const String _keyLocalPlayerName = 'local_player_name';
  static const String _keyOwnerName = 'owner_name';
  static const String _keyLastSelectedPlayerId = 'last_selected_player_id';

  static Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl);
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, url);
  }

  static Future<void> clearServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServerUrl);
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

  // Get Music Assistant native auth token (long-lived token)
  static Future<String?> getMaAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMaAuthToken);
  }

  // Set Music Assistant native auth token (long-lived token)
  static Future<void> setMaAuthToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_keyMaAuthToken);
    } else {
      await prefs.setString(_keyMaAuthToken, token);
    }
  }

  // Clear Music Assistant native auth token
  static Future<void> clearMaAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMaAuthToken);
  }

  // Get authentication credentials (serialized auth strategy credentials)
  static Future<Map<String, dynamic>?> getAuthCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyAuthCredentials);
    if (json == null) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  // Set authentication credentials (serialized auth strategy credentials)
  static Future<void> setAuthCredentials(Map<String, dynamic> credentials) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthCredentials, jsonEncode(credentials));
  }

  // Clear authentication credentials
  static Future<void> clearAuthCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAuthCredentials);
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

  // Metadata API Keys
  static Future<String?> getLastFmApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastFmApiKey);
  }

  static Future<void> setLastFmApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await prefs.remove(_keyLastFmApiKey);
    } else {
      await prefs.setString(_keyLastFmApiKey, key);
    }
  }

  static Future<String?> getTheAudioDbApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTheAudioDbApiKey);
  }

  static Future<void> setTheAudioDbApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await prefs.remove(_keyTheAudioDbApiKey);
    } else {
      await prefs.setString(_keyTheAudioDbApiKey, key);
    }
  }

  // Local Playback Settings
  static Future<bool> getEnableLocalPlayback() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableLocalPlayback) ?? true;
  }

  static Future<void> setEnableLocalPlayback(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableLocalPlayback, enabled);
  }

  static Future<String> getLocalPlayerName() async {
    // Derive player name from owner name
    final ownerName = await getOwnerName();
    if (ownerName != null && ownerName.isNotEmpty) {
      return _makePlayerName(ownerName);
    }

    // Fallback to stored local player name or default
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalPlayerName) ?? 'Ensemble';
  }

  static Future<void> setLocalPlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocalPlayerName, name);
  }

  // Owner Name - used to derive player name
  static Future<String?> getOwnerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOwnerName);
  }

  static Future<void> setOwnerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOwnerName, name.trim());
  }

  // Last selected player ID - persists user's player selection across sessions
  static Future<String?> getLastSelectedPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSelectedPlayerId);
  }

  static Future<void> setLastSelectedPlayerId(String? playerId) async {
    final prefs = await SharedPreferences.getInstance();
    if (playerId == null || playerId.isEmpty) {
      await prefs.remove(_keyLastSelectedPlayerId);
    } else {
      await prefs.setString(_keyLastSelectedPlayerId, playerId);
    }
  }

  // Helper to create player name with possessive apostrophe
  static String _makePlayerName(String ownerName) {
    // Handle possessive: "Chris" -> "Chris' Phone", "Mom" -> "Mom's Phone"
    if (ownerName.toLowerCase().endsWith('s')) {
      return "$ownerName' Phone";
    } else {
      return "$ownerName's Phone";
    }
  }

  static Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
