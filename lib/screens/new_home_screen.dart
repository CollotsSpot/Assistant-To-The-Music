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

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin {
  Key _refreshKey = UniqueKey();
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final showAlbums = await SettingsService.getShowFavoriteAlbums();
    final showArtists = await SettingsService.getShowFavoriteArtists();
    final showTracks = await SettingsService.getShowFavoriteTracks();
    if (mounted) {
      setState(() {
        _showFavoriteAlbums = showAlbums;
        _showFavoriteArtists = showArtists;
        _showFavoriteTracks = showTracks;
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
    // Use LayoutBuilder to adapt to available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height for the 3 main rows
        // Account for bottom nav + mini player space
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;

        // Total spacing between the 3 main rows
        const totalSpacing = 16.0; // Reduced from 24 (was 21 + 3)
        const titleHeight = 40.0; // Height for title text + padding per row
        const numRows = 3;

        // Calculate height available for row content (excluding titles and spacing)
        final contentHeight = availableHeight - totalSpacing - (titleHeight * numRows);

        // Distribute height proportionally:
        // Album rows get slightly more space (ratio 1.18:1:1.18 based on original 193:163:193)
        final totalRatio = 1.18 + 1.0 + 1.18; // 3.36
        final artistRowHeight = (contentHeight / totalRatio).clamp(120.0, 180.0);
        final albumRowHeight = (artistRowHeight * 1.18).clamp(140.0, 210.0);

        // Use Android 12+ stretch overscroll effect
        return ScrollConfiguration(
          behavior: const _StretchScrollBehavior(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            key: _refreshKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recently played albums (with caching)
              // Stable keys prevent widget recreation on parent rebuilds
              AlbumRow(
                key: const ValueKey('recent-albums'),
                title: 'Recently Played',
                loadAlbums: () => provider.getRecentAlbumsWithCache(),
                rowHeight: albumRowHeight,
              ),
              const SizedBox(height: 8),

              // Discover Artists (with caching)
              ArtistRow(
                key: const ValueKey('discover-artists'),
                title: 'Discover Artists',
                loadArtists: () => provider.getDiscoverArtistsWithCache(),
                rowHeight: artistRowHeight,
              ),
              const SizedBox(height: 8),

              // Discover Albums (with caching)
              AlbumRow(
                key: const ValueKey('discover-albums'),
                title: 'Discover Albums',
                loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
                rowHeight: albumRowHeight,
              ),

              // Optional favorites rows (fixed height, below scaled section)
              if (_showFavoriteAlbums) ...[
                const SizedBox(height: 16),
                AlbumRow(
                  key: const ValueKey('favorite-albums'),
                  title: 'Favorite Albums',
                  loadAlbums: () => provider.getFavoriteAlbums(),
                ),
              ],
              if (_showFavoriteArtists) ...[
                const SizedBox(height: 16),
                ArtistRow(
                  key: const ValueKey('favorite-artists'),
                  title: 'Favorite Artists',
                  loadArtists: () => provider.getFavoriteArtists(),
                ),
              ],
              if (_showFavoriteTracks) ...[
                const SizedBox(height: 16),
                TrackRow(
                  key: const ValueKey('favorite-tracks'),
                  title: 'Favorite Tracks',
                  loadTracks: () => provider.getFavoriteTracks(),
                ),
              ],

              // Only add bottom spacing if favorites are shown (they scroll below)
              // The main 3 rows are calculated to fit exactly without this
              if (_showFavoriteAlbums || _showFavoriteArtists || _showFavoriteTracks)
                SizedBox(height: BottomSpacing.withMiniPlayer),
            ],
            ),
          ),
        );
      },
    );
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
