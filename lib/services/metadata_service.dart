import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class MetadataService {
  // Cache to avoid repeated API calls for the same artist/album
  static final Map<String, String> _cache = {};

  // Cache for artist images
  static final Map<String, String?> _artistImageCache = {};

  /// Fetches artist biography/description with fallback chain:
  /// 1. Music Assistant metadata (passed in)
  /// 2. Last.fm API (if key configured)
  /// 3. TheAudioDB API (if key configured)
  static Future<String?> getArtistDescription(
    String artistName,
    Map<String, dynamic>? musicAssistantMetadata,
  ) async {
    // Try Music Assistant metadata first
    if (musicAssistantMetadata != null) {
      final maDescription = musicAssistantMetadata['description'] ??
          musicAssistantMetadata['biography'] ??
          musicAssistantMetadata['wiki'] ??
          musicAssistantMetadata['bio'] ??
          musicAssistantMetadata['summary'];

      if (maDescription != null && (maDescription as String).trim().isNotEmpty) {
        return maDescription;
      }
    }

    // Check cache
    final cacheKey = 'artist:$artistName';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Try Last.fm API
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null && lastFmKey.isNotEmpty) {
      final lastFmDesc = await _fetchFromLastFm(artistName, null, lastFmKey);
      if (lastFmDesc != null) {
        _cache[cacheKey] = lastFmDesc;
        return lastFmDesc;
      }
    }

    // Try TheAudioDB API
    final audioDbKey = await SettingsService.getTheAudioDbApiKey();
    if (audioDbKey != null && audioDbKey.isNotEmpty) {
      final audioDbDesc = await _fetchFromTheAudioDb(artistName, audioDbKey);
      if (audioDbDesc != null) {
        _cache[cacheKey] = audioDbDesc;
        return audioDbDesc;
      }
    }

    return null;
  }

  /// Fetches album description with fallback chain:
  /// 1. Music Assistant metadata (passed in)
  /// 2. Last.fm API (if key configured)
  static Future<String?> getAlbumDescription(
    String artistName,
    String albumName,
    Map<String, dynamic>? musicAssistantMetadata,
  ) async {
    // Try Music Assistant metadata first
    if (musicAssistantMetadata != null) {
      final maDescription = musicAssistantMetadata['description'] ??
          musicAssistantMetadata['wiki'] ??
          musicAssistantMetadata['biography'] ??
          musicAssistantMetadata['summary'];

      if (maDescription != null && (maDescription as String).trim().isNotEmpty) {
        return maDescription;
      }
    }

    // Check cache
    final cacheKey = 'album:$artistName:$albumName';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Try Last.fm API (TheAudioDB doesn't have good album info)
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null && lastFmKey.isNotEmpty) {
      final lastFmDesc = await _fetchFromLastFm(artistName, albumName, lastFmKey);
      if (lastFmDesc != null) {
        _cache[cacheKey] = lastFmDesc;
        return lastFmDesc;
      }
    }

    return null;
  }

  static Future<String?> _fetchFromLastFm(
    String artistName,
    String? albumName,
    String apiKey,
  ) async {
    try {
      final String method;
      final Map<String, String> params = {
        'api_key': apiKey,
        'format': 'json',
      };

      if (albumName != null) {
        // Album info
        method = 'album.getinfo';
        params['artist'] = artistName;
        params['album'] = albumName;
      } else {
        // Artist info
        method = 'artist.getinfo';
        params['artist'] = artistName;
      }

      params['method'] = method;

      final uri = Uri.https('ws.audioscrobbler.com', '/2.0/', params);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (albumName != null) {
          // Parse album response
          final album = data['album'];
          if (album != null) {
            final wiki = album['wiki'];
            if (wiki != null) {
              // Prefer summary, fall back to content
              return _cleanLastFmText(wiki['summary'] ?? wiki['content']);
            }
          }
        } else {
          // Parse artist response
          final artist = data['artist'];
          if (artist != null) {
            final bio = artist['bio'];
            if (bio != null) {
              // Prefer summary, fall back to content
              return _cleanLastFmText(bio['summary'] ?? bio['content']);
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Last.fm API error: $e');
    }
    return null;
  }

  static Future<String?> _fetchFromTheAudioDb(
    String artistName,
    String apiKey,
  ) async {
    try {
      final uri = Uri.https(
        'theaudiodb.com',
        '/api/v1/json/$apiKey/search.php',
        {'s': artistName},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final artists = data['artists'];

        if (artists != null && artists.isNotEmpty) {
          final artist = artists[0];
          // Try multiple language fields
          return artist['strBiographyEN'] ??
              artist['strBiographyDE'] ??
              artist['strBiographyFR'] ??
              artist['strBiographyIT'] ??
              artist['strBiographyES'];
        }
      }
    } catch (e) {
      print('⚠️ TheAudioDB API error: $e');
    }
    return null;
  }

  /// Removes Last.fm HTML tags and links
  static String? _cleanLastFmText(String? text) {
    if (text == null) return null;

    // Remove <a href...> tags
    text = text.replaceAll(RegExp(r'<a[^>]*>'), '');
    text = text.replaceAll('</a>', '');

    // Remove "Read more on Last.fm" footer
    text = text.replaceAll(RegExp(r'\s*<a[^>]*>.*?</a>.*$'), '');

    // Clean up any remaining HTML
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    return text.trim();
  }

  // Cache for MusicBrainz IDs (artist name -> MBID)
  static final Map<String, String?> _mbidCache = {};

  /// Fetches artist image URL with fallback chain:
  /// 1. Fanart.tv (requires free API key, uses MusicBrainz ID)
  /// 2. TheAudioDB (if key configured)
  /// Returns the image URL if found, null otherwise
  static Future<String?> getArtistImageUrl(String artistName) async {
    // Check cache first
    final cacheKey = 'artistImage:$artistName';
    if (_artistImageCache.containsKey(cacheKey)) {
      return _artistImageCache[cacheKey];
    }

    // Try Fanart.tv first (best source, free API key)
    final fanartKey = await SettingsService.getFanartTvApiKey();
    if (fanartKey != null && fanartKey.isNotEmpty) {
      // First get MusicBrainz ID (free, no key needed)
      final mbid = await _getMusicBrainzArtistId(artistName);
      if (mbid != null) {
        final imageUrl = await _fetchArtistImageFromFanartTv(mbid, fanartKey);
        if (imageUrl != null) {
          _artistImageCache[cacheKey] = imageUrl;
          return imageUrl;
        }
      }
    }

    // Try TheAudioDB API as fallback
    final audioDbKey = await SettingsService.getTheAudioDbApiKey();
    if (audioDbKey != null && audioDbKey.isNotEmpty) {
      final imageUrl = await _fetchArtistImageFromTheAudioDb(artistName, audioDbKey);
      if (imageUrl != null) {
        _artistImageCache[cacheKey] = imageUrl;
        return imageUrl;
      }
    }

    // Cache the null result to avoid repeated failed lookups
    _artistImageCache[cacheKey] = null;
    return null;
  }

  /// Get MusicBrainz artist ID from artist name (free, no API key required)
  static Future<String?> _getMusicBrainzArtistId(String artistName) async {
    // Check cache
    if (_mbidCache.containsKey(artistName)) {
      return _mbidCache[artistName];
    }

    try {
      // MusicBrainz requires a User-Agent header
      final uri = Uri.https(
        'musicbrainz.org',
        '/ws/2/artist/',
        {
          'query': 'artist:$artistName',
          'fmt': 'json',
          'limit': '1',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Ensemble/1.0 (music-player-app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final artists = data['artists'] as List?;
        if (artists != null && artists.isNotEmpty) {
          final mbid = artists[0]['id'] as String?;
          _mbidCache[artistName] = mbid;
          return mbid;
        }
      }
    } catch (e) {
      print('⚠️ MusicBrainz lookup error: $e');
    }

    _mbidCache[artistName] = null;
    return null;
  }

  /// Fetch artist image from Fanart.tv using MusicBrainz ID
  static Future<String?> _fetchArtistImageFromFanartTv(
    String mbid,
    String apiKey,
  ) async {
    try {
      final uri = Uri.https(
        'webservice.fanart.tv',
        '/v3/music/$mbid',
        {'api_key': apiKey},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Try artistthumb first (best for cards), then artistbackground
        final thumbs = data['artistthumb'] as List?;
        if (thumbs != null && thumbs.isNotEmpty) {
          return thumbs[0]['url'] as String?;
        }

        final backgrounds = data['artistbackground'] as List?;
        if (backgrounds != null && backgrounds.isNotEmpty) {
          return backgrounds[0]['url'] as String?;
        }
      }
    } catch (e) {
      print('⚠️ Fanart.tv artist image error: $e');
    }
    return null;
  }

  /// Fetch artist image from TheAudioDB
  static Future<String?> _fetchArtistImageFromTheAudioDb(
    String artistName,
    String apiKey,
  ) async {
    try {
      final uri = Uri.https(
        'theaudiodb.com',
        '/api/v1/json/$apiKey/search.php',
        {'s': artistName},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final artists = data['artists'];

        if (artists != null && artists.isNotEmpty) {
          final artist = artists[0];
          // Try different image fields in order of preference
          return artist['strArtistThumb'] ??
              artist['strArtistFanart'] ??
              artist['strArtistFanart2'] ??
              artist['strArtistFanart3'];
        }
      }
    } catch (e) {
      print('⚠️ TheAudioDB artist image error: $e');
    }
    return null;
  }

  /// Clears the metadata cache
  static void clearCache() {
    _cache.clear();
    _artistImageCache.clear();
    _mbidCache.clear();
  }
}
