import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/album_card.dart';
import '../widgets/common/empty_state.dart';

class LibraryAlbumsScreen extends StatelessWidget {
  const LibraryAlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when albums or loading state changes
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
          'Albums',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: Selector<MusicAssistantProvider, (List<Album>, bool)>(
        selector: (_, provider) => (provider.albums, provider.isLoading),
        builder: (context, data, _) {
          final (albums, isLoading) = data;
          return _buildAlbumsList(context, albums, isLoading);
        },
      ),
    );
  }

  Widget _buildAlbumsList(BuildContext context, List<Album> albums, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (albums.isEmpty) {
      return EmptyState.albums(
        onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await context.read<MusicAssistantProvider>().loadLibrary();
      },
      child: GridView.builder(
        key: const PageStorageKey<String>('library_albums_full_grid'),
        cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        padding: const EdgeInsets.all(12),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return AlbumCard(
            key: ValueKey(album.uri ?? album.itemId),
            album: album,
            heroTagSuffix: 'library',
          );
        },
      ),
    );
  }
}

