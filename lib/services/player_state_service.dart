import 'dart:async';
import '../constants/timings.dart' show Timings;
import '../models/player.dart';
import '../models/media_item.dart';
import 'music_assistant_api.dart';
import 'settings_service.dart';
import 'debug_logger.dart';
import 'error_handler.dart';

/// Callback type for notifying state changes
typedef StateChangeCallback = void Function();

/// Service responsible for player state management.
/// Handles player selection, playback controls, and state polling.
class PlayerStateService {
  final DebugLogger _logger = DebugLogger();
  final StateChangeCallback? onStateChanged;

  MusicAssistantAPI? _api;

  // Player selection
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack;
  Timer? _playerStateTimer;

  // Player list caching
  DateTime? _playersLastFetched;

  PlayerStateService({this.onStateChanged});

  // Getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;
  MusicAssistantAPI? get api => _api;

  /// Set the API instance (called when connection established)
  void setApi(MusicAssistantAPI? api) {
    _api = api;
  }

  /// Clear all player state (called on disconnect)
  void clear() {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _selectedPlayer = null;
    _availablePlayers = [];
    _currentTrack = null;
    _playersLastFetched = null;
  }

  /// Get all players from the API
  Future<List<Player>> getPlayers() async {
    if (_api == null) return [];

    try {
      return await _api!.getPlayers();
    } catch (e) {
      ErrorHandler.logError('Get players', e);
      return [];
    }
  }

  /// Load available players and auto-select one
  Future<void> loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (!forceRefresh &&
          _playersLastFetched != null &&
          _availablePlayers.isNotEmpty &&
          now.difference(_playersLastFetched!) < Timings.playersCacheDuration) {
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players');

      // Filter out unavailable players and legacy ghosts
      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        // Filter out legacy "Music Assistant Mobile" ghosts
        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        // Filter out unavailable players (ghost players from old installations)
        // Exception: Keep our own player even if temporarily unavailable
        if (!player.available) {
          if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
            return true;
          }
          filteredCount++;
          return false;
        }

        return true;
      }).toList();

      _playersLastFetched = DateTime.now();

      _logger.log('🎛️ After filtering: ${_availablePlayers.length} players available');

      if (_availablePlayers.isNotEmpty) {
        Player? playerToSelect;

        // Keep current selection if still valid
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

        // Only auto-select if NO player is currently selected
        if (playerToSelect == null) {
          // Priority 1: Local player (this device)
          if (builtinPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == builtinPlayerId && p.available,
              );
              _logger.log('📱 Auto-selected local player: ${playerToSelect?.name}');
            } catch (e) {
              // Local player not found
            }
          }

          // Priority 2: A currently playing player
          if (playerToSelect == null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.state == 'playing' && p.available,
              );
            } catch (e) {
              // No playing player
            }
          }

          // Priority 3: First available player
          if (playerToSelect == null) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
          }
        }

        selectPlayer(playerToSelect);
      }

      onStateChanged?.call();
    } catch (e) {
      ErrorHandler.logError('Load players', e);
    }
  }

  /// Select a player and start polling its state
  void selectPlayer(Player player) {
    _selectedPlayer = player;
    _startPlayerPolling();
    onStateChanged?.call();
  }

  /// Start polling player state at configured interval
  void _startPlayerPolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    _playerStateTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      try {
        await updatePlayerState();
      } catch (e) {
        _logger.log('Error updating player state (will retry): $e');
      }
    });

    // Also update immediately
    updatePlayerState();
  }

  /// Update the selected player's state from the server
  Future<void> updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      final updatedPlayer = await _api!.getPlayer(_selectedPlayer!.playerId);
      if (updatedPlayer != null) {
        _selectedPlayer = updatedPlayer;

        // Get current track info if playing
        if (updatedPlayer.currentMedia != null) {
          _currentTrack = updatedPlayer.currentMedia;
        }

        onStateChanged?.call();
      }
    } catch (e) {
      _logger.log('Error updating player state: $e');
    }
  }

  /// Refresh the list of available players
  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;

    await loadAndSelectPlayers(forceRefresh: true);

    // If selected player changed state, notify listeners
    if (_selectedPlayer?.state != previousState) {
      onStateChanged?.call();
    }
  }

  // ============================================================================
  // PLAYBACK CONTROLS
  // ============================================================================

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
      await _api?.playPlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Resume player', e);
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

  Future<void> togglePower(String playerId) async {
    try {
      final player = _availablePlayers.firstWhere(
        (p) => p.playerId == playerId,
        orElse: () => throw Exception('Player not found'),
      );

      if (player.powered) {
        await _api?.powerOffPlayer(playerId);
      } else {
        await _api?.powerOnPlayer(playerId);
      }

      await refreshPlayers();
    } catch (e) {
      _logger.log('ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
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
  // CONVENIENCE METHODS (for selected player)
  // ============================================================================

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) return;

    if (_selectedPlayer!.state == 'playing') {
      await pausePlayer(_selectedPlayer!.playerId);
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
    }
    await Future.delayed(Timings.trackChangeDelay);
    await updatePlayerState();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await updatePlayerState();
  }
}
