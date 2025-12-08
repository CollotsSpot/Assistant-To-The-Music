import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/common/empty_state.dart';
import 'playlist_details_screen.dart';

class LibraryPlaylistsScreen extends StatefulWidget {
  const LibraryPlaylistsScreen({super.key});

  @override
  State<LibraryPlaylistsScreen> createState() => _LibraryPlaylistsScreenState();
}

class _LibraryPlaylistsScreenState extends State<LibraryPlaylistsScreen> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final playlists = await maProvider.api!.getPlaylists(limit: 100);
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: colorScheme.onBackground,
        ),
        title: Text(
          'Playlists',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildPlaylistsList(context, provider),
    );
  }

  Widget _buildPlaylistsList(BuildContext context, MusicAssistantProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (_playlists.isEmpty) {
      return EmptyState.playlists(onRefresh: _loadPlaylists);
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: _loadPlaylists,
      child: ListView.builder(
        itemCount: _playlists.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          return _buildPlaylistTile(context, playlist, provider);
        },
      ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, Playlist playlist, MusicAssistantProvider provider) {
    final imageUrl = provider.api?.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Builder(
      builder: (context) => ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            image: imageUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(imageUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imageUrl == null
              ? Icon(Icons.playlist_play_rounded, color: colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Text(
          playlist.name,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          playlist.trackCount != null
              ? '${playlist.trackCount} tracks'
              : playlist.owner ?? 'Playlist',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: playlist.favorite == true
            ? const Icon(Icons.favorite, color: Colors.red, size: 20)
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistDetailsScreen(
                playlist: playlist,
                provider: playlist.provider,
                itemId: playlist.itemId,
              ),
            ),
          );
        },
      ),
    );
  }
}
