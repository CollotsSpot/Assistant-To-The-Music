import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import '../debug_logger.dart';

/// Music Assistant native authentication strategy
/// Used when MA server has built-in authentication enabled (schema 28+)
///
/// Flow:
/// 1. Connect WebSocket (receives server_info with auth requirements)
/// 2. If auth required, login with username/password to get access token
/// 3. Send 'auth' command with token to authenticate the session
/// 4. Optionally create long-lived token for persistent storage
class MusicAssistantAuthStrategy implements AuthStrategy {
  final _logger = DebugLogger();

  @override
  String get name => 'music_assistant';

  /// Login to Music Assistant and get an access token
  /// This is called AFTER WebSocket connection is established
  /// Returns credentials containing the access token
  @override
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    try {
      // Normalize server URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        // Determine protocol based on URL pattern
        if (baseUrl.startsWith('192.') ||
            baseUrl.startsWith('10.') ||
            baseUrl.startsWith('172.') ||
            baseUrl == 'localhost' ||
            baseUrl.startsWith('127.')) {
          baseUrl = 'http://$baseUrl';
        } else {
          baseUrl = 'https://$baseUrl';
        }
      }

      _logger.log('🔐 Attempting Music Assistant login to $baseUrl');

      // MA auth endpoint - POST /api with JSON-RPC style command
      final uri = Uri.parse(baseUrl);
      final apiUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? null : 8095),
        path: '/api',
      );

      _logger.log('Auth API URL: $apiUrl');

      // Login request to get access token
      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'command': 'auth/login',
          'args': {
            'username': username,
            'password': password,
          },
        }),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Auth response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Check for error in response
        if (data.containsKey('error_code')) {
          _logger.log('✗ Login failed: ${data['error_code']} - ${data['details']}');
          return null;
        }

        // Extract access token from result
        final result = data['result'] as Map<String, dynamic>?;
        final accessToken = result?['access_token'] as String?;

        if (accessToken != null) {
          _logger.log('✓ Got access token from MA');

          // Now try to create a long-lived token for persistent auth
          final longLivedToken = await _createLongLivedToken(apiUrl, accessToken);

          return AuthCredentials('music_assistant', {
            'access_token': accessToken,
            'long_lived_token': longLivedToken,
            'username': username,
            'server_url': baseUrl,
          });
        }

        _logger.log('✗ No access token in response');
        return null;
      }

      _logger.log('✗ Authentication failed: ${response.statusCode}');
      _logger.log('Response body: ${response.body}');
      return null;
    } catch (e) {
      _logger.log('✗ Login error: $e');
      return null;
    }
  }

  /// Create a long-lived token for persistent authentication
  Future<String?> _createLongLivedToken(Uri apiUrl, String accessToken) async {
    try {
      _logger.log('Creating long-lived token...');

      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'command': 'auth/create_token',
          'args': {
            'name': 'Ensemble Mobile App',
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (!data.containsKey('error_code')) {
          final result = data['result'] as Map<String, dynamic>?;
          final token = result?['token'] as String?;

          if (token != null) {
            _logger.log('✓ Created long-lived token');
            return token;
          }
        }
      }

      _logger.log('⚠️ Could not create long-lived token (non-fatal)');
      return null;
    } catch (e) {
      _logger.log('⚠️ Long-lived token creation failed: $e (non-fatal)');
      return null;
    }
  }

  @override
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    // Try long-lived token first, then access token
    final longLivedToken = credentials.data['long_lived_token'] as String?;
    final accessToken = credentials.data['access_token'] as String?;

    final token = longLivedToken ?? accessToken;
    if (token == null) return false;

    try {
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      final uri = Uri.parse(baseUrl);
      final apiUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? null : 8095),
        path: '/api',
      );

      // Test token by getting server info
      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'command': 'server/info',
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return !data.containsKey('error_code');
      }

      return false;
    } catch (e) {
      _logger.log('Token validation failed: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    // MA auth happens AFTER WebSocket connection, not via headers
    // But we can still include token if available for initial handshake
    final longLivedToken = credentials.data['long_lived_token'] as String?;
    final accessToken = credentials.data['access_token'] as String?;

    final token = longLivedToken ?? accessToken;
    if (token != null) {
      return {
        'Authorization': 'Bearer $token',
      };
    }

    return {};
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    final longLivedToken = credentials.data['long_lived_token'] as String?;
    final accessToken = credentials.data['access_token'] as String?;

    final token = longLivedToken ?? accessToken;
    if (token != null) {
      return {
        'Authorization': 'Bearer $token',
      };
    }

    return {};
  }

  @override
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials) {
    return credentials.data;
  }

  @override
  AuthCredentials deserializeCredentials(Map<String, dynamic> data) {
    return AuthCredentials('music_assistant', data);
  }

  /// Get the best available token (prefer long-lived)
  String? getToken(AuthCredentials credentials) {
    final longLivedToken = credentials.data['long_lived_token'] as String?;
    final accessToken = credentials.data['access_token'] as String?;
    return longLivedToken ?? accessToken;
  }
}
