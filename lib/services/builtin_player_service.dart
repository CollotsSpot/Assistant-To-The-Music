import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/builtin_player_event.dart';
import '../models/audio_track.dart';
import 'music_assistant_api.dart';
import 'audio_player_service.dart';
import 'debug_logger.dart';
import 'settings_service.dart';

/// Service that implements Music Assistant's built-in player protocol
///
/// This service:
/// 1. Listens for BuiltinPlayerEvent from Music Assistant via WebSocket
/// 2. Controls the local audio player based on those events
/// 3. Sends playback state updates back to Music Assistant
class BuiltinPlayerService {
  final MusicAssistantAPI _api;
  final AudioPlayerService _audioPlayer;
  final _logger = DebugLogger();

  StreamSubscription? _eventSubscription;
  Timer? _stateUpdateTimer;

  BuiltinPlayerService(this._api, this._audioPlayer);

  /// Start listening for built-in player events
  void start() {
    _logger.log('Starting built-in player service');

    // Listen for built-in player events from Music Assistant
    _eventSubscription = _api.builtinPlayerEvents.listen(_handlePlayerEvent);

    // Start periodic state updates (every 5 seconds when playing, 20 seconds when idle)
    _startStateUpdates();

    // Listen to local player state changes
    _audioPlayer.playerStateStream.listen((state) {
      // Immediately update state when playback state changes
      if (state.playing != _audioPlayer.isPlaying) {
        _sendStateUpdate();
      }
    });
  }

  /// Handle built-in player events from Music Assistant
  void _handlePlayerEvent(BuiltinPlayerEvent event) async {
    _logger.log('Handling built-in player event: ${event.type.value}');

    try {
      switch (event.type) {
        case BuiltinPlayerEventType.playMedia:
          await _handlePlayMedia(event);
          break;

        case BuiltinPlayerEventType.play:
        case BuiltinPlayerEventType.resume:
          await _audioPlayer.play();
          _sendStateUpdate();
          break;

        case BuiltinPlayerEventType.pause:
          await _audioPlayer.pause();
          _sendStateUpdate();
          break;

        case BuiltinPlayerEventType.stop:
          await _audioPlayer.pause();
          _sendStateUpdate();
          break;

        default:
          _logger.log('Unhandled player event type: ${event.type.value}');
      }
    } catch (e) {
      _logger.log('Error handling player event: $e');
    }
  }

  /// Handle PLAY_MEDIA event - load and play the media URL
  Future<void> _handlePlayMedia(BuiltinPlayerEvent event) async {
    if (event.mediaUrl == null) {
      _logger.log('⚠️ PLAY_MEDIA event has no media_url');
      return;
    }

    try {
      // Get server URL to construct full media URL
      final serverUrl = await SettingsService.getServerUrl();
      var baseUrl = serverUrl;

      // Add protocol if missing
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      // Add port if needed (check for custom port setting)
      final uri = Uri.parse(baseUrl);
      final customPort = await SettingsService.getWebSocketPort();

      if (customPort != null) {
        baseUrl = '${uri.scheme}://${uri.host}:$customPort';
      } else if (!uri.hasPort) {
        // Default to 443 for HTTPS if no port specified
        baseUrl = '${uri.scheme}://${uri.host}';
      }

      // Construct full media URL
      final mediaUrl = '$baseUrl/${event.mediaUrl}';
      _logger.log('🎵 Playing media: $mediaUrl');

      // Create AudioTrack and play
      final track = AudioTrack(
        id: 'builtin_player_track',
        title: 'Now Playing',
        artist: 'Music Assistant',
        filePath: mediaUrl,
      );

      await _audioPlayer.setPlaylist([track]);
      await _audioPlayer.play();

      _sendStateUpdate();

      _logger.log('✓ Media loaded and playing');
    } catch (e) {
      _logger.log('Error playing media: $e');
      // Send error state to Music Assistant
      _sendStateUpdate();
    }
  }

  /// Start periodic state updates to Music Assistant
  void _startStateUpdates() {
    _stateUpdateTimer?.cancel();

    // Update every 5 seconds
    _stateUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendStateUpdate();
    });
  }

  /// Send current playback state to Music Assistant
  void _sendStateUpdate() {
    final isPlaying = _audioPlayer.isPlaying;
    final position = _audioPlayer.position.inMilliseconds / 1000.0; // Convert to seconds

    final state = BuiltinPlayerState(
      powered: true,
      playing: isPlaying,
      paused: !isPlaying,
      position: position,
      volume: 100.0, // TODO: Get actual volume from audio player
      muted: false,
    );

    _api.updateBuiltinPlayerState(state);
  }

  /// Stop the service
  void stop() {
    _logger.log('Stopping built-in player service');
    _eventSubscription?.cancel();
    _stateUpdateTimer?.cancel();
  }

  void dispose() {
    stop();
  }
}
