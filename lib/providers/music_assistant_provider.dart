import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/auth/auth_manager.dart';
import '../services/device_id_service.dart';
import '../services/cache_service.dart';
import '../services/local_player_service.dart';
import '../services/metadata_service.dart';
import '../constants/timings.dart';
import '../main.dart' show audioHandler;

/// Main provider that coordinates connection, player, and library state.
///
/// This is a facade that delegates to internal services while maintaining
/// backward compatibility with existing code that uses MusicAssistantProvider.
///
/// Architecture:
/// - CacheService: Handles all caching (non-notifying)
/// - Connection logic: WebSocket, auth, reconnection
/// - Player logic: Player selection, controls, local player
/// - Library logic: Artists, albums, tracks, search
class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthManager _authManager = AuthManager();
  final DebugLogger _logger = DebugLogger();
  final CacheService _cacheService = CacheService();

  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;
  String? _error;

  // Library state
  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;

  // Player state
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack;
  Timer? _playerStateTimer;

  // Local player state
  bool _isLocalPlayerPowered = true;
  int _localPlayerVolume = 100; // Tracked MA volume for builtin player (0-100)
  bool _builtinPlayerAvailable = true; // False on MA 2.7.0b20+ (uses Sendspin instead)
  StreamSubscription? _localPlayerEventSubscription;
  StreamSubscription? _playerUpdatedEventSubscription;
  Timer? _localPlayerStateReportTimer;
  TrackMetadata? _pendingTrackMetadata;
  TrackMetadata? _currentNotificationMetadata;
  Completer<void>? _registrationInProgress;

  // Local player service
  late final LocalPlayerService _localPlayer;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // ============================================================================
  // GETTERS
  // ============================================================================

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected ||
                          _connectionState == MAConnectionState.authenticated;

  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;

  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;

  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  MusicAssistantAPI? get api => _api;
  AuthManager get authManager => _authManager;

  /// Get cached track for a player (used for smooth swipe transitions)
  Track? getCachedTrackForPlayer(String playerId) => _cacheService.getCachedTrackForPlayer(playerId);

  /// Get artwork URL for a player from cache
  String? getCachedArtworkUrl(String playerId, {int size = 512}) {
    final track = _cacheService.getCachedTrackForPlayer(playerId);
    if (track == null) return null;
    return getImageUrl(track, size: size);
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  MusicAssistantProvider() {
    _localPlayer = LocalPlayerService(_authManager);
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      await _restoreAuthCredentials();
      await connectToServer(_serverUrl!);
      await _initializeLocalPlayback();
    }
  }

  Future<void> _restoreAuthCredentials() async {
    final savedCredentials = await SettingsService.getAuthCredentials();
    if (savedCredentials != null) {
      _logger.log('🔐 Restoring saved auth credentials...');
      _authManager.deserializeCredentials(savedCredentials);
      _logger.log('🔐 Auth credentials restored: ${_authManager.currentStrategy?.name ?? "none"}');
    }
  }

  // ============================================================================
  // CONNECTION
  // ============================================================================

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Dispose the old API to stop any pending reconnects
      _api?.dispose();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      _api!.connectionState.listen(
        (state) async {
          _connectionState = state;
          notifyListeners();

          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            if (_api!.authRequired && !_api!.isAuthenticated) {
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await _handleMaAuthentication();
              if (!authenticated) {
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              // After authentication succeeds, authenticated state will trigger initialization
              // Don't call _initializeAfterConnection() here - wait for authenticated state
              return;
            }

            // No auth required, initialize immediately
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.authenticated) {
            _logger.log('✅ MA authentication successful');
            // Now safe to initialize since we're authenticated
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.disconnected) {
            _availablePlayers = [];
            _selectedPlayer = null;
            // Only clear detail caches on disconnect, NOT home screen caches
            // Home screen data should persist across reconnects for better UX
            _cacheService.clearAllDetailCaches();
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
      );

      _localPlayerEventSubscription?.cancel();
      _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(
        _handleLocalPlayerEvent,
        onError: (error) => _logger.log('Builtin player event stream error: $error'),
      );

      _playerUpdatedEventSubscription?.cancel();
      _playerUpdatedEventSubscription = _api!.playerUpdatedEvents.listen(
        _handlePlayerUpdatedEvent,
        onError: (error) => _logger.log('Player updated event stream error: $error'),
      );

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Connect to server');
      _error = errorInfo.userMessage;
      _connectionState = MAConnectionState.error;
      _logger.log('Connection error: ${errorInfo.technicalMessage}');
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> _handleMaAuthentication() async {
    if (_api == null) return false;

    try {
      final storedToken = await SettingsService.getMaAuthToken();
      if (storedToken != null) {
        _logger.log('🔐 Trying stored MA token...');
        final success = await _api!.authenticateWithToken(storedToken);
        if (success) {
          _logger.log('✅ MA authentication with stored token successful');
          await _fetchAndSetUserProfileName();
          return true;
        }
        _logger.log('⚠️ Stored MA token invalid, clearing...');
        await SettingsService.clearMaAuthToken();
      }

      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        _logger.log('🔐 Trying stored credentials...');
        final accessToken = await _api!.loginWithCredentials(username, password);

        if (accessToken != null) {
          _logger.log('✅ MA login with stored credentials successful');

          final longLivedToken = await _api!.createLongLivedToken();
          if (longLivedToken != null) {
            await SettingsService.setMaAuthToken(longLivedToken);
            _logger.log('✅ Saved new long-lived MA token');
          } else {
            await SettingsService.setMaAuthToken(accessToken);
          }

          await _fetchAndSetUserProfileName();
          return true;
        }
      }

      _logger.log('❌ MA authentication failed - no valid token or credentials');
      return false;
    } catch (e) {
      _logger.log('❌ MA authentication error: $e');
      return false;
    }
  }

  Future<void> _fetchAndSetUserProfileName() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) return;

      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;

      final profileName = (displayName != null && displayName.isNotEmpty) ? displayName : username;

      if (profileName != null && profileName.isNotEmpty) {
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user profile (non-fatal): $e');
    }
  }

  Future<void> _initializeAfterConnection() async {
    if (_api == null) return;

    try {
      _logger.log('🚀 Initializing after connection...');

      await _api!.fetchState();

      if (_api!.authRequired) {
        await _fetchAndSetUserProfileName();
      }

      await _tryAdoptGhostPlayer();
      await _registerLocalPlayer();
      await _loadAndSelectPlayers();

      loadLibrary();

      _logger.log('✅ Post-connection initialization complete');
    } catch (e) {
      _logger.log('❌ Error during post-connection initialization: $e');
      _error = 'Failed to initialize after connection';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    _cacheService.clearAll();
    notifyListeners();
  }

  Future<void> checkAndReconnect() async {
    _logger.log('🔄 checkAndReconnect called - state: $_connectionState');

    if (_serverUrl == null) {
      _logger.log('🔄 No server URL saved, skipping reconnect');
      return;
    }

    if (_connectionState != MAConnectionState.connected &&
        _connectionState != MAConnectionState.authenticated) {
      _logger.log('🔄 Not connected, attempting reconnect to $_serverUrl');
      try {
        await connectToServer(_serverUrl!);
        _logger.log('🔄 Reconnection successful');
      } catch (e) {
        _logger.log('🔄 Reconnection failed: $e');
      }
    } else {
      _logger.log('🔄 Already connected, verifying connection...');
      try {
        await refreshPlayers();
        await _updatePlayerState();
        _logger.log('🔄 Connection verified, players and state refreshed');
      } catch (e) {
        _logger.log('🔄 Connection verification failed, reconnecting: $e');
        try {
          await connectToServer(_serverUrl!);
        } catch (reconnectError) {
          _logger.log('🔄 Reconnection failed: $reconnectError');
        }
      }
    }
  }

  // ============================================================================
  // LOCAL PLAYER
  // ============================================================================

  Future<void> _initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true;

    // Wire up notification button callbacks
    audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      nextTrackSelectedPlayer();
    };
    audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      previousTrackSelectedPlayer();
    };
    audioHandler.onPlay = () {
      _logger.log('🎵 Notification: Play pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onPause = () {
      _logger.log('🎵 Notification: Pause pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onSwitchPlayer = () {
      _logger.log('🎵 Notification: Switch player pressed');
      selectNextPlayer();
    };

    // Player registration is now handled in _initializeAfterConnection()
    // which runs after authentication completes (when auth is required)
  }

  Future<bool> _tryAdoptGhostPlayer() async {
    if (_api == null) return false;

    try {
      final isFresh = await DeviceIdService.isFreshInstallation();
      if (!isFresh) return false;

      final ownerName = await SettingsService.getOwnerName();
      if (ownerName == null || ownerName.isEmpty) return false;

      _logger.log('👻 Fresh install detected, searching for adoptable ghost for "$ownerName"...');
      final adoptableId = await _api!.findAdoptableGhostPlayer(ownerName);
      if (adoptableId == null) return false;

      _logger.log('👻 Found adoptable ghost: $adoptableId');
      await DeviceIdService.adoptPlayerId(adoptableId);
      _logger.log('✅ Successfully adopted ghost player');
      return true;
    } catch (e) {
      _logger.log('⚠️ Ghost adoption failed (non-fatal): $e');
      return false;
    }
  }

  Future<void> _registerLocalPlayer() async {
    if (_api == null) return;

    if (_registrationInProgress != null) {
      _logger.log('⏳ Registration already in progress, waiting...');
      return _registrationInProgress!.future;
    }

    _registrationInProgress = Completer<void>();

    try {
      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('🆔 Using player ID: $playerId');

      await SettingsService.setBuiltinPlayerId(playerId);

      final name = await SettingsService.getLocalPlayerName();

      final existingPlayers = await _api!.getPlayers();
      final existingPlayer = existingPlayers.where((p) => p.playerId == playerId).firstOrNull;

      if (existingPlayer != null && existingPlayer.available) {
        _logger.log('✅ Player already registered and available: $playerId');
        _startReportingLocalPlayerState();
        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return;
      } else if (existingPlayer != null && !existingPlayer.available) {
        _logger.log('⚠️ Player exists but unavailable (stale), re-registering: $playerId');
      } else {
        _logger.log('🆔 Player not found in MA, registering as new');
      }

      _logger.log('🎵 Registering player with MA: id=$playerId, name=$name');
      await _api!.registerBuiltinPlayer(playerId, name);

      _logger.log('✅ Player registration complete');
      _startReportingLocalPlayerState();

      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.complete();
      }
      _registrationInProgress = null;
    } catch (e) {
      // Check if this is because builtin_player API is not available (MA 2.7.0b20+)
      final errorStr = e.toString();
      if (errorStr.contains('Invalid command') && errorStr.contains('builtin_player')) {
        _logger.log('⚠️ Builtin player API not available (MA 2.7.0b20+ uses Sendspin)');
        _logger.log('ℹ️ Local player registration skipped - use other players (Chromecast, etc)');
        _builtinPlayerAvailable = false;
        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return; // Non-fatal, continue without local player
      }

      _logger.log('❌ Player registration failed: $e');
      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.completeError(e);
      }
      _registrationInProgress = null;
      rethrow;
    }
  }

  void _startReportingLocalPlayerState() {
    _localPlayerStateReportTimer?.cancel();
    _localPlayerStateReportTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) async {
      try {
        await _reportLocalPlayerState();
      } catch (e) {
        _logger.log('Error reporting local player state (will retry): $e');
      }
    });
  }

  Future<void> _reportLocalPlayerState() async {
    if (_api == null) return;
    if (!_builtinPlayerAvailable) return; // Skip on MA 2.7.0b20+ (no builtin_player API)

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    // Use tracked MA volume instead of just_audio player volume
    // just_audio volume is for local playback, MA volume is for server sync
    final volume = _localPlayerVolume;
    final isPaused = !isPlaying && position > 0;

    await _api!.updateBuiltinPlayerState(
      playerId,
      powered: _isLocalPlayerPowered,
      playing: isPlaying,
      paused: isPaused,
      position: position,
      volume: volume,
      muted: _localPlayerVolume == 0,
    );
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    _logger.log('📥 Local player event received: ${event['type'] ?? event['command']}');

    try {
      final eventPlayerId = event['player_id'] as String?;
      final myPlayerId = await SettingsService.getBuiltinPlayerId();

      if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
        _logger.log('🚫 Ignoring event for different player: $eventPlayerId (my player: $myPlayerId)');
        return;
      }

      final command = (event['type'] as String?) ?? (event['command'] as String?);

      switch (command) {
        case 'play_media':
          final urlPath = event['media_url'] as String? ?? event['url'] as String?;

          _logger.log('🎵 play_media: urlPath=$urlPath, _serverUrl=$_serverUrl');

          if (urlPath != null && _serverUrl != null) {
            String fullUrl;
            if (urlPath.startsWith('http')) {
              fullUrl = urlPath;
            } else {
              var baseUrl = _serverUrl!;
              if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                baseUrl = 'https://$baseUrl';
              }
              baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
              final path = urlPath.startsWith('/') ? urlPath : '/$urlPath';
              fullUrl = '$baseUrl$path';
            }

            TrackMetadata metadata;
            if (_pendingTrackMetadata != null) {
              metadata = _pendingTrackMetadata!;
              _logger.log('🎵 Using metadata from player_updated: ${metadata.title} by ${metadata.artist}');
            } else {
              final trackName = event['track_name'] as String? ?? event['name'] as String? ?? 'Unknown Track';
              final artistName = event['artist_name'] as String? ?? event['artist'] as String? ?? 'Unknown Artist';
              final albumName = event['album_name'] as String? ?? event['album'] as String?;
              var artworkUrl = event['image_url'] as String? ?? event['artwork_url'] as String?;
              final durationSecs = event['duration'] as int?;

              if (artworkUrl != null && artworkUrl.startsWith('http://')) {
                artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
              }

              metadata = TrackMetadata(
                title: trackName,
                artist: artistName,
                album: albumName,
                artworkUrl: artworkUrl,
                duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
              );
            }

            _localPlayer.setCurrentTrackMetadata(metadata);
            _currentNotificationMetadata = metadata;

            await _localPlayer.playUrl(fullUrl);
          }
          break;

        case 'stop':
          await _localPlayer.stop();
          break;

        case 'pause':
          await _localPlayer.pause();
          break;

        case 'play':
          await _localPlayer.play();
          break;

        case 'seek':
          final position = event['position'] as int?;
          if (position != null) {
            await _localPlayer.seek(Duration(seconds: position));
          }
          break;

        case 'volume_set':
        case 'set_volume':
          final volume = event['volume_level'] as int? ?? event['volume'] as int?;
          if (volume != null) {
            _localPlayerVolume = volume;
            await FlutterVolumeController.setVolume(volume / 100.0);
          }
          break;

        case 'power_on':
        case 'power_off':
        case 'power':
          _logger.log('🔋 POWER COMMAND RECEIVED: $command');

          bool? newPowerState;
          if (command == 'power_on') {
            newPowerState = true;
          } else if (command == 'power_off') {
            newPowerState = false;
          } else {
            newPowerState = event['powered'] as bool?;
          }

          if (newPowerState != null) {
            _isLocalPlayerPowered = newPowerState;
            _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');
            if (!_isLocalPlayerPowered) {
              _logger.log('🔋 Stopping playback because powered off');
              await _localPlayer.stop();
            }
          }
          break;
      }

      await _reportLocalPlayerState();
    } catch (e) {
      _logger.log('Error handling local player event: $e');
    }
  }

  Future<void> _handlePlayerUpdatedEvent(Map<String, dynamic> event) async {
    try {
      final playerId = event['player_id'] as String?;
      if (playerId == null) return;

      if (_selectedPlayer != null && playerId == _selectedPlayer!.playerId) {
        _updatePlayerState();
      }

      final currentMedia = event['current_media'] as Map<String, dynamic>?;
      final playerName = event['name'] as String? ?? playerId;

      if (currentMedia != null) {
        final mediaType = currentMedia['media_type'] as String?;
        if (mediaType != 'flow_stream') {
          final durationSecs = (currentMedia['duration'] as num?)?.toInt();
          final albumName = currentMedia['album'] as String?;
          final imageUrl = currentMedia['image_url'] as String?;

          Map<String, dynamic>? metadata;
          if (imageUrl != null) {
            var finalImageUrl = imageUrl;
            if (_serverUrl != null) {
              try {
                final imgUri = Uri.parse(imageUrl);
                final queryString = imgUri.query;
                var baseUrl = _serverUrl!;
                if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                  baseUrl = 'https://$baseUrl';
                }
                if (baseUrl.endsWith('/')) {
                  baseUrl = baseUrl.substring(0, baseUrl.length - 1);
                }
                finalImageUrl = '$baseUrl/imageproxy?$queryString';
              } catch (e) {
                // Use original URL
              }
            }
            metadata = {
              'images': [
                {'path': finalImageUrl, 'provider': 'direct'}
              ]
            };
          }

          final trackFromEvent = Track(
            itemId: currentMedia['queue_item_id'] as String? ?? '',
            provider: 'library',
            name: currentMedia['title'] as String? ?? 'Unknown Track',
            uri: currentMedia['uri'] as String?,
            duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
            artists: [Artist(itemId: '', provider: 'library', name: currentMedia['artist'] as String? ?? 'Unknown Artist')],
            album: albumName != null ? Album(itemId: '', provider: 'library', name: albumName) : null,
            metadata: metadata,
          );
          _cacheService.setCachedTrackForPlayer(playerId, trackFromEvent);

          if (_selectedPlayer != null && playerId == _selectedPlayer!.playerId) {
            _currentTrack = trackFromEvent;
          }

          _logger.log('📋 Cached track for $playerName from player_updated: ${trackFromEvent.name}');

          notifyListeners();
        }
      }

      // Handle notification metadata for local player
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId == null) return;

      if (playerId != builtinPlayerId) return;

      if (currentMedia == null) return;

      final title = currentMedia['title'] as String? ?? 'Unknown Track';
      final artist = currentMedia['artist'] as String? ?? 'Unknown Artist';
      final album = currentMedia['album'] as String?;
      var imageUrl = currentMedia['image_url'] as String?;
      final durationSecs = (currentMedia['duration'] as num?)?.toInt();

      if (imageUrl != null && _serverUrl != null) {
        try {
          final imgUri = Uri.parse(imageUrl);
          final queryString = imgUri.query;
          var baseUrl = _serverUrl!;
          if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
            baseUrl = 'https://$baseUrl';
          }
          if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length - 1);
          }
          imageUrl = '$baseUrl/imageproxy?$queryString';
        } catch (e) {
          if (imageUrl != null && imageUrl.startsWith('http://')) {
            imageUrl = imageUrl.replaceFirst('http://', 'https://');
          }
        }
      }

      final newMetadata = TrackMetadata(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: imageUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      final mediaType = currentMedia['media_type'] as String?;
      if (mediaType == 'flow_stream') return;

      _pendingTrackMetadata = newMetadata;
      _logger.log('📋 Captured track metadata from player_updated: $title by $artist');

      final notificationNeedsUpdate = _currentNotificationMetadata != null &&
          (_currentNotificationMetadata!.title != title ||
           _currentNotificationMetadata!.artist != artist);

      if (_localPlayer.isPlaying && notificationNeedsUpdate) {
        _logger.log('📋 Notification has stale metadata - updating to: $title by $artist');
        await _localPlayer.updateNotificationWhilePlaying(newMetadata);
        _currentNotificationMetadata = newMetadata;
      }
    } catch (e) {
      _logger.log('Error handling player_updated event: $e');
    }
  }

  // ============================================================================
  // SEARCH STATE
  // ============================================================================

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {'artists': [], 'albums': [], 'tracks': []};
  }

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  Future<List<Album>> getRecentAlbumsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isRecentAlbumsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached recent albums');
      return _cacheService.getCachedRecentAlbums()!;
    }

    if (_api == null) return _cacheService.getCachedRecentAlbums() ?? [];

    try {
      _logger.log('🔄 Fetching fresh recent albums...');
      final albums = await _api!.getRecentAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedRecentAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch recent albums: $e');
      return _cacheService.getCachedRecentAlbums() ?? [];
    }
  }

  Future<List<Artist>> getDiscoverArtistsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverArtistsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover artists');
      return _cacheService.getCachedDiscoverArtists()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverArtists() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover artists...');
      final artists = await _api!.getRandomArtists(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedDiscoverArtists(artists);
      return artists;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover artists: $e');
      return _cacheService.getCachedDiscoverArtists() ?? [];
    }
  }

  Future<List<Album>> getDiscoverAlbumsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverAlbumsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover albums');
      return _cacheService.getCachedDiscoverAlbums()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverAlbums() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover albums...');
      final albums = await _api!.getRandomAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedDiscoverAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover albums: $e');
      return _cacheService.getCachedDiscoverAlbums() ?? [];
    }
  }

  void invalidateHomeCache() {
    _cacheService.invalidateHomeCache();
  }

  // ============================================================================
  // FAVORITES FOR HOME SCREEN
  // ============================================================================

  /// Get favorite albums from the library
  Future<List<Album>> getFavoriteAlbums() async {
    // Filter from loaded library - favorites are already loaded
    return _albums.where((a) => a.favorite == true).toList();
  }

  /// Get favorite artists from the library
  Future<List<Artist>> getFavoriteArtists() async {
    // Filter from loaded library - favorites are already loaded
    return _artists.where((a) => a.favorite == true).toList();
  }

  /// Get favorite tracks from the library
  Future<List<Track>> getFavoriteTracks() async {
    // Filter from loaded library - favorites are already loaded
    return _tracks.where((t) => t.favorite == true).toList();
  }

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

  Future<List<Track>> getAlbumTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isAlbumTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached album tracks for $cacheKey');
      return _cacheService.getCachedAlbumTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh album tracks for $cacheKey...');
      final tracks = await _api!.getAlbumTracks(provider, itemId);
      _cacheService.setCachedAlbumTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch album tracks: $e');
      return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];
    }
  }

  Future<List<Track>> getPlaylistTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isPlaylistTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached playlist tracks for $cacheKey');
      return _cacheService.getCachedPlaylistTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh playlist tracks for $cacheKey...');
      final tracks = await _api!.getPlaylistTracks(provider, itemId);
      _cacheService.setCachedPlaylistTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch playlist tracks: $e');
      return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];
    }
  }

  Future<List<Album>> getArtistAlbumsWithCache(String artistName, {bool forceRefresh = false}) async {
    final cacheKey = artistName.toLowerCase();

    if (_cacheService.isArtistAlbumsCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached artist albums for "$artistName"');
      return _cacheService.getCachedArtistAlbums(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching albums for artist "$artistName"...');

      // Fetch all library albums (with high limit to get full library)
      final libraryAlbums = await _api!.getAlbums(limit: LibraryConstants.maxLibraryItems);
      _logger.log('📚 Fetched ${libraryAlbums.length} total library albums');
      final artistAlbums = libraryAlbums.where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final searchResults = await _api!.search(artistName);
      final searchAlbums = searchResults['albums'] as List<MediaItem>? ?? [];
      final providerAlbums = searchAlbums.whereType<Album>().where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final allAlbums = <Album>[];
      final seenNames = <String>{};

      for (final album in [...artistAlbums, ...providerAlbums]) {
        final key = album.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          allAlbums.add(album);
        }
      }

      _cacheService.setCachedArtistAlbums(cacheKey, allAlbums);
      _logger.log('✅ Cached ${allAlbums.length} albums for artist "$artistName"');
      return allAlbums;
    } catch (e) {
      _logger.log('❌ Failed to fetch artist albums: $e');
      return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];
    }
  }

  void invalidateAlbumTracksCache(String albumId) {
    _cacheService.invalidateAlbumTracksCache(albumId);
  }

  void invalidatePlaylistTracksCache(String playlistId) {
    _cacheService.invalidatePlaylistTracksCache(playlistId);
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

  Future<Map<String, List<MediaItem>>> searchWithCache(String query, {bool forceRefresh = false}) async {
    final cacheKey = query.toLowerCase().trim();
    if (cacheKey.isEmpty) return {'artists': [], 'albums': [], 'tracks': []};

    if (_cacheService.isSearchCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached search results for "$query"');
      return _cacheService.getCachedSearchResults(cacheKey)!;
    }

    if (_api == null) {
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      _logger.log('🔄 Searching for "$query"...');
      final results = await _api!.search(query);

      final cachedResults = <String, List<MediaItem>>{
        'artists': results['artists'] ?? [],
        'albums': results['albums'] ?? [],
        'tracks': results['tracks'] ?? [],
      };

      _cacheService.setCachedSearchResults(cacheKey, cachedResults);
      _logger.log('✅ Cached search results for "$query"');
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  void clearAllDetailCaches() {
    _cacheService.clearAllDetailCaches();
  }

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

  Future<String?> getCurrentPlayerId() async {
    return await SettingsService.getBuiltinPlayerId();
  }

  Future<void> _loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh &&
          _cacheService.isPlayersCacheValid() &&
          _availablePlayers.isNotEmpty) {
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players:');

      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        if (nameLower == 'this device' || player.playerId.startsWith('ma_')) {
          _logger.log('🚫 Filtering out MA Web UI player: ${player.name}');
          filteredCount++;
          return false;
        }

        if (player.playerId.startsWith('ensemble_')) {
          if (builtinPlayerId == null || player.playerId != builtinPlayerId) {
            _logger.log('🚫 Filtering out other device\'s player: ${player.name}');
            filteredCount++;
            return false;
          }
        }

        if (!player.available) {
          if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
            return true;
          }
          filteredCount++;
          return false;
        }

        return true;
      }).toList();

      _availablePlayers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _cacheService.updatePlayersLastFetched();

      _logger.log('🎛️ After filtering: ${_availablePlayers.length} players available');

      if (_availablePlayers.isNotEmpty) {
        Player? playerToSelect;

        if (_selectedPlayer != null) {
          final stillAvailable = _availablePlayers.any(
            (p) => p.playerId == _selectedPlayer!.playerId && p.available,
          );
          if (stillAvailable) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == _selectedPlayer!.playerId,
            );
          }
        }

        if (playerToSelect == null) {
          final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();

          if (lastSelectedPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == lastSelectedPlayerId && p.available,
              );
              _logger.log('🔄 Auto-selected last used player: ${playerToSelect?.name}');
            } catch (e) {}
          }

          if (playerToSelect == null && builtinPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == builtinPlayerId && p.available,
              );
              _logger.log('📱 Auto-selected local player: ${playerToSelect?.name}');
            } catch (e) {}
          }

          if (playerToSelect == null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.state == 'playing' && p.available,
              );
            } catch (e) {}
          }

          if (playerToSelect == null) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
          }
        }

        selectPlayer(playerToSelect);
      }

      // Await preload so track data and images are ready for swipe gestures
      await _preloadAdjacentPlayers(preloadAll: true);
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  void selectPlayer(Player player, {bool skipNotify = false}) async {
    _selectedPlayer = player;

    SettingsService.setLastSelectedPlayerId(player.playerId);

    // Immediately set currentTrack from cache to avoid flash during player switch
    // This ensures the UI shows the correct track info immediately, before
    // the async _updatePlayerState() completes.
    // IMPORTANT: Always set from cache, even if null - this prevents showing
    // stale track info when switching to a non-playing player.
    _currentTrack = _cacheService.getCachedTrackForPlayer(player.playerId);

    // Switch audio handler mode based on player type
    final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
    final isBuiltinPlayer = builtinPlayerId != null && player.playerId == builtinPlayerId;
    if (isBuiltinPlayer) {
      audioHandler.setLocalMode();
    } else {
      // For remote players, immediately show notification if we have cached track info
      // and the player is playing (don't wait for polling to kick in)
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        // Include player name in artist line: "Artist • Player Name"
        final artistWithPlayer = track.artistsString.isNotEmpty
            ? '${track.artistsString} • ${player.name}'
            : player.name;
        final mediaItem = audio_service.MediaItem(
          id: track.uri ?? track.itemId,
          title: track.name,
          artist: artistWithPlayer,
          album: track.album?.name ?? '',
          duration: track.duration,
          artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
        );
        audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          duration: track.duration,
        );
      }
    }

    _startPlayerStatePolling();

    _preloadAdjacentPlayers();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  /// Cycle to the next active player (for notification switch button)
  /// Only cycles through players that are currently playing or paused
  void selectNextPlayer() {
    // Only include players that are available AND actively playing/paused
    final activePlayers = _availablePlayers.where((p) =>
      p.available && (p.state == 'playing' || p.state == 'paused')
    ).toList();

    if (activePlayers.isEmpty) {
      _logger.log('🔄 No active players to switch to');
      return;
    }

    if (_selectedPlayer == null) return;

    // Find current player in active list
    final currentIndex = activePlayers.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);

    // Calculate next index - if current isn't in active list, start at 0
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % activePlayers.length;
    final nextPlayer = activePlayers[nextIndex];

    _logger.log('🔄 Switching to next active player: ${nextPlayer.name} (${nextIndex + 1}/${activePlayers.length})');
    selectPlayer(nextPlayer);
  }

  Future<void> _preloadAdjacentPlayers({bool preloadAll = false}) async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();
    if (players.isEmpty) return;

    if (preloadAll) {
      _logger.log('🖼️ Preloading track info for all ${players.length} players...');
      await Future.wait(
        players.map((player) => _preloadPlayerTrack(player)),
      );
      _logger.log('🖼️ Preloading complete');
      return;
    }

    if (_selectedPlayer == null) return;
    if (players.length <= 1) return;

    final currentIndex = players.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);
    if (currentIndex == -1) return;

    final prevIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    final nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;

    final playersToPreload = <Player>{};
    if (prevIndex != currentIndex) playersToPreload.add(players[prevIndex]);
    if (nextIndex != currentIndex) playersToPreload.add(players[nextIndex]);

    // Await all preloads so images are ready for next swipe
    await Future.wait(
      playersToPreload.map((player) => _preloadPlayerTrack(player)),
    );
  }

  Future<void> _preloadPlayerTrack(Player player) async {
    if (_api == null) return;

    try {
      _logger.log('🔍 Preload ${player.name}: state=${player.state}, available=${player.available}');

      if (!player.available || !player.powered) {
        _logger.log('🔍 Preload ${player.name}: SKIPPED - not available or powered');
        _cacheService.setCachedTrackForPlayer(player.playerId, null);
        return;
      }

      final queue = await getQueue(player.playerId);
      _logger.log('🔍 Preload ${player.name}: queue=${queue != null}, currentItem=${queue?.currentItem != null}');

      if (queue != null && queue.currentItem != null) {
        final track = queue.currentItem!.track;

        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        final existingHasImage = existingTrack?.metadata?['images'] != null;
        final newHasImage = track.metadata?['images'] != null;

        if (existingHasImage && !newHasImage) {
          _logger.log('🔍 Preload ${player.name}: SKIPPED - keeping cached track with image');
        } else {
          _cacheService.setCachedTrackForPlayer(player.playerId, track);
          _logger.log('🔍 Preload ${player.name}: CACHED track "${track.name}"');

          // Also precache the image so it's ready for swipe preview
          final imageUrl = getImageUrl(track, size: 512);
          if (imageUrl != null) {
            _precacheImage(imageUrl);
          }
        }
      } else {
        _logger.log('🔍 Preload ${player.name}: NO TRACK - queue empty');
        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        if (existingTrack?.metadata?['images'] == null) {
          _cacheService.setCachedTrackForPlayer(player.playerId, null);
        }
      }
    } catch (e) {
      _logger.log('Error preloading player track for ${player.name}: $e');
    }
  }

  /// Precache an image URL so it loads instantly when displayed
  Future<void> _precacheImage(String url) async {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) completer.complete();
          imageStream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) completer.completeError(exception);
          imageStream.removeListener(listener);
        },
      );

      imageStream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
        imageStream.removeListener(listener);
      });
    } catch (e) {
      // Silently ignore precache errors - image will load on demand
    }
  }

  Future<void> preloadAllPlayerTracks() async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();

    await Future.wait(
      players.map((player) => _preloadPlayerTrack(player)),
    );
  }

  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    _playerStateTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      try {
        await _updatePlayerState();
      } catch (e) {
        _logger.log('Error updating player state (will retry): $e');
      }
    });

    _updatePlayerState();
  }

  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      bool stateChanged = false;

      final allPlayers = await getPlayers();
      final updatedPlayer = allPlayers.firstWhere(
        (p) => p.playerId == _selectedPlayer!.playerId,
        orElse: () => _selectedPlayer!,
      );

      _selectedPlayer = updatedPlayer;
      stateChanged = true;

      final isPlayingOrPaused = _selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused';
      final isIdleWithContent = _selectedPlayer!.state == 'idle' && _selectedPlayer!.powered;
      final shouldShowTrack = _selectedPlayer!.available && (isPlayingOrPaused || isIdleWithContent);

      if (!shouldShowTrack) {
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        final trackChanged = _currentTrack == null ||
            _currentTrack!.uri != queue.currentItem!.track.uri ||
            _currentTrack!.name != queue.currentItem!.track.name;

        if (trackChanged) {
          _currentTrack = queue.currentItem!.track;
          stateChanged = true;
        }

        // Update notification for ALL players
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
        final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;

        if (isBuiltinPlayer) {
          // Local playback - use local player notification
          if (trackChanged) {
            _localPlayer.updateNotification(
              id: track.uri ?? track.itemId,
              title: track.name,
              artist: track.artistsString,
              album: track.album?.name,
              artworkUrl: artworkUrl,
              duration: track.duration,
            );
          }
        } else {
          // Remote MA player - show notification via remote mode
          // Include player name in artist line: "Artist • Player Name"
          final artistWithPlayer = track.artistsString.isNotEmpty
              ? '${track.artistsString} • ${_selectedPlayer!.name}'
              : _selectedPlayer!.name;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: artistWithPlayer,
            album: track.album?.name ?? '',
            duration: track.duration,
            artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
          );
          audioHandler.setRemotePlaybackState(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
            duration: track.duration,
          );
        }
      } else {
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
          // Clear notification when no track
          final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
          final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;
          if (!isBuiltinPlayer) {
            audioHandler.clearRemotePlaybackState();
          }
        }
      }

      if (stateChanged) {
        notifyListeners();
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) return;

    if (_selectedPlayer!.isPlaying) {
      await pausePlayer(_selectedPlayer!.playerId);
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
    }

    await refreshPlayers();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        stateChanged = true;
      }
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  // ============================================================================
  // LIBRARY DATA
  // ============================================================================

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final results = await Future.wait([
        _api!.getArtists(limit: LibraryConstants.maxLibraryItems),
        _api!.getAlbums(limit: LibraryConstants.maxLibraryItems),
        _api!.getTracks(limit: LibraryConstants.maxLibraryItems),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load albums');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (!isConnected) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  /// Get artist image URL with fallback to external sources (Deezer, Fanart.tv)
  /// Returns a Future since fallback requires async API calls
  Future<String?> getArtistImageUrlWithFallback(Artist artist, {int size = 256}) async {
    // Try Music Assistant first
    final maUrl = _api?.getImageUrl(artist, size: size);
    if (maUrl != null) {
      return maUrl;
    }

    // Fall back to external sources (Deezer, Fanart.tv, etc.)
    return MetadataService.getArtistImageUrl(artist.name);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    return await _api?.getQueue(playerId);
  }

  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      await _api?.playTrack(playerId, track, clearQueue: clearQueue);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play track');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play track', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);

      final trackIndex = startIndex ?? 0;
      if (tracks.isNotEmpty && trackIndex < tracks.length) {
        _currentTrack = tracks[trackIndex];
        notifyListeners();
      }
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play tracks');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play tracks', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playRadio(String playerId, Track track) async {
    try {
      await _api?.playRadio(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playArtistRadio(String playerId, Artist artist) async {
    try {
      await _api?.playArtistRadio(playerId, artist);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play artist radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play artist radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      await _api?.pausePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Pause player', e);
      rethrow;
    }
  }

  Future<void> resumePlayer(String playerId) async {
    try {
      await _api?.resumePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Resume player', e);
      rethrow;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      await _api?.nextTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Next track', e);
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      await _api?.previousTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Previous track', e);
      rethrow;
    }
  }

  Future<void> stopPlayer(String playerId) async {
    try {
      await _api?.stopPlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Stop player', e);
      rethrow;
    }
  }

  Future<void> togglePower(String playerId) async {
    try {
      _logger.log('🔋 togglePower called for playerId: $playerId');

      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      _logger.log('🔋 Is local builtin player: $isLocalPlayer');

      if (isLocalPlayer) {
        _logger.log('🔋 Handling power toggle LOCALLY for builtin player');

        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');

        if (!_isLocalPlayerPowered) {
          _logger.log('🔋 Stopping playback because powered off');
          await _localPlayer.stop();
        }

        await _reportLocalPlayerState();
        await refreshPlayers();
      } else {
        _logger.log('🔋 Sending power command to server for regular player');

        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        _logger.log('🔋 Current power state: ${player.powered}, will set to: ${!player.powered}');

        await _api?.setPower(playerId, !player.powered);

        _logger.log('🔋 setPower command sent successfully');

        await refreshPlayers();
      }
    } catch (e) {
      _logger.log('🔋 ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId) {
        _localPlayerVolume = volumeLevel;
        await FlutterVolumeController.setVolume(volumeLevel / 100.0);
      }
      await _api?.setVolume(playerId, volumeLevel);
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    try {
      await _api?.seek(playerId, position);
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    try {
      await _api?.toggleShuffle(queueId);
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

  Future<void> cycleRepeatMode(String queueId, String? currentMode) async {
    String nextMode;
    switch (currentMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }
    await setRepeatMode(queueId, nextMode);
  }

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
