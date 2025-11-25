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

  // Debug: Get ALL players including filtered ones
  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

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
      // Use a high limit to fetch "all" items (assuming library < 5000 items per type)
      final results = await Future.wait([
        _api!.getArtists(limit: 5000),
        _api!.getAlbums(limit: 5000),
        _api!.getTracks(limit: 5000),
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
        limit: limit ?? 5000, // Default to high limit if not specified
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
        limit: limit ?? 5000, // Default to high limit
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
      // Find the player to get current power state
      final player = _availablePlayers.firstWhere(
        (p) => p.playerId == playerId,
        orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
            ? _selectedPlayer!
            : throw Exception("Player not found"),
      );
      
      // Toggle the state
      await _api?.setPower(playerId, !player.powered);
      
      // Immediately refresh players to update UI
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Toggle power', e);
      // Don't rethrow to avoid crashing UI, just log
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _api?.setVolume(playerId, volumeLevel);
      // Don't refresh immediately - let automatic polling pick up the change
      // This prevents the slider from snapping back before the server updates
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

  Future<void> seek(String playerId, int position) async {
    try {
      await _api?.seek(playerId, position);
      // Player state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Seek', e);
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
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      // Filter out ghost players and duplicates
      // 1. "Music Assistant Mobile" players are legacy/ghosts
      // 2. "This Device" players: Only keep the one matching our client ID
      int filteredCount = 0;
      final List<String> ghostPlayerIds = [];

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        // Legacy ghosts
        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          ghostPlayerIds.add('${player.playerId} (Mobile Ghost)');
          return false;
        }

        // Filter "This Device" duplicates
        if (nameLower.contains('this device')) {
          // If we have a builtin ID, only keep the player that matches it
          if (builtinPlayerId != null && player.playerId != builtinPlayerId) {
            filteredCount++;
            ghostPlayerIds.add('${player.playerId} (Duplicate This Device)');
            return false;
          }
          // If we don't have a builtin ID yet (rare), or this matches, keep it
        }

        return true;
      }).toList();

      _playersLastFetched = DateTime.now();

      // Log details about ghost players
      if (filteredCount > 0) {
        _logger.log('🧹 Filtered out $filteredCount ghost players:');
        for (int i = 0; i < ghostPlayerIds.length && i < 5; i++) {
          _logger.log('   - ${ghostPlayerIds[i]}');
        }
        if (ghostPlayerIds.length > 5) {
          _logger.log('   ... and ${ghostPlayerIds.length - 5} more');
        }
        _logger.log('📊 Result: ${_availablePlayers.length} valid players from ${allPlayers.length} total');
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

      // Don't call notifyListeners here - selectPlayer already does it
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  /// Select a player for playback
  void selectPlayer(Player player, {bool skipNotify = false}) {
    _selectedPlayer = player;
    _logger.log('Selected player: ${player.name} (${player.playerId})');

    // Start polling for player state
    _startPlayerStatePolling();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  /// Start polling for selected player's current state
  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    // Poll every 5 seconds for better performance
    _playerStateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updatePlayerState();
    });

    // Also update immediately
    _updatePlayerState();
  }

  /// Update the selected player's current state
  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      bool stateChanged = false;

      // Fetch only the selected player's state instead of all players
      final allPlayers = await getPlayers();
      final updatedPlayer = allPlayers.firstWhere(
        (p) => p.playerId == _selectedPlayer!.playerId,
        orElse: () => _selectedPlayer!,
      );

      // Check if player state actually changed
      if (updatedPlayer.state != _selectedPlayer!.state ||
          updatedPlayer.volumeLevel != _selectedPlayer!.volumeLevel ||
          updatedPlayer.volumeMuted != _selectedPlayer!.volumeMuted ||
          updatedPlayer.available != _selectedPlayer!.available) {
        _selectedPlayer = updatedPlayer;
        stateChanged = true;
      }

      // Only show tracks if player is available and not idle
      final shouldShowTrack = _selectedPlayer!.available &&
                             (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused');

      if (!shouldShowTrack) {
        // Clear track if player is unavailable or idle
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      // Get the player's queue
      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        // Only update if track actually changed
        if (_currentTrack == null ||
            _currentTrack!.uri != queue.currentItem!.track.uri ||
            _currentTrack!.name != queue.currentItem!.track.name) {
          _currentTrack = queue.currentItem!.track;
          stateChanged = true;
        }
      } else {
        if (_currentTrack != null) {
          // Clear current track if queue is empty
          _currentTrack = null;
          stateChanged = true;
        }
      }

      // Only notify if something actually changed
      if (stateChanged) {
        notifyListeners();
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
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    // Update the selected player with fresh data
    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        // Check if state actually changed
        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        // Selected player no longer available
        stateChanged = true;
      }
    }

    // Only notify if state changed
    if (stateChanged) {
      notifyListeners();
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
