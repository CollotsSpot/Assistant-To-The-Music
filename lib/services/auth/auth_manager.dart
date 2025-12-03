import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import 'no_auth_strategy.dart';
import 'basic_auth_strategy.dart';
import 'authelia_strategy.dart';
import 'ma_auth_strategy.dart';
import '../debug_logger.dart';

/// Central authentication manager
/// Manages auth strategy selection, auto-detection, and credential lifecycle
class AuthManager {
  final _logger = DebugLogger();

  // Available auth strategies
  final List<AuthStrategy> _strategies = [
    NoAuthStrategy(),
    BasicAuthStrategy(),
    AutheliaStrategy(),
    MusicAssistantAuthStrategy(),
  ];

  AuthStrategy? _currentStrategy;
  AuthCredentials? _currentCredentials;

  /// Get current auth strategy (null if none selected)
  AuthStrategy? get currentStrategy => _currentStrategy;

  /// Get current credentials (null if none stored)
  AuthCredentials? get currentCredentials => _currentCredentials;

  /// Auto-detect authentication requirements for a server
  /// Returns null if server is unreachable or auth method unknown
  Future<AuthStrategy?> detectAuthStrategy(String serverUrl) async {
    _logger.log('🔍 Auto-detecting auth strategy for $serverUrl');

    // Normalize URL
    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      // Use http for local IPs, https for domains
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

    // First, check if this is a Music Assistant server with native auth
    _logger.log('Checking for Music Assistant native auth...');
    final maAuthResult = await _checkMusicAssistantAuth(baseUrl);
    if (maAuthResult != null) {
      if (maAuthResult == 'required') {
        _logger.log('✓ Detected Music Assistant native authentication');
        return _strategies.firstWhere((s) => s.name == 'music_assistant');
      } else if (maAuthResult == 'none') {
        _logger.log('✓ Music Assistant server - no auth required');
        return _strategies.firstWhere((s) => s.name == 'none');
      }
    }

    // Try no-auth (direct connection without any auth)
    _logger.log('Testing no-auth strategy...');
    final canConnect = await _canConnectWithoutAuth(baseUrl);
    _logger.log('No-auth result: $canConnect');

    if (canConnect) {
      _logger.log('✓ Server does not require authentication');
      return _strategies.firstWhere((s) => s.name == 'none');
    }

    // Probe server for auth requirements (reverse proxy scenarios)
    try {
      _logger.log('Probing server for auth headers...');
      // Test root endpoint
      final probeUrl = baseUrl;
      _logger.log('Probe URL: $probeUrl');

      final response = await http.get(
        Uri.parse(probeUrl),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Probe status: ${response.statusCode}');

      // Check for redirect (common with reverse proxy auth)
      if (response.statusCode == 302 || response.statusCode == 307) {
        final location = response.headers['location'];
        _logger.log('Redirect to: $location');

        // If redirects to Authelia login, it's Authelia
        if (location != null && location.contains('authelia')) {
          _logger.log('✓ Detected Authelia (redirect)');
          return _strategies.firstWhere((s) => s.name == 'authelia');
        }
      }

      // Server returned 401 Unauthorized - check WWW-Authenticate header
      if (response.statusCode == 401) {
        final wwwAuth = response.headers['www-authenticate']?.toLowerCase();
        _logger.log('401 with WWW-Authenticate: $wwwAuth');

        // Check for Basic Auth
        if (wwwAuth != null && wwwAuth.contains('basic')) {
          _logger.log('✓ Detected Basic Authentication');
          return _strategies.firstWhere((s) => s.name == 'basic');
        }

        // Check for Bearer token - could be MA native auth
        if (wwwAuth != null && wwwAuth.contains('bearer')) {
          _logger.log('✓ Detected Bearer auth - likely Music Assistant native');
          return _strategies.firstWhere((s) => s.name == 'music_assistant');
        }
      }

      // If we got here and there's any auth challenge, assume Authelia
      // (since we're behind a reverse proxy that requires auth)
      if (response.statusCode >= 300) {
        _logger.log('Server requires authentication (status ${response.statusCode})');
        _logger.log('Assuming Authelia (default for authenticated reverse proxy)');
        return _strategies.firstWhere((s) => s.name == 'authelia');
      }
    } catch (e) {
      _logger.log('✗ Auth detection error: $e');
      return null; // Return null instead of rethrow to show generic error
    }

    _logger.log('⚠️ Could not determine auth method');
    return null;
  }

  /// Check if server is a Music Assistant server with native auth
  /// Returns 'required' if auth needed, 'none' if no auth, null if not MA or error
  Future<String?> _checkMusicAssistantAuth(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl);
      final apiUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? null : 8095),
        path: '/api',
      );

      _logger.log('Checking MA API at: $apiUrl');

      // Try to get server info - this tells us if auth is required
      final response = await http.post(
        apiUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command': 'server/info',
        }),
      ).timeout(const Duration(seconds: 5));

      _logger.log('MA API response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Check if we got server info successfully (no auth required)
        if (data.containsKey('result')) {
          final result = data['result'] as Map<String, dynamic>?;
          final serverVersion = result?['server_version'] as String?;
          final schemaVersion = result?['schema_version'] as int?;

          if (serverVersion != null) {
            _logger.log('MA server version: $serverVersion, schema: $schemaVersion');

            // Schema 28+ requires auth, but if we got here without auth, it's not enabled
            return 'none';
          }
        }

        // Check for auth error
        if (data.containsKey('error_code')) {
          final errorCode = data['error_code'] as int?;
          // Error 50 = AuthenticationRequired
          if (errorCode == 50) {
            _logger.log('MA server requires authentication (error 50)');
            return 'required';
          }
        }
      }

      // 401/403 means auth required
      if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.log('MA API returned ${response.statusCode} - auth required');
        return 'required';
      }

      return null;
    } catch (e) {
      _logger.log('MA auth check error: $e');
      return null;
    }
  }

  /// Test if server is accessible without authentication
  Future<bool> _canConnectWithoutAuth(String serverUrl) async {
    try {
      // Test root endpoint - Music Assistant doesn't have /api/info
      final testUrl = serverUrl;
      _logger.log('No-auth test URL: $testUrl');

      final response = await http.get(
        Uri.parse(testUrl),
        // Don't follow redirects - we want to see if server requires auth
      ).timeout(const Duration(seconds: 10));

      _logger.log('No-auth status: ${response.statusCode}');

      // 200 = no auth required
      // 302/307 = redirect (probably to auth)
      // 401 = auth required
      if (response.statusCode == 200) {
        return true;
      }

      return false;
    } catch (e) {
      _logger.log('No-auth error: $e');
      return false;
    }
  }

  /// Attempt login with specified strategy
  /// Returns true if login successful and credentials stored
  /// authServerUrl is optional - only used for Authelia when auth is on a different domain
  Future<bool> login(
    String serverUrl,
    String username,
    String password,
    AuthStrategy strategy, {
    String? authServerUrl,
  }) async {
    _logger.log('Attempting login with ${strategy.name} strategy');

    // Use auth server URL if provided, otherwise use main server URL
    final loginUrl = authServerUrl?.isNotEmpty == true ? authServerUrl! : serverUrl;
    _logger.log('Login URL: $loginUrl');

    final credentials = await strategy.login(loginUrl, username, password);

    if (credentials != null) {
      _currentStrategy = strategy;
      _currentCredentials = credentials;
      _logger.log('✓ Login successful with ${strategy.name}');
      return true;
    }

    _logger.log('✗ Login failed with ${strategy.name}');
    return false;
  }

  /// Validate current credentials are still valid
  Future<bool> validateCurrentCredentials(String serverUrl) async {
    if (_currentStrategy == null || _currentCredentials == null) {
      return false;
    }

    return await _currentStrategy!.validateCredentials(
      serverUrl,
      _currentCredentials!,
    );
  }

  /// Get WebSocket connection headers for current credentials
  Map<String, dynamic> getWebSocketHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildWebSocketHeaders(_currentCredentials!);
  }

  /// Get HTTP streaming headers for current credentials
  Map<String, String> getStreamingHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildStreamingHeaders(_currentCredentials!);
  }

  /// Serialize current credentials for persistent storage
  Map<String, dynamic>? serializeCredentials() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return null;
    }

    return {
      'strategy': _currentStrategy!.name,
      'data': _currentStrategy!.serializeCredentials(_currentCredentials!),
    };
  }

  /// Deserialize and restore credentials from persistent storage
  void deserializeCredentials(Map<String, dynamic> stored) {
    final strategyName = stored['strategy'] as String?;
    final data = stored['data'] as Map<String, dynamic>?;

    if (strategyName == null || data == null) {
      return;
    }

    // Find matching strategy
    try {
      final strategy = _strategies.firstWhere((s) => s.name == strategyName);
      _currentStrategy = strategy;
      _currentCredentials = strategy.deserializeCredentials(data);
      _logger.log('✓ Restored ${strategy.name} credentials from storage');
    } catch (e) {
      _logger.log('✗ Could not restore credentials: $e');
    }
  }

  /// Clear current authentication state
  void logout() {
    _currentStrategy = null;
    _currentCredentials = null;
    _logger.log('Logged out - cleared auth state');
  }

  /// Get strategy by name (for manual selection)
  AuthStrategy? getStrategyByName(String name) {
    try {
      return _strategies.firstWhere((s) => s.name == name);
    } catch (e) {
      return null;
    }
  }
}
