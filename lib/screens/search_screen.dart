import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/music_player_provider.dart';
import '../models/media_item.dart';
import '../models/audio_track.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Map<String, List<MediaItem>> _searchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = {'artists': [], 'albums': [], 'tracks': []};
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final provider = context.read<MusicAssistantProvider>();
    final results = await provider.search(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2a2a2a),
        elevation: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search music...',
            hintStyle: const TextStyle(color: Colors.white54),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {});
            _performSearch(value);
          },
          onSubmitted: _performSearch,
        ),
      ),
      body: !maProvider.isConnected
          ? _buildDisconnectedView()
          : _buildSearchContent(),
    );
  }

  Widget _buildDisconnectedView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Colors.white54,
            ),
            SizedBox(height: 16),
            Text(
              'Not connected to Music Assistant',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for artists, albums, or tracks',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final artists = _searchResults['artists'] as List<MediaItem>? ?? [];
    final albums = _searchResults['albums'] as List<MediaItem>? ?? [];
    final tracks = _searchResults['tracks'] as List<MediaItem>? ?? [];

    final hasResults = artists.isNotEmpty || albums.isNotEmpty || tracks.isNotEmpty;

    if (!hasResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (artists.isNotEmpty) ...[
          _buildSectionHeader('Artists', artists.length),
          const SizedBox(height: 8),
          ...artists.map((item) => _buildArtistTile(item as Artist)),
          const SizedBox(height: 24),
        ],
        if (albums.isNotEmpty) ...[
          _buildSectionHeader('Albums', albums.length),
          const SizedBox(height: 8),
          ...albums.map((item) => _buildAlbumTile(item as Album)),
          const SizedBox(height: 24),
        ],
        if (tracks.isNotEmpty) ...[
          _buildSectionHeader('Tracks', tracks.length),
          const SizedBox(height: 8),
          ...tracks.map((item) => _buildTrackTile(item as Track)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        '$title ($count)',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildArtistTile(Artist artist) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 128);

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.white12,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? const Icon(Icons.person_rounded, color: Colors.white54)
            : null,
      ),
      title: Text(
        artist.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text(
        'Artist',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailsScreen(artist: artist),
          ),
        );
      },
    );
  }

  Widget _buildAlbumTile(Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? const Icon(Icons.album_rounded, color: Colors.white54)
            : null,
      ),
      title: Text(
        album.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artistsString,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(album: album),
          ),
        );
      },
    );
  }

  Widget _buildTrackTile(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = track.album != null
        ? maProvider.getImageUrl(track.album!, size: 128)
        : null;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? const Icon(Icons.music_note_rounded, color: Colors.white54)
            : null,
      ),
      title: Text(
        track.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistsString,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      onTap: () => _playTrack(track),
    );
  }

  Future<void> _playTrack(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final playerProvider = context.read<MusicPlayerProvider>();

    final streamUrl = maProvider.getStreamUrl(
      track.provider,
      track.itemId,
      uri: track.uri,
      providerMappings: track.providerMappings,
    );
    final audioTrack = AudioTrack(
      id: track.itemId,
      title: track.name,
      artist: track.artistsString,
      album: track.album?.name ?? '',
      filePath: streamUrl,
      duration: track.duration,
    );

    await playerProvider.setPlaylist([audioTrack]);
    await playerProvider.play();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
