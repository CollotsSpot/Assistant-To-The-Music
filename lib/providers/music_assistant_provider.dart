import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';

class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthService _authService = AuthService();
  final DebugLogger _logger = DebugLogger();
  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  // Player selection
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack; // Current track playing on selected player
  Timer? _playerStateTimer;

  // Player list caching
  DateTime? _playersLastFetched;
  static const Duration _playersCacheDuration = Duration(minutes: 5);

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected;

  // Player selection getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;

  // API access
  MusicAssistantAPI? get api => _api;

  MusicAssistantProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      // Auto-login if credentials are saved
      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        _logger.log('🔐 Auto-login with saved credentials...');
        try {
          final token = await _authService.login(_serverUrl!, username, password);
          if (token != null) {
            _logger.log('✓ Auto-login successful');
          } else {
            _logger.log('⚠️ Auto-login failed - session cookie may be expired');
          }
        } catch (e) {
          _logger.log('⚠️ Auto-login error: $e');
        }
      }

      await connectToServer(_serverUrl!);
    }
  }

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Disconnect existing connection
      await _api?.disconnect();

      _api = MusicAssistantAPI(serverUrl);

      // Listen to connection state changes
      _api!.connectionState.listen((state) {
        _connectionState = state;
        notifyListeners();

        if (state == MAConnectionState.connected) {
          // Load available players and auto-select
          _loadAndSelectPlayers();

          // Auto-load library when connected
          loadLibrary();
        } else if (state == MAConnectionState.disconnected) {
          _availablePlayers = [];
          _selectedPlayer = null;
        }
      });

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

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load artists, albums, and tracks in parallel
      final results = await Future.wait([
        _api!.getArtists(limit: 500),
        _api!.getAlbums(limit: 500),
        _api!.getTracks(limit: 500),
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
      _logger.log('Library load error: ${errorInfo.technicalMessage}');
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
        limit: limit,
        offset: offset,
        search: search,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      _logger.log('Artists load error: ${errorInfo.technicalMessage}');
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
        limit: limit,
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
      _logger.log('Albums load error: ${errorInfo.technicalMessage}');
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

  Future<Map<String, List<MediaItem>>> search(String query) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query);
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

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    return await _api?.getQueue(playerId);
  }

  Future<void> playTrack(String playerId, Track track) async {
    try {
      await _api?.playTrack(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play track');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play track', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play tracks');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play tracks', e);
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

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _api?.setVolume(playerId, volumeLevel);
      // Refresh player state to get updated volume
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      // Refresh player state to get updated mute status
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    try {
      await _api?.toggleShuffle(queueId);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

  /// Cycle through repeat modes: off -> all -> one -> off
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

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  /// Load available players and auto-select one
  Future<void> _loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (!forceRefresh &&
          _playersLastFetched != null &&
          _availablePlayers.isNotEmpty &&
          now.difference(_playersLastFetched!) < _playersCacheDuration) {
        _logger.log('Using cached player list (${_availablePlayers.length} players)');
        return;
      }

      _logger.log('Fetching fresh player list...');
      _availablePlayers = await getPlayers();
      _playersLastFetched = DateTime.now();
      _logger.log('Loaded ${_availablePlayers.length} players');

      // Log each player for debugging
      for (final player in _availablePlayers) {
        _logger.log('  - ${player.name} (${player.playerId}) - available: ${player.available}, state: ${player.state}');
      }

      if (_availablePlayers.isNotEmpty) {
        // Smart player selection logic:
        // 1. If a player is already selected and still available, keep it (ALWAYS)
        // 2. Only auto-select a player if none is currently selected
        // 3. Prefer a playing player, then first available player

        Player? playerToSelect;

        // Keep current selection if still valid - ALWAYS prefer this
        if (_selectedPlayer != null) {
          final stillAvailable = _availablePlayers.any(
            (p) => p.playerId == _selectedPlayer!.playerId && p.available,
          );
          if (stillAvailable) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == _selectedPlayer!.playerId,
            );
            _logger.log('Keeping current player: ${playerToSelect.name}');
          }
        }

        // Only auto-select if NO player is currently selected
        if (playerToSelect == null) {
          // Try to find a playing player first
          try {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.state == 'playing' && p.available,
            );
            _logger.log('Auto-selected playing player: ${playerToSelect.name}');
          } catch (e) {
            // No playing player found, pick first available
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
            _logger.log('Selected first available player: ${playerToSelect.name}');
          }
        }

        selectPlayer(playerToSelect);
      } else {
        _logger.log('⚠️ No players available');
      }

      notifyListeners();
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  /// Select a player for playback
  void selectPlayer(Player player) {
    _selectedPlayer = player;
    _logger.log('Selected player: ${player.name} (${player.playerId})');

    // Start polling for player state
    _startPlayerStatePolling();

    notifyListeners();
  }

  /// Start polling for selected player's current state
  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    // Poll every 2 seconds
    _playerStateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _updatePlayerState();
    });

    // Also update immediately
    _updatePlayerState();
  }

  /// Update the selected player's current state
  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      // Refresh players list to get latest player state
      await refreshPlayers();

      // Only show tracks if player is available and not idle
      final shouldShowTrack = _selectedPlayer!.available &&
                             (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused');

      if (!shouldShowTrack) {
        // Clear track if player is unavailable or idle
        if (_currentTrack != null) {
          _currentTrack = null;
          _logger.log('🗑️ Cleared track - player unavailable or idle (state: ${_selectedPlayer!.state}, available: ${_selectedPlayer!.available})');
          notifyListeners();
        }
        return;
      }

      // Get the player's queue
      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        _currentTrack = queue.currentItem!.track;
        _logger.log('✅ Current track updated: ${_currentTrack!.name}');
        notifyListeners();
      } else {
        if (queue == null) {
          _logger.log('⚠️ Queue is null for player ${_selectedPlayer!.playerId}');
        } else if (queue.currentItem == null) {
          _logger.log('⚠️ Queue currentItem is null (currentIndex: ${queue.currentIndex}, items: ${queue.items.length})');
        }

        if (_currentTrack != null) {
          // Clear current track if queue is empty
          _currentTrack = null;
          _logger.log('🗑️ Cleared current track');
          notifyListeners();
        }
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  /// Control the selected player
  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) {
      _logger.log('⚠️ playPause: No player selected');
      return;
    }

    _logger.log('🎮 playPause: ${_selectedPlayer!.name} - current state: ${_selectedPlayer!.state}');

    if (_selectedPlayer!.isPlaying) {
      _logger.log('⏸️ Pausing player');
      await pausePlayer(_selectedPlayer!.playerId);
    } else {
      _logger.log('▶️ Resuming player');
      await resumePlayer(_selectedPlayer!.playerId);
    }

    // Refresh player state immediately
    await refreshPlayers();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _updatePlayerState();
  }

  /// Refresh the list of available players
  Future<void> refreshPlayers() async {
    await _loadAndSelectPlayers(forceRefresh: true);

    // Update the selected player with fresh data
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );
        _selectedPlayer = updatedPlayer;
        _logger.log('Updated selected player state: ${updatedPlayer.name} - ${updatedPlayer.state}');
      } catch (e) {
        // Selected player no longer available
        _logger.log('Selected player no longer in list');
      }
    }
  }

  // ============================================================================
  // END PLAYER SELECTION
  // ============================================================================

  /// Check connection and reconnect if needed (called when app resumes)
  Future<void> checkAndReconnect() async {
    if (_api == null || _serverUrl == null) {
      _logger.log('⚠️ No API or server URL configured');
      return;
    }

    // Check if we're disconnected
    if (_connectionState != MAConnectionState.connected) {
      _logger.log('🔄 App resumed and disconnected - attempting reconnect...');
      try {
        await connectToServer(_serverUrl!);
        _logger.log('✅ Reconnected successfully');
      } catch (e) {
        _logger.log('❌ Reconnection failed: $e');
      }
    } else {
      _logger.log('✓ Already connected, no reconnection needed');
      // Even if connected, refresh player state
      await refreshPlayers();
    }
  }

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
