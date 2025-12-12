import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/local_player_service.dart';
import '../services/auth/auth_manager.dart';
import '../services/device_id_service.dart';
import '../services/cache_service.dart';
import '../constants/timings.dart';
import '../main.dart' show audioHandler;

/// Provider for managing player state, selection, and controls
class PlayerProvider with ChangeNotifier {
  final DebugLogger _logger = DebugLogger();
  late final LocalPlayerService _localPlayer;
  final CacheService _cacheService;

  // Dependencies injected from parent provider
  MusicAssistantAPI? _api;
  AuthManager? _authManager;
  String? _serverUrl;

  // Player selection
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack;
  Timer? _playerStateTimer;
  Timer? _adjacentPlayerCacheTimer;

  // Local Playback
  bool _isLocalPlayerPowered = true;
  StreamSubscription? _localPlayerEventSubscription;
  StreamSubscription? _playerUpdatedEventSubscription;
  Timer? _localPlayerStateReportTimer;

  // Pending metadata from player_updated events
  TrackMetadata? _pendingTrackMetadata;
  TrackMetadata? _currentNotificationMetadata;

  // Registration guard
  Completer<void>? _registrationInProgress;

  // Getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;
  bool get isLocalPlayerPowered => _isLocalPlayerPowered;

  /// Get cached track for a player (used for smooth swipe transitions)
  Track? getCachedTrackForPlayer(String playerId) => _cacheService.getCachedTrackForPlayer(playerId);

  PlayerProvider(this._cacheService, AuthManager authManager) {
    _authManager = authManager;
    _localPlayer = LocalPlayerService(authManager);
  }

  /// Initialize with API reference after connection
  void initialize(MusicAssistantAPI api, String serverUrl) {
    _api = api;
    _serverUrl = serverUrl;
  }

  /// Set up event listeners after connection
  Future<void> setupEventListeners() async {
    if (_api == null) return;

    // Listen to built-in player events
    _localPlayerEventSubscription?.cancel();
    _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(
      _handleLocalPlayerEvent,
      onError: (error) {
        _logger.log('Builtin player event stream error: $error');
      },
    );

    // Listen to player_updated events
    _playerUpdatedEventSubscription?.cancel();
    _playerUpdatedEventSubscription = _api!.playerUpdatedEvents.listen(
      _handlePlayerUpdatedEvent,
      onError: (error) {
        _logger.log('Player updated event stream error: $error');
      },
    );
  }

  /// Initialize local playback
  Future<void> initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true;

