import 'media_item.dart';

class Player {
  final String playerId;
  final String name;
  final String? provider; // e.g., 'builtin_player', 'chromecast', etc.
  final bool available;
  final bool powered;
  final String state; // 'idle', 'playing', 'paused'
  final String? currentItemId;
  final int? volumeLevel; // 0-100
  final bool? volumeMuted;
  final double? elapsedTime; // Seconds elapsed in current track
  final double? elapsedTimeLastUpdated; // Unix timestamp when elapsed_time was last updated

  Player({
    required this.playerId,
    required this.name,
    this.provider,
    required this.available,
    required this.powered,
    required this.state,
    this.currentItemId,
    this.volumeLevel,
    this.volumeMuted,
    this.elapsedTime,
    this.elapsedTimeLastUpdated,
  });

  // Derived properties
  bool get isPlaying => state == 'playing';
  bool get isMuted => volumeMuted ?? false;
  int get volume => volumeLevel ?? 0;

  // Track when this Player object was created (for local interpolation fallback)
  static final Map<String, double> _playerCreationTimes = {};

  // Calculate current elapsed time (interpolated if playing)
  double get currentElapsedTime {
    if (elapsedTime == null) {
      return 0;
    }

    if (!isPlaying) {
      return elapsedTime!;
    }

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Try server-provided timestamp first
    if (elapsedTimeLastUpdated != null) {
      final timeSinceUpdate = now - elapsedTimeLastUpdated!;

      // Clamp to reasonable range: 0 to 10 seconds
      // - Negative means clock skew (client ahead of server) - clamp to 0
      // - > 10 seconds likely means stale data or network delay - clamp to 10
      // This prevents jumps while still allowing some interpolation
      final clampedTime = timeSinceUpdate.clamp(0.0, 10.0);
      return elapsedTime! + clampedTime;
    }

    // Fallback: use local creation time for interpolation
    // This handles the case where server doesn't send elapsed_time_last_updated
    final creationKey = '$playerId:$elapsedTime';
    if (!_playerCreationTimes.containsKey(creationKey)) {
      // First time seeing this player/position combo - record creation time
      _playerCreationTimes[creationKey] = now;
      // Clean up old entries to prevent memory leak
      if (_playerCreationTimes.length > 50) {
        final keysToRemove = _playerCreationTimes.keys.take(25).toList();
        for (final key in keysToRemove) {
          _playerCreationTimes.remove(key);
        }
      }
    }

    final creationTime = _playerCreationTimes[creationKey]!;
    final timeSinceCreation = now - creationTime;

    // Clamp local interpolation to 10 seconds as well
    final clampedTime = timeSinceCreation.clamp(0.0, 10.0);
    return elapsedTime! + clampedTime;
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    // Extract current_item_id from current_media if available
    String? currentItemId = json['current_item_id'] as String?;
    double? elapsedTime;
    double? elapsedTimeLastUpdated;

    // Get top-level elapsed time values
    final topLevelElapsedTime = (json['elapsed_time'] as num?)?.toDouble();
    final topLevelLastUpdated = (json['elapsed_time_last_updated'] as num?)?.toDouble();

    // Extract current_item_id and elapsed time from current_media
    // current_media often has the more accurate position after seeks
    if (json.containsKey('current_media')) {
      final currentMedia = json['current_media'] as Map<String, dynamic>?;
      if (currentMedia != null) {
        currentItemId ??= currentMedia['queue_item_id'] as String?;

        final currentMediaElapsedTime = (currentMedia['elapsed_time'] as num?)?.toDouble();
        final currentMediaLastUpdated = (currentMedia['elapsed_time_last_updated'] as num?)?.toDouble();

        // Prefer current_media elapsed_time when available - it reflects actual playback position
        // after seek operations, while top-level elapsed_time may lag behind
        if (currentMediaElapsedTime != null) {
          elapsedTime = currentMediaElapsedTime;
          elapsedTimeLastUpdated = currentMediaLastUpdated ?? topLevelLastUpdated;
        }
      }
    }

    // Fall back to top-level values if current_media didn't have elapsed time
    elapsedTime ??= topLevelElapsedTime;
    elapsedTimeLastUpdated ??= topLevelLastUpdated;

    return Player(
      playerId: json['player_id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String?,
      available: json['available'] as bool? ?? false,
      powered: json['powered'] as bool? ?? false,
      state: json['playback_state'] as String? ?? json['state'] as String? ?? 'idle',
      currentItemId: currentItemId,
      volumeLevel: json['volume_level'] as int?,
      volumeMuted: json['volume_muted'] as bool?,
      elapsedTime: elapsedTime,
      elapsedTimeLastUpdated: elapsedTimeLastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'name': name,
      if (provider != null) 'provider': provider,
      'available': available,
      'powered': powered,
      'state': state,
      if (currentItemId != null) 'current_item_id': currentItemId,
      if (volumeLevel != null) 'volume_level': volumeLevel,
      if (volumeMuted != null) 'volume_muted': volumeMuted,
      if (elapsedTime != null) 'elapsed_time': elapsedTime,
      if (elapsedTimeLastUpdated != null) 'elapsed_time_last_updated': elapsedTimeLastUpdated,
    };
  }
}

class StreamDetails {
  final String? streamId;
  final int sampleRate;
  final int bitDepth;
  final String contentType;

