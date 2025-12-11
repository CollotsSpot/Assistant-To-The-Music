import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
import '../widgets/track_row.dart';
import '../widgets/common/disconnected_state.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Key _refreshKey = UniqueKey();
  // Main rows (default on)
  bool _showRecentAlbums = true;
  bool _showDiscoverArtists = true;
  bool _showDiscoverAlbums = true;
  // Favorites rows (default off)
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;
  // Random order for favorites (generated once per session)
  late List<int> _favoritesOrder;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Generate random order for favorites rows (0, 1, 2 shuffled)
    _favoritesOrder = [0, 1, 2]..shuffle();
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload settings when app resumes (coming back from settings)
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final showRecent = await SettingsService.getShowRecentAlbums();
    final showDiscArtists = await SettingsService.getShowDiscoverArtists();
    final showDiscAlbums = await SettingsService.getShowDiscoverAlbums();
    final showFavAlbums = await SettingsService.getShowFavoriteAlbums();
    final showFavArtists = await SettingsService.getShowFavoriteArtists();
    final showFavTracks = await SettingsService.getShowFavoriteTracks();
    if (mounted) {
      setState(() {
        _showRecentAlbums = showRecent;
        _showDiscoverArtists = showDiscArtists;
        _showDiscoverAlbums = showDiscAlbums;
        _showFavoriteAlbums = showFavAlbums;
        _showFavoriteArtists = showFavArtists;
        _showFavoriteTracks = showFavTracks;
      });
    }
  }

  Future<void> _onRefresh() async {
    // Invalidate cache to force fresh data on pull-to-refresh
    final provider = context.read<MusicAssistantProvider>();
    provider.invalidateHomeCache();

    // Reload settings in case they changed
    await _loadSettings();

    if (mounted) {
      setState(() {
        _refreshKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Reload settings on each build to catch changes from Settings screen
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.light
                ? const ColorFilter.matrix(<double>[
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
            child: Image.asset(
              'assets/images/ensemble_logo.png',
              height: 40,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        titleSpacing: 0,
        centerTitle: false,
        actions: [
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: Selector<MusicAssistantProvider, bool>(
          selector: (_, p) => p.isConnected,
          builder: (context, isConnected, child) {
            final maProvider = context.read<MusicAssistantProvider>();
            return !isConnected
                ? DisconnectedState.full(
                    onSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surface,
                    child: _buildConnectedView(context, maProvider),
                  );
          },
        ),
      ),
    );
  }


  Widget _buildConnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    // Count enabled rows
    final totalEnabledRows = (_showRecentAlbums ? 1 : 0) +
                             (_showDiscoverArtists ? 1 : 0) +
                             (_showDiscoverAlbums ? 1 : 0) +
                             (_showFavoriteAlbums ? 1 : 0) +
                             (_showFavoriteArtists ? 1 : 0) +
                             (_showFavoriteTracks ? 1 : 0);

    // Use LayoutBuilder to adapt to available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Always calculate heights based on fitting exactly 3 rows (2 album + 1 artist)
        // This ensures consistent sizing regardless of how many rows are enabled
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;

        // Fixed layout: 3 rows with 2 spacings of 8px each, 3 titles
        const numRowsForCalc = 3;
        const totalSpacing = (numRowsForCalc - 1) * 8.0; // 16px total spacing
        const titleHeight = 44.0; // Height for title text + padding per row

        // Content height for 3 rows (2 album-type + 1 artist-type)
        final contentHeight = availableHeight - totalSpacing - (titleHeight * numRowsForCalc);

        // Distribute: 2 album rows + 1 artist row with ratio 1.18:1
        // totalRatio = (2 * 1.18) + (1 * 1.0) = 3.36
        const totalRatio = 3.36;
        final unitHeight = contentHeight / totalRatio;
        final artistRowHeight = unitHeight.clamp(120.0, 180.0);
        final albumRowHeight = (unitHeight * 1.18).clamp(140.0, 210.0);

        // Build favorites rows in random order with calculated heights
        final favoritesWidgets = _buildFavoritesRows(provider, albumRowHeight, artistRowHeight);

        // Use Android 12+ stretch overscroll effect
        return ScrollConfiguration(
          behavior: const _StretchScrollBehavior(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            key: _refreshKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recently played albums (optional)
              if (_showRecentAlbums) ...[
                AlbumRow(
                  key: const ValueKey('recent-albums'),
                  title: 'Recently Played',
                  loadAlbums: () => provider.getRecentAlbumsWithCache(),
                  rowHeight: albumRowHeight,
                ),
                if (_showDiscoverArtists || _showDiscoverAlbums) const SizedBox(height: 8),
              ],

              // Discover Artists (optional)
              if (_showDiscoverArtists) ...[
                ArtistRow(
                  key: const ValueKey('discover-artists'),
                  title: 'Discover Artists',
                  loadArtists: () => provider.getDiscoverArtistsWithCache(),
                  rowHeight: artistRowHeight,
                ),
                if (_showDiscoverAlbums) const SizedBox(height: 8),
              ],

              // Discover Albums (optional)
              if (_showDiscoverAlbums)
                AlbumRow(
                  key: const ValueKey('discover-albums'),
                  title: 'Discover Albums',
                  loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
                  rowHeight: albumRowHeight,
                ),

              // Favorites rows in random order (with same calculated heights)
              ...favoritesWidgets,
            ],
            ),
          ),
        );
      },
    );
  }

  /// Build favorites rows in random order (order set once per session)
  List<Widget> _buildFavoritesRows(MusicAssistantProvider provider, double albumRowHeight, double artistRowHeight) {
    final widgets = <Widget>[];

    // Create list of enabled favorites with their order index
    final enabledFavorites = <MapEntry<int, Widget>>[];

    if (_showFavoriteAlbums) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[0],
        AlbumRow(
          key: const ValueKey('favorite-albums'),
          title: 'Favorite Albums',
          loadAlbums: () => provider.getFavoriteAlbums(),
          rowHeight: albumRowHeight,
        ),
      ));
    }

    if (_showFavoriteArtists) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[1],
        ArtistRow(
          key: const ValueKey('favorite-artists'),
          title: 'Favorite Artists',
          loadArtists: () => provider.getFavoriteArtists(),
          rowHeight: artistRowHeight,
        ),
      ));
    }

    if (_showFavoriteTracks) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[2],
        TrackRow(
          key: const ValueKey('favorite-tracks'),
          title: 'Favorite Tracks',
          loadTracks: () => provider.getFavoriteTracks(),
          rowHeight: albumRowHeight, // Track row uses album-like sizing
        ),
      ));
    }

    // Sort by the random order index
    enabledFavorites.sort((a, b) => a.key.compareTo(b.key));

    // Add widgets with spacing (no spacer before first row)
    for (var i = 0; i < enabledFavorites.length; i++) {
      if (i > 0) {
        widgets.add(const SizedBox(height: 8));
      }
      widgets.add(enabledFavorites[i].value);
    }

    return widgets;
  }
}

/// Custom scroll behavior that uses Android 12+ stretch overscroll effect
class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
