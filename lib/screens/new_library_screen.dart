import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_card.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../widgets/common/empty_state.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';

class NewLibraryScreen extends StatefulWidget {
  const NewLibraryScreen({super.key});

  @override
  State<NewLibraryScreen> createState() => _NewLibraryScreenState();
}

class _NewLibraryScreenState extends State<NewLibraryScreen>
    with SingleTickerProviderStateMixin, RestorationMixin {
  late TabController _tabController;
  List<Playlist> _playlists = [];
  bool _isLoadingPlaylists = true;

  // Restoration: Remember selected tab across app restarts
  final RestorableInt _selectedTabIndex = RestorableInt(0);

  @override
  String? get restorationId => 'new_library_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedTabIndex, 'selected_tab_index');
    // Apply restored tab index after TabController is created
    if (_tabController.index != _selectedTabIndex.value) {
      _tabController.index = _selectedTabIndex.value;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Listen to tab changes to persist selection
    _tabController.addListener(_onTabChanged);
    _loadPlaylists();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _selectedTabIndex.value = _tabController.index;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _selectedTabIndex.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final playlists = await maProvider.api!.getPlaylists(limit: 100);
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _isLoadingPlaylists = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when connection state changes
    return Selector<MusicAssistantProvider, bool>(
      selector: (_, provider) => provider.isConnected,
      builder: (context, isConnected, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        if (!isConnected) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(
                'Library',
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w300,
                ),
              ),
              centerTitle: true,
              actions: const [PlayerSelector()],
            ),
            body: _buildDisconnectedView(context),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Library',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.w300,
              ),
            ),
            centerTitle: true,
            actions: const [PlayerSelector()],
            bottom: TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
              tabs: const [
                Tab(text: 'Artists'),
                Tab(text: 'Albums'),
                Tab(text: 'Playlists'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildArtistsTab(context),
              _buildAlbumsTab(context),
              _buildPlaylistsTab(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisconnectedView(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            const SizedBox(height: 16),
            Text(
              'Not connected to Music Assistant',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Configure Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ ARTISTS TAB ============
  Widget _buildArtistsTab(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
    return Selector<MusicAssistantProvider, (List<Artist>, bool)>(
      selector: (_, provider) => (provider.artists, provider.isLoading),
      builder: (context, data, _) {
        final (artists, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        if (artists.isEmpty) {
          return EmptyState.artists(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: ListView.builder(
            key: const PageStorageKey<String>('library_artists_list'),
            cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
            itemCount: artists.length,
            padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
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
      },
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
    final suffix = '_library';

    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: Hero(
        tag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
        child: CircleAvatar(
          radius: 24,
          backgroundColor: colorScheme.surfaceVariant,
          backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
          child: imageUrl == null
              ? Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant)
              : null,
        ),
      ),
      title: Hero(
        tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
        child: Material(
          color: Colors.transparent,
          child: Text(
            artist.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
        onTap: () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
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

  // ============ ALBUMS TAB ============
  Widget _buildAlbumsTab(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when albums or loading state changes
    return Selector<MusicAssistantProvider, (List<Album>, bool)>(
      selector: (_, provider) => (provider.albums, provider.isLoading),
      builder: (context, data, _) {
        final (albums, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        if (albums.isEmpty) {
          return EmptyState.albums(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: GridView.builder(
            key: const PageStorageKey<String>('library_albums_grid'),
            cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return AlbumCard(
                key: ValueKey(album.uri ?? album.itemId),
                album: album,
                heroTagSuffix: 'library_grid',
              );
            },
          ),
        );
      },
    );
  }

  // ============ PLAYLISTS TAB ============
  Widget _buildPlaylistsTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingPlaylists) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_playlists.isEmpty) {
      return EmptyState.playlists(onRefresh: _loadPlaylists);
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: _loadPlaylists,
      child: ListView.builder(
        key: const PageStorageKey<String>('library_playlists_list'),
        cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
        itemCount: _playlists.length,
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          return _buildPlaylistTile(context, playlist);
        },
      ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, Playlist playlist) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(image: CachedNetworkImageProvider(imageUrl), fit: BoxFit.cover)
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
        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
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
    );
  }

}