  StreamDetails({
    this.streamId,
    required this.sampleRate,
    required this.bitDepth,
    required this.contentType,
  });

  factory StreamDetails.fromJson(Map<String, dynamic> json) {
    return StreamDetails(
      streamId: json['stream_id'] as String?,
      sampleRate: json['sample_rate'] as int? ?? 44100,
      bitDepth: json['bit_depth'] as int? ?? 16,
      contentType: json['content_type'] as String? ?? 'audio/flac',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'sample_rate': sampleRate,
      'bit_depth': bitDepth,
      'content_type': contentType,
    };
  }
}

class QueueItem {
  final String queueItemId;
  final Track track;
  final StreamDetails? streamdetails;

  QueueItem({
    required this.queueItemId,
    required this.track,
    this.streamdetails,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    // Queue items may have queue_item_id, or we fall back to item_id from the track
    final queueItemId = json['queue_item_id'] as String? ??
                        json['item_id']?.toString() ??
                        '';

    // The track data is nested inside 'media_item' field (if present and not null)
    final mediaItemData = json.containsKey('media_item') && json['media_item'] != null
        ? json['media_item'] as Map<String, dynamic>
        : json;

    return QueueItem(
      queueItemId: queueItemId,
      track: Track.fromJson(mediaItemData),
      streamdetails: json['streamdetails'] != null
          ? StreamDetails.fromJson(json['streamdetails'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'queue_item_id': queueItemId,
      ...track.toJson(),
      if (streamdetails != null) 'streamdetails': streamdetails!.toJson(),
    };
  }
}

class PlayerQueue {
  final String playerId;
  final List<QueueItem> items;
  final int? currentIndex;
  final bool? shuffleEnabled;
  final String? repeatMode; // 'off', 'one', 'all'

  PlayerQueue({
    required this.playerId,
    required this.items,
    this.currentIndex,
    this.shuffleEnabled,
    this.repeatMode,
  });

  bool get shuffle => shuffleEnabled ?? false;
  bool get repeatAll => repeatMode == 'all';
  bool get repeatOne => repeatMode == 'one';
  bool get repeatOff => repeatMode == 'off' || repeatMode == null;

  factory PlayerQueue.fromJson(Map<String, dynamic> json) {
    return PlayerQueue(
      playerId: json['player_id'] as String,
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => QueueItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      currentIndex: json['current_index'] as int?,
      shuffleEnabled: json['shuffle_enabled'] as bool?,
      repeatMode: json['repeat_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'items': items.map((i) => i.toJson()).toList(),
      if (currentIndex != null) 'current_index': currentIndex,
      if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
      if (repeatMode != null) 'repeat_mode': repeatMode,
    };
  }

  QueueItem? get currentItem {
    if (currentIndex == null || items.isEmpty) return null;
    if (currentIndex! < 0 || currentIndex! >= items.length) return null;
    return items[currentIndex!];
  }
}
