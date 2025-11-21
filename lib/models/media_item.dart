enum MediaType {
  artist,
  album,
  track,
  playlist,
  radio,
}

class MediaItem {
  final String itemId;
  final String provider;
  final String name;
  final MediaType mediaType;
  final String? sortName;
  final String? uri;
  final List<String>? providerMappings;
  final Map<String, dynamic>? metadata;
  final bool? favorite;
  final int? position;
  final Duration? duration;

  MediaItem({
    required this.itemId,
    required this.provider,
    required this.name,
    required this.mediaType,
    this.sortName,
    this.uri,
    this.providerMappings,
    this.metadata,
    this.favorite,
    this.position,
    this.duration,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    MediaType? mediaType;
    final mediaTypeStr = json['media_type'] as String?;
    if (mediaTypeStr != null) {
      mediaType = MediaType.values.firstWhere(
        (e) => e.name == mediaTypeStr.toLowerCase(),
        orElse: () => MediaType.track,
      );
    }

    return MediaItem(
      itemId: json['item_id'] as String? ?? json['id'] as String,
      provider: json['provider'] as String? ?? 'unknown',
      name: json['name'] as String,
      mediaType: mediaType ?? MediaType.track,
      sortName: json['sort_name'] as String?,
      uri: json['uri'] as String?,
      providerMappings: (json['provider_mappings'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      favorite: json['favorite'] as bool?,
      position: json['position'] as int?,
      duration: json['duration'] != null
          ? Duration(seconds: (json['duration'] as num).toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider': provider,
      'name': name,
      'media_type': mediaType.name,
      if (sortName != null) 'sort_name': sortName,
      if (uri != null) 'uri': uri,
      if (providerMappings != null) 'provider_mappings': providerMappings,
      if (metadata != null) 'metadata': metadata,
      if (favorite != null) 'favorite': favorite,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration!.inSeconds,
    };
  }
}

class Artist extends MediaItem {
  Artist({
    required super.itemId,
    required super.provider,
    required super.name,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.artist);

  factory Artist.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Artist(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }
}

class Album extends MediaItem {
  final List<Artist>? artists;
  final String? albumType;

  Album({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.albumType,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.album);

  factory Album.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Album(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      albumType: json['album_type'] as String?,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';
}

class Track extends MediaItem {
  final List<Artist>? artists;
  final Album? album;

  Track({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.album,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
    super.position,
    super.duration,
  }) : super(mediaType: MediaType.track);

  factory Track.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Track(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      album: json['album'] != null
          ? Album.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
      position: item.position,
      duration: item.duration,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';
}
