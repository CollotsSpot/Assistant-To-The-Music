import '../constants/timings.dart' show LibraryConstants;
import '../models/media_item.dart';
import 'music_assistant_api.dart';
import 'debug_logger.dart';
import 'error_handler.dart';

/// Service responsible for library data management.
/// Handles loading and caching of artists, albums, tracks, and search.
class LibraryService {
  final DebugLogger _logger = DebugLogger();

  MusicAssistantAPI? _api;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // Getters
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  /// Set the API instance (called when connection established)
  void setApi(MusicAssistantAPI? api) {
    _api = api;
  }

  /// Clear all library data (called on disconnect)
  void clear() {
    _artists = [];
    _albums = [];
    _tracks = [];
    _error = null;
    _isLoading = false;
  }

  /// Save search state for persistence across screen changes
  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
  }

  /// Clear search state
  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {
      'artists': [],
      'albums': [],
      'tracks': [],
    };
  }

  /// Load all library data (artists, albums, tracks) in parallel
  /// Returns true if successful
  Future<bool> loadLibrary() async {
    if (_api == null) return false;

    try {
      _isLoading = true;
      _error = null;

      final results = await Future.wait([
        _api!.getArtists(limit: LibraryConstants.maxLibraryItems),
        _api!.getAlbums(limit: LibraryConstants.maxLibraryItems),
        _api!.getTracks(limit: LibraryConstants.maxLibraryItems),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      return true;
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      return false;
    }
  }

  /// Load artists with optional pagination and search
  Future<bool> loadArtists({int? limit, int? offset, String? search}) async {
    if (_api == null) return false;

    try {
      _isLoading = true;
      _error = null;

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
      );

      _isLoading = false;
      return true;
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      return false;
    }
  }

  /// Load albums with optional pagination, search, and artist filter
  Future<bool> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (_api == null) return false;

    try {
      _isLoading = true;
      _error = null;

      _albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      return true;
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load albums');
      _error = errorInfo.userMessage;
      _isLoading = false;
      return false;
    }
  }

  /// Get tracks for a specific album
  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (_api == null) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  /// Search for artists, albums, and tracks
  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (_api == null) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  /// Get recent albums
  Future<List<Album>> getRecentAlbums({int limit = 10}) async {
    if (_api == null) return [];

    try {
      return await _api!.getRecentAlbums(limit: limit);
    } catch (e) {
      ErrorHandler.logError('Get recent albums', e);
      return [];
    }
  }

  /// Get random albums for discovery
  Future<List<Album>> getRandomAlbums({int limit = 10}) async {
    if (_api == null) return [];

    try {
      return await _api!.getRandomAlbums(limit: limit);
    } catch (e) {
      ErrorHandler.logError('Get random albums', e);
      return [];
    }
  }

  /// Toggle favorite status for a media item
  Future<void> toggleFavorite(String itemId, String mediaType, bool favorite) async {
    if (_api == null) return;

    try {
      await _api!.setFavorite(itemId, mediaType, favorite);
    } catch (e) {
      ErrorHandler.logError('Toggle favorite', e);
      rethrow;
    }
  }

  /// Get image URL for a media item
  String getImageUrl(dynamic item, {int? size}) {
    return _api?.getImageUrl(item, size: size) ?? '';
  }

  /// Get stream URL for a track
  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }
}