    // Wire up skip button callbacks
    audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      nextTrackSelectedPlayer();
    };
    audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      previousTrackSelectedPlayer();
    };

    if (_api != null) {
      await registerLocalPlayer();
    }
  }

  /// Try to adopt an existing ghost player
  Future<bool> tryAdoptGhostPlayer() async {
    if (_api == null) return false;

    try {
      final isFresh = await DeviceIdService.isFreshInstallation();
      if (!isFresh) {
        _logger.log('👻 Not a fresh install, skipping ghost adoption');
        return false;
      }

      final ownerName = await SettingsService.getOwnerName();
      if (ownerName == null || ownerName.isEmpty) {
        _logger.log('👻 No owner name set, cannot adopt ghost player');
        return false;
      }

      _logger.log('👻 Fresh install detected, searching for adoptable ghost for "$ownerName"...');
      final adoptableId = await _api!.findAdoptableGhostPlayer(ownerName);
      if (adoptableId == null) {
        _logger.log('👻 No matching ghost player found - will generate new ID');
        return false;
      }

      _logger.log('👻 Found adoptable ghost: $adoptableId');
      await DeviceIdService.adoptPlayerId(adoptableId);

      _logger.log('✅ Successfully adopted ghost player');
      return true;
    } catch (e) {
      _logger.log('⚠️ Ghost adoption failed (non-fatal): $e');
      return false;
    }
  }

  /// Register local player with MA server
  Future<void> registerLocalPlayer() async {
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
      _logger.log('❌ CRITICAL: Player registration failed: $e');
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

    // Don't try to report state if not authenticated - avoids spamming errors
    if (_api!.currentConnectionState != MAConnectionState.authenticated) return;

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    final volume = (_localPlayer.volume * 100).round();
    final isPaused = !isPlaying && position > 0;

    await _api!.updateBuiltinPlayerState(
      playerId,
      powered: _isLocalPlayerPowered,
      playing: isPlaying,
      paused: isPaused,
      position: position,
      volume: volume,
      muted: _localPlayer.volume == 0.0,
    );
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    _logger.log('📥 Local player event received: ${event['type'] ?? event['command']}');

    try {
      final eventPlayerId = event['player_id'] as String?;
      final myPlayerId = await SettingsService.getBuiltinPlayerId();

      if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
        _logger.log('🚫 Ignoring event for different player: $eventPlayerId');
        return;
      }

      final command = (event['type'] as String?) ?? (event['command'] as String?);

      switch (command) {
        case 'play_media':
          final urlPath = event['media_url'] as String? ?? event['url'] as String?;

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
          final volume = event['volume_level'] as int?;
          if (volume != null) {
            await _localPlayer.setVolume(volume / 100.0);
          }
          break;

        case 'power_on':
        case 'power_off':
        case 'power':
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
            if (!_isLocalPlayerPowered) {
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
          if (imageUrl != null && _serverUrl != null) {
            var finalImageUrl = imageUrl;
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
            metadata = {
              'images': [{'path': finalImageUrl, 'provider': 'direct'}]
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

          _logger.log('📋 Cached track for $playerName: ${trackFromEvent.name}');

          if (imageUrl != null) {
            final images = metadata?['images'] as List?;
            if (images != null && images.isNotEmpty) {
              final imagePath = images[0]['path'] as String?;
              if (imagePath != null) {
                _precacheImage(imagePath);
              }
            }
          }

          notifyListeners();
        }
      }

      // Handle notification metadata for local player
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId == null || playerId != builtinPlayerId) return;

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

      final notificationNeedsUpdate = _currentNotificationMetadata != null &&
          (_currentNotificationMetadata!.title != title ||
           _currentNotificationMetadata!.artist != artist);

      if (_localPlayer.isPlaying && notificationNeedsUpdate) {
        await _localPlayer.updateNotificationWhilePlaying(newMetadata);
        _currentNotificationMetadata = newMetadata;
      }
    } catch (e) {
      _logger.log('Error handling player_updated event: $e');
    }
  }

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  Future<void> loadAndSelectPlayers({bool forceRefresh = false}) async {
    if (_api == null) return;

    try {
      if (!forceRefresh && _cacheService.isPlayersCacheValid() && _availablePlayers.isNotEmpty) {
        return;
      }

      final allPlayers = await _api!.getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players');

      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        if (nameLower == 'this device' || player.playerId.startsWith('ma_')) {
          filteredCount++;
          return false;
        }

        if (player.playerId.startsWith('ensemble_')) {
          if (builtinPlayerId == null || player.playerId != builtinPlayerId) {
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
            } catch (e) {}
          }

          if (playerToSelect == null && builtinPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == builtinPlayerId && p.available,
              );
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

      _preloadAdjacentPlayers(preloadAll: true);
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  void selectPlayer(Player player, {bool skipNotify = false}) {
    _selectedPlayer = player;
    SettingsService.setLastSelectedPlayerId(player.playerId);
    _startPlayerStatePolling();
    _preloadAdjacentPlayers();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  Future<void> _preloadAdjacentPlayers({bool preloadAll = false}) async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();
    if (players.isEmpty) return;

    if (preloadAll) {
      _logger.log('🖼️ Preloading track info for all ${players.length} players...');
      await Future.wait(players.map((player) => _preloadPlayerTrack(player)));
      _logger.log('🖼️ Preloading complete');
      return;
    }

    if (_selectedPlayer == null || players.length <= 1) return;

    final currentIndex = players.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);
    if (currentIndex == -1) return;

    final prevIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    final nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;

    final playersToPreload = <Player>{};
    if (prevIndex != currentIndex) playersToPreload.add(players[prevIndex]);
    if (nextIndex != currentIndex) playersToPreload.add(players[nextIndex]);

    for (final player in playersToPreload) {
      _preloadPlayerTrack(player);
    }
  }

  Future<void> _preloadPlayerTrack(Player player) async {
    if (_api == null) return;

    try {
      if (!player.available || !player.powered) {
        _cacheService.setCachedTrackForPlayer(player.playerId, null);
        return;
      }

      final queue = await _api!.getQueue(player.playerId);

      if (queue != null && queue.currentItem != null) {
        final track = queue.currentItem!.track;
        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        final existingHasImage = existingTrack?.metadata?['images'] != null;
        final newHasImage = track.metadata?['images'] != null;

        if (!existingHasImage || newHasImage) {
          _cacheService.setCachedTrackForPlayer(player.playerId, track);
        }

        final artworkUrl512 = _api!.getImageUrl(existingHasImage ? existingTrack! : track, size: 512);
        if (artworkUrl512 != null) {
          await _precacheImage(artworkUrl512);
        }
      } else {
        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        if (existingTrack?.metadata?['images'] == null) {
          _cacheService.setCachedTrackForPlayer(player.playerId, null);
        }
      }
    } catch (e) {
      _logger.log('Error preloading player track for ${player.name}: $e');
    }
  }

  Future<void> _precacheImage(String url) async {
    try {
      final imageProvider = NetworkImage(url);
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
      await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
        imageStream.removeListener(listener);
      });
    } catch (e) {
      _logger.log('Image precache failed for $url: $e');
    }
  }

  Future<void> preloadAllPlayerTracks() async {
    if (_api == null) return;
    final players = _availablePlayers.where((p) => p.available).toList();
    await Future.wait(players.map((player) => _preloadPlayerTrack(player)));
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

      final allPlayers = await _api!.getPlayers();
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
        if (stateChanged) notifyListeners();
        return;
      }

      final queue = await _api!.getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        if (_currentTrack == null ||
            _currentTrack!.uri != queue.currentItem!.track.uri ||
            _currentTrack!.name != queue.currentItem!.track.name) {
          _currentTrack = queue.currentItem!.track;
          stateChanged = true;

          final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
          if (builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId) {
            final track = _currentTrack!;
            final artworkUrl = _api?.getImageUrl(track, size: 512);
            _localPlayer.updateNotification(
              id: track.uri ?? track.itemId,
              title: track.name,
              artist: track.artistsString,
              album: track.album?.name,
              artworkUrl: artworkUrl,
              duration: track.duration,
            );
          }
        }
      } else {
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
        }
      }

      if (stateChanged) notifyListeners();
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  // ============================================================================
  // PLAYER CONTROLS
  // ============================================================================

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null || _api == null) return;

    if (_selectedPlayer!.isPlaying) {
      await _api!.pausePlayer(_selectedPlayer!.playerId);
    } else {
      await _api!.resumePlayer(_selectedPlayer!.playerId);
    }

    await refreshPlayers();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null || _api == null) return;
    await _api!.nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null || _api == null) return;
    await _api!.previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await loadAndSelectPlayers(forceRefresh: true);

    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        if (updatedPlayer.state != previousState || updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        stateChanged = true;
      }
    }

    if (stateChanged) notifyListeners();
  }

  Future<void> togglePower(String playerId) async {
    if (_api == null) return;

    try {
      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      if (isLocalPlayer) {
        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        if (!_isLocalPlayerPowered) {
          await _localPlayer.stop();
        }
        await _reportLocalPlayerState();
        await refreshPlayers();
      } else {
        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        await _api!.setPower(playerId, !player.powered);
        await refreshPlayers();
      }
    } catch (e) {
      ErrorHandler.logError('Toggle power', e);
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    if (_api == null) return;
    try {
      await _api!.setVolume(playerId, volumeLevel);
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    if (_api == null) return;
    try {
      await _api!.setMute(playerId, muted);
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    if (_api == null) return;
    try {
      await _api!.seek(playerId, position);
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    if (_api == null) return;
    try {
      await _api!.toggleShuffle(queueId);
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    if (_api == null) return;
    try {
      await _api!.setRepeatMode(queueId, mode);
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

  void clearState() {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _availablePlayers = [];
    _selectedPlayer = null;
    _currentTrack = null;
  }

  @override
  void dispose() {
    clearState();
    super.dispose();
  }
}
