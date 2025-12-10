import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;
  final String? heroTagSuffix;

  const ArtistDetailsScreen({
    super.key, 
    required this.artist,
    this.heroTagSuffix,
  });

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> {
  final _logger = DebugLogger();
  List<Album> _albums = [];
  List<Album> _providerAlbums = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _artistDescription;
  String? _artistImageUrl;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.artist.favorite ?? false;
    _loadArtistAlbums();
    _loadArtistImage();
    _loadArtistDescription();
    _refreshFavoriteStatus();
  }

  Future<void> _refreshFavoriteStatus() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    final artistUri = widget.artist.uri;
    if (artistUri == null || artistUri.isEmpty) {
      _logger.log('Cannot refresh favorite status: artist has no URI');
      return;
    }

    try {
      final freshArtist = await maProvider.api!.getArtistByUri(artistUri);
      if (freshArtist != null && mounted) {
        setState(() {
          _isFavorite = freshArtist.favorite ?? false;
        });
      }
    } catch (e) {
      _logger.log('Error refreshing artist favorite status: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    try {
      final newState = !_isFavorite;

      if (newState) {
        String actualProvider = widget.artist.provider;
        String actualItemId = widget.artist.itemId;

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          final mapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.artist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.artist.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding artist to favorites: provider=$actualProvider, itemId=$actualItemId');
        await maProvider.api!.addToFavorites('artist', actualItemId, actualProvider);
      } else {
        int? libraryItemId;

        if (widget.artist.provider == 'library') {
          libraryItemId = int.tryParse(widget.artist.itemId);
        } else if (widget.artist.providerMappings != null) {
          final libraryMapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.artist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          throw Exception('Could not determine library ID for this artist');
        }

        _logger.log('Removing artist from favorites: libraryItemId=$libraryItemId');
        await maProvider.api!.removeFromFavorites('artist', libraryItemId);
      }

      setState(() {
        _isFavorite = newState;
      });

      maProvider.invalidateHomeCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFavorite ? 'Added to favorites' : 'Removed from favorites',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error toggling artist favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favorite: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _startArtistRadio() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    try {
      await maProvider.playArtistRadio(selectedPlayer.playerId, widget.artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Starting ${widget.artist.name} radio'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error starting artist radio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start radio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.players.where((p) => p.available).toList();
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start ${widget.artist.name} radio on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await maProvider.playArtistRadio(player.playerId, widget.artist);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Starting ${widget.artist.name} radio on ${player.name}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error starting artist radio on player: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to start radio: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _addArtistRadioToQueue() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    try {
      // For adding to queue with radio mode, we use radio_mode but with 'add' option
      await maProvider.api?.playArtistRadioToQueue(selectedPlayer.playerId, widget.artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${widget.artist.name} radio to queue'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error adding artist radio to queue: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add to queue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadArtistImage() async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Get image URL with fallback to Deezer/Fanart.tv
    final imageUrl = await maProvider.getArtistImageUrlWithFallback(widget.artist, size: 512);

    if (mounted && imageUrl != null) {
      setState(() {
        _artistImageUrl = imageUrl;
      });
      // Extract colors after we have the image
      _extractColors(imageUrl);
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      _logger.log('Failed to extract colors for artist: $e');
    }
  }

  Future<void> _loadArtistDescription() async {
    final artistName = widget.artist.name;

    if (artistName.isEmpty) return;

    final description = await MetadataService.getArtistDescription(
      artistName,
      widget.artist.metadata,
    );

    if (mounted) {
      setState(() {
        _artistDescription = description;
      });
    }
  }

  Future<void> _loadArtistAlbums() async {
    final provider = context.read<MusicAssistantProvider>();

    // Use cached artist albums method
    final allAlbums = await provider.getArtistAlbumsWithCache(widget.artist.name);

    if (mounted) {
      setState(() {
        _albums = allAlbums;
        _providerAlbums = []; // All albums are merged in the cache method
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    // Use the loaded image URL (with fallback) instead of directly from MA
    final imageUrl = _artistImageUrl;

    final useAdaptiveTheme = themeProvider.adaptiveTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ColorScheme? adaptiveScheme;
    if (useAdaptiveTheme) {
      adaptiveScheme = isDark ? _darkColorScheme : _lightColorScheme;
    }
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          clearAdaptiveColorsOnBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: colorScheme.background,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  clearAdaptiveColorsOnBack(context);
                  Navigator.pop(context);
                },
                color: colorScheme.onBackground,
              ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Hero(
                    tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
                    child: ClipOval(
                      child: Container(
                        width: 200,
                        height: 200,
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_rounded,
                                  size: 100,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: 100,
                                color: colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.artist.name,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_artistDescription != null && _artistDescription!.isNotEmpty) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _artistDescription!,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onBackground.withOpacity(0.8),
                          ),
                          maxLines: _isDescriptionExpanded ? null : 2,
                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Action Buttons Row
                  Row(
                    children: [
                      // Main Radio Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _startArtistRadio,
                            icon: const Icon(Icons.radio),
                            label: const Text('Radio'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // "Play on..." Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: () => _showPlayOnMenu(context),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.speaker_group_outlined),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // "Add to Queue" Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _addArtistRadioToQueue,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.playlist_add),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Favorite Button
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _toggleFavorite,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: _isFavorite
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (_albums.isEmpty && _providerAlbums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No albums found',
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else ...[
            // Library Albums Section
            if (_albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Text(
                    'In Library',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final album = _albums[index];
                      return _buildAlbumCard(album, maProvider);
                    },
                    childCount: _albums.length,
                  ),
                ),
              ),
            ],

            // Provider Albums Section
            if (_providerAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 12.0),
                  child: Text(
                    'From Providers',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final album = _providerAlbums[index];
                      return _buildAlbumCard(album, maProvider);
                    },
                    childCount: _providerAlbums.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 140)), // Space for bottom nav + mini player
            ],
          ],
        ],
        ),
      ),
    );
  }

  Widget _buildAlbumCard(Album album, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const String heroSuffix = 'artist_albums';

    return InkWell(
      onTap: () {
        // Update adaptive colors immediately on tap
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AlbumDetailsScreen(
              album: album,
              heroTagSuffix: heroSuffix,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: HeroTags.albumCover + (album.uri ?? album.itemId) + '_$heroSuffix',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: colorScheme.surfaceVariant,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.album_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.album_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.albumTitle + (album.uri ?? album.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.name,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Hero(
            tag: HeroTags.artistName + (album.uri ?? album.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.artistsString,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
