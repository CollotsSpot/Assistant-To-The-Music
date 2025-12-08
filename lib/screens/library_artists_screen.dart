import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/empty_state.dart';
import 'artist_details_screen.dart';

class LibraryArtistsScreen extends StatelessWidget {
  const LibraryArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
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
          'Artists',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: Selector<MusicAssistantProvider, (List<Artist>, bool)>(
        selector: (_, provider) => (provider.artists, provider.isLoading),
        builder: (context, data, _) {
          final (artists, isLoading) = data;
          return _buildArtistsList(context, artists, isLoading);
        },
      ),
    );
  }

  Widget _buildArtistsList(BuildContext context, List<Artist> artists, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (artists.isEmpty) {
      return EmptyState.artists(
        onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await context.read<MusicAssistantProvider>().loadLibrary();
      },
      child: ListView.builder(
        key: const PageStorageKey<String>('library_artists_full_list'),
        cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
        itemCount: artists.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final artist = artists[index];
          return _buildArtistTile(
            context,
            artist,
            key: ValueKey(artist.uri ?? artist.itemId),
          );
        },
      ),
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    Artist artist, {
    Key? key,
  }) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.getImageUrl(artist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // RepaintBoundary isolates repaints to individual tiles
    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: CircleAvatar(
        radius: 24,
        backgroundColor: colorScheme.surfaceVariant,
        backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
        child: imageUrl == null
            ? Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        artist.name,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
        onTap: () {
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'library',
              ),
            ),
          );
        },
      ),
    );
  }
}
