import 'package:http/http.dart' as http;
import 'dart:convert';
import 'debug_logger.dart';
import 'settings_service.dart';

class AuthService {
  final _logger = DebugLogger();

  /// Authenticate with the server and get session cookie
  Future<String?> login(String serverUrl, String username, String password) async {
    try {
      _logger.log('🔐 Attempting login to $serverUrl');

      // Determine base URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      // Parse URL
      final uri = Uri.parse(baseUrl);
      final authUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/verify',
      );

      _logger.log('Auth URL: $authUrl');

      // Try basic authentication first
      final response = await http.get(
        authUrl,
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        },
      ).timeout(const Duration(seconds: 10));

      _logger.log('Auth response status: ${response.statusCode}');

      // Check for session cookies
      final cookies = response.headers['set-cookie'];
      if (cookies != null && cookies.isNotEmpty) {
        _logger.log('✓ Received session cookie');

        // Extract authelia_session cookie if present
        final sessionCookie = _extractSessionCookie(cookies);
        if (sessionCookie != null) {
          _logger.log('✓ Extracted session cookie');
          await SettingsService.setAuthToken(sessionCookie);
          return sessionCookie;
        }
      }

      // If no cookie, check if authentication was successful
      if (response.statusCode == 200) {
        _logger.log('✓ Authentication successful (no cookie needed)');
        return 'authenticated';
      }

      _logger.log('✗ Authentication failed: ${response.statusCode}');
      _logger.log('Response: ${response.body}');
      return null;
    } catch (e) {
      _logger.log('✗ Login error: $e');
      return null;
    }
  }

  String? _extractSessionCookie(String setCookieHeader) {
    // Parse Set-Cookie header to extract authelia_session value
    final cookies = setCookieHeader.split(',');

    for (final cookie in cookies) {
      if (cookie.trim().startsWith('authelia_session=')) {
        final parts = cookie.split(';');
        if (parts.isNotEmpty) {
          final value = parts[0].trim();
          if (value.startsWith('authelia_session=')) {
            return value.substring('authelia_session='.length);
          }
        }
      }
    }

    return null;
  }

  /// Test if current credentials/token work
  Future<bool> testAuthentication(String serverUrl) async {
    try {
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      final uri = Uri.parse(baseUrl);
      final testUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/verify',
      );

      final token = await SettingsService.getAuthToken();
      final headers = <String, String>{};

      if (token != null && token != 'authenticated') {
        headers['Cookie'] = 'authelia_session=$token';
      }

      final response = await http.get(
        testUrl,
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      _logger.log('Auth test failed: $e');
      return false;
    }
  }
}
