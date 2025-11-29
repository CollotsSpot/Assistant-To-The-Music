import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';

/// Basic HTTP Authentication strategy
/// Used by reverse proxies (nginx, Apache, Caddy, etc.) configured with basic auth
/// Example: Authorization: Basic base64(username:password)
class BasicAuthStrategy implements AuthStrategy {
  @override
  String get name => 'basic';

  @override
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    // Encode credentials to base64
    final credentials = base64Encode(utf8.encode('$username:$password'));

    // Test credentials against server root endpoint
    // (Music Assistant doesn't have /api/info)
    try {
      final response = await http.get(
        Uri.parse(serverUrl),
        headers: {'Authorization': 'Basic $credentials'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return AuthCredentials('basic', {
          'credentials': credentials,
          'username': username, // Store for re-login if needed
        });
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    final base64Creds = credentials.data['credentials'] as String?;
    if (base64Creds == null) return false;

    try {
      final response = await http.get(
        Uri.parse(serverUrl),
        headers: {'Authorization': 'Basic $base64Creds'},
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    final base64Creds = credentials.data['credentials'] as String;
    return {'Authorization': 'Basic $base64Creds'};
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    final base64Creds = credentials.data['credentials'] as String;
    return {'Authorization': 'Basic $base64Creds'};
  }

  @override
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials) {
    return credentials.data;
  }

  @override
  AuthCredentials deserializeCredentials(Map<String, dynamic> data) {
    return AuthCredentials('basic', data);
  }
}
