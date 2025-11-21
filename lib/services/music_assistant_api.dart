import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../models/media_item.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class MusicAssistantAPI {
  final String serverUrl;
  WebSocketChannel? _channel;
  final _uuid = const Uuid();

  final _connectionStateController = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  ConnectionState _currentState = ConnectionState.disconnected;
  ConnectionState get currentConnectionState => _currentState;

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, StreamController<Map<String, dynamic>>> _eventStreams = {};

  MusicAssistantAPI(this.serverUrl);

  Future<void> connect() async {
    if (_currentState == ConnectionState.connected ||
        _currentState == ConnectionState.connecting) {
      return;
    }

    try {
      _updateConnectionState(ConnectionState.connecting);

      // Parse server URL and construct WebSocket URL
      var wsUrl = serverUrl;
      if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
        // Determine protocol
        if (wsUrl.startsWith('https://')) {
          wsUrl = wsUrl.replaceFirst('https://', 'wss://');
        } else if (wsUrl.startsWith('http://')) {
          wsUrl = wsUrl.replaceFirst('http://', 'ws://');
        } else {
          wsUrl = 'ws://$wsUrl';
        }
      }

      // Add port if not present
      if (!wsUrl.contains(':8095')) {
        final uri = Uri.parse(wsUrl);
        wsUrl = '${uri.scheme}://${uri.host}:8095${uri.path}';
      }

      // Add /ws path for WebSocket endpoint
      if (!wsUrl.endsWith('/ws')) {
        wsUrl = '$wsUrl/ws';
      }

      print('Connecting to Music Assistant at: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('WebSocket error: $error');
          _updateConnectionState(ConnectionState.error);
          _reconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _updateConnectionState(ConnectionState.disconnected);
          _reconnect();
        },
      );

      // Wait a bit to see if connection succeeds
      await Future.delayed(const Duration(milliseconds: 500));
      _updateConnectionState(ConnectionState.connected);

      print('Connected to Music Assistant');
    } catch (e) {
      print('Connection error: $e');
      _updateConnectionState(ConnectionState.error);
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final messageId = data['message_id'] as String?;

      // Handle response to a request
      if (messageId != null && _pendingRequests.containsKey(messageId)) {
        final completer = _pendingRequests.remove(messageId);

        if (data.containsKey('error_code')) {
          completer!.completeError(
            Exception('${data['error_code']}: ${data['details']}'),
          );
        } else {
          completer!.complete(data);
        }
        return;
      }

      // Handle event
      final eventType = data['event'] as String?;
      if (eventType != null) {
        _eventStreams[eventType]?.add(data['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  Future<Map<String, dynamic>> _sendCommand(
    String command, {
    Map<String, dynamic>? args,
  }) async {
    if (_currentState != ConnectionState.connected) {
      throw Exception('Not connected to Music Assistant server');
    }

    final messageId = _uuid.v4();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[messageId] = completer;

    final message = {
      'message_id': messageId,
      'command': command,
      if (args != null) 'args': args,
    };

    _channel!.sink.add(jsonEncode(message));

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(messageId);
        throw TimeoutException('Command timeout: $command');
      },
    );
  }

  // Library browsing methods
  Future<List<Artist>> getArtists({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
  }) async {
    try {
      final response = await _sendCommand(
        'music/artists',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite_only': favoriteOnly,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Artist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting artists: $e');
      return [];
    }
  }

  Future<List<Album>> getAlbums({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? artistId,
  }) async {
    try {
      final response = await _sendCommand(
        'music/albums',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite_only': favoriteOnly,
          if (artistId != null) 'artist': artistId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Album.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting albums: $e');
      return [];
    }
  }

  Future<List<Track>> getTracks({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? artistId,
    String? albumId,
  }) async {
    try {
      final response = await _sendCommand(
        'music/tracks',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite_only': favoriteOnly,
          if (artistId != null) 'artist': artistId,
          if (albumId != null) 'album': albumId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting tracks: $e');
      return [];
    }
  }

  Future<Album?> getAlbumDetails(String provider, String itemId) async {
    try {
      final response = await _sendCommand(
        'music/album',
        args: {
          'provider': provider,
          'item_id': itemId,
        },
      );

      final result = response['result'];
      if (result == null) return null;

      return Album.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      print('Error getting album details: $e');
      return null;
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    try {
      final response = await _sendCommand(
        'music/album/tracks',
        args: {
          'provider': provider,
          'item_id': itemId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting album tracks: $e');
      return [];
    }
  }

  // Search
  Future<Map<String, List<MediaItem>>> search(String query) async {
    try {
      final response = await _sendCommand(
        'music/search',
        args: {'search': query},
      );

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) {
        return {'artists': [], 'albums': [], 'tracks': []};
      }

      return {
        'artists': (result['artists'] as List<dynamic>?)
                ?.map((item) => Artist.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        'albums': (result['albums'] as List<dynamic>?)
                ?.map((item) => Album.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        'tracks': (result['tracks'] as List<dynamic>?)
                ?.map((item) => Track.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
      };
    } catch (e) {
      print('Error searching: $e');
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  // Get stream URL for a track
  String getStreamUrl(String provider, String itemId) {
    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    if (!baseUrl.contains(':8095')) {
      final uri = Uri.parse(baseUrl);
      baseUrl = '${uri.scheme}://${uri.host}:8095';
    }
    return '$baseUrl/api/stream/$provider/$itemId';
  }

  // Get image URL
  String? getImageUrl(MediaItem item, {int size = 256}) {
    final imageUrl = item.metadata?['image'];
    if (imageUrl == null) return null;

    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    if (!baseUrl.contains(':8095')) {
      final uri = Uri.parse(baseUrl);
      baseUrl = '${uri.scheme}://${uri.host}:8095';
    }

    return '$baseUrl/api/image/$size/${Uri.encodeComponent(imageUrl)}';
  }

  void _updateConnectionState(ConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  Future<void> _reconnect() async {
    await Future.delayed(const Duration(seconds: 3));
    if (_currentState != ConnectionState.connected) {
      try {
        await connect();
      } catch (e) {
        print('Reconnection failed: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _updateConnectionState(ConnectionState.disconnected);
    await _channel?.sink.close();
    _channel = null;
    _pendingRequests.clear();
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _eventStreams.clear();
  }
}
