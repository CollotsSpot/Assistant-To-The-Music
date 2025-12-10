import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_avatar.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
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
  List<Track> _favoriteTracks = [];
  bool _isLoadingPlaylists = true;
  bool _isLoadingTracks = false;
  bool _showFavoritesOnly = false;

  // Restoration: Remember selected tab across app restarts
  final RestorableInt _selectedTabIndex = RestorableInt(0);

  int get _tabCount => _showFavoritesOnly ? 4 : 3;

  @override
  String? get restorationId => 'new_library_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedTabIndex, 'selected_tab_index');
    // Apply restored tab index after TabController is created
    if (_tabController.index != _selectedTabIndex.value &&
        _selectedTabIndex.value < _tabController.length) {
      _tabController.index = _selectedTabIndex.value;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    // Listen to tab changes to persist selection
    _tabController.addListener(_onTabChanged);
    _loadPlaylists();
  }

  void _recreateTabController() {
    final oldIndex = _tabController.index;
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Restore to previous index if valid, otherwise default to 0
    if (oldIndex < _tabCount) {
      _tabController.index = oldIndex;
    }
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

  Future<void> _loadPlaylists({bool? favoriteOnly}) async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final playlists = await maProvider.api!.getPlaylists(
        limit: 100,
        favoriteOnly: favoriteOnly,
      );
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

  Future<void> _loadFavoriteTracks() async {
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: 500,
        favoriteOnly: true,
      );
      if (mounted) {
        setState(() {
          _favoriteTracks = tracks;
          _isLoadingTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  void _toggleFavoritesMode(bool value) {
    setState(() {
      _showFavoritesOnly = value;
      _recreateTabController();
    });
    if (value) {
      _loadPlaylists(favoriteOnly: true);
      _loadFavoriteTracks();
    } else {
      _loadPlaylists();
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
            body: DisconnectedState.withSettingsAction(
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                // Favorites toggle with label
                GestureDetector(
                  onTap: () => _toggleFavoritesMode(!_showFavoritesOnly),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _showFavoritesOnly,
                        onChanged: _toggleFavoritesMode,
                        activeColor: colorScheme.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Favourites',
                        style: textTheme.titleMedium?.copyWith(
                          color: _showFavoritesOnly
                              ? colorScheme.primary
                              : colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: _showFavoritesOnly ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            centerTitle: false,
            actions: const [
              PlayerSelector(),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
              tabs: [
                const Tab(text: 'Artists'),
                const Tab(text: 'Albums'),
                if (_showFavoritesOnly) const Tab(text: 'Tracks'),
                const Tab(text: 'Playlists'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildArtistsTab(context),
              _buildAlbumsTab(context),
              if (_showFavoritesOnly) _buildTracksTab(context),
              _buildPlaylistsTab(context),
            ],
          ),
        );
      },
    );
  }

  // ============ ARTISTS TAB ============
  Widget _buildArtistsTab(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
    return Selector<MusicAssistantProvider, (List<Artist>, bool)>(
      selector: (_, provider) => (provider.artists, provider.isLoading),
      builder: (context, data, _) {
        final (allArtists, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final artists = _showFavoritesOnly
            ? allArtists.where((a) => a.favorite == true).toList()
            : allArtists;

        if (artists.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              icon: Icons.favorite_border,
              title: 'No favorite artists',
              subtitle: 'Tap the heart on an artist to add them to favorites',
            );
          }
          return EmptyState.artists(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: ListView.builder(
            key: PageStorageKey<String>('library_artists_list_${_showFavoritesOnly ? 'fav' : 'all'}'),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final suffix = '_library';

    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: ArtistAvatar(
          artist: artist,
          radius: 24,
          imageSize: 128,
          heroTag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
          onImageLoaded: (imageUrl) {
            // Store for adaptive colors on tap
          },
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
        final (allAlbums, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final albums = _showFavoritesOnly
            ? allAlbums.where((a) => a.favorite == true).toList()
            : allAlbums;

        if (albums.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              icon: Icons.favorite_border,
              title: 'No favorite albums',
              subtitle: 'Tap the heart on an album to add it to favorites',
            );
          }
          return EmptyState.albums(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: GridView.builder(
            key: PageStorageKey<String>('library_albums_grid_${_showFavoritesOnly ? 'fav' : 'all'}'),
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
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          icon: Icons.favorite_border,
          title: 'No favorite playlists',
          subtitle: 'Tap the heart on a playlist to add it to favorites',
        );
      }
      return EmptyState.playlists(onRefresh: () => _loadPlaylists());
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadPlaylists(favoriteOnly: _showFavoritesOnly ? true : null),
      child: ListView.builder(
        key: PageStorageKey<String>('library_playlists_list_${_showFavoritesOnly ? 'fav' : 'all'}'),
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

  // ============ TRACKS TAB (favorites only) ============
  Widget _buildTracksTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();

    if (_isLoadingTracks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_favoriteTracks.isEmpty) {
      return EmptyState.custom(
        icon: Icons.favorite_border,
        title: 'No favorite tracks',
        subtitle: 'Long-press a track and tap the heart to add it to favorites',
      );
    }

    // Group tracks by artist, then by album
    final tracksByArtistAlbum = <String, Map<String, List<Track>>>{};
    for (final track in _favoriteTracks) {
      final artistKey = track.artistsString.isNotEmpty ? track.artistsString : 'Unknown Artist';
      final albumKey = track.album?.name ?? 'Unknown Album';
      tracksByArtistAlbum.putIfAbsent(artistKey, () => {});
      tracksByArtistAlbum[artistKey]!.putIfAbsent(albumKey, () => []).add(track);
    }

    // Sort artists alphabetically
    final sortedArtists = tracksByArtistAlbum.keys.toList()..sort();

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: _loadFavoriteTracks,
      child: ListView.builder(
        key: const PageStorageKey<String>('library_tracks_list'),
        cacheExtent: 500,
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
        itemCount: sortedArtists.length,
        itemBuilder: (context, index) {
          final artistName = sortedArtists[index];
          final albumsMap = tracksByArtistAlbum[artistName]!;
          final sortedAlbums = albumsMap.keys.toList()..sort();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artist header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  artistName,
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Albums under this artist
              ...sortedAlbums.map((albumName) {
                final tracks = albumsMap[albumName]!;
                final firstTrack = tracks.first;
                final albumImageUrl = firstTrack.album != null
                    ? maProvider.api?.getImageUrl(firstTrack.album!, size: 128)
                    : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Album header with art
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          // Album art
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                              image: albumImageUrl != null
                                  ? DecorationImage(
                                      image: CachedNetworkImageProvider(albumImageUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: albumImageUrl == null
                                ? Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 24)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          // Album name
                          Expanded(
                            child: Text(
                              albumName,
                              style: textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tracks under this album
                    ...tracks.map((track) => _buildTrackTile(context, track)),
                  ],
                );
              }),
              const Divider(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackTile(BuildContext context, Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 76, right: 16),
      dense: true,
      title: Text(
        track.name,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.favorite,
        color: Colors.red,
        size: 18,
      ),
      onTap: () async {
        final player = maProvider.selectedPlayer;
        if (player == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No player selected')),
          );
          return;
        }

        try {
          // Start radio from this track
          await maProvider.api?.playRadio(player.playerId, track);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start radio: $e')),
            );
          }
        }
      },
    );
  }
}
