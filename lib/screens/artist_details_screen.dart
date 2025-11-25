import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;

  const ArtistDetailsScreen({super.key, required this.artist});

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> {
  List<Album> _albums = [];
  bool _isLoading = true;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  @override
  void initState() {
    super.initState();
    _loadArtistAlbums();
    _extractColors();
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.artist, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      print('⚠️ Failed to extract colors for artist: $e');
    }
  }

  Future<void> _loadArtistAlbums() async {
    final provider = context.read<MusicAssistantProvider>();

    // Load albums for this specific artist by filtering
    if (provider.api != null) {
      print('🎵 Loading albums for artist: ${widget.artist.name}');
      print('   Provider: ${widget.artist.provider}');
      print('   ItemId: ${widget.artist.itemId}');

      // Get all albums and filter by this artist
      final allAlbums = await provider.api!.getAlbums();

      // Filter albums that include this artist
      final artistAlbums = allAlbums.where((album) {
        if (album.artists == null) return false;
        return album.artists!.any((artist) =>
          artist.itemId == widget.artist.itemId &&
          artist.provider == widget.artist.provider
        );
      }).toList();

      print('   Got ${artistAlbums.length} albums for this artist (from ${allAlbums.length} total)');
      if (artistAlbums.isNotEmpty) {
        print('   First album: ${artistAlbums.first.name}');
      }

      setState(() {
        _albums = artistAlbums;
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
    final maProvider = context.watch<MusicAssistantProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final imageUrl = maProvider.getImageUrl(widget.artist, size: 512);

    // Determine if we should use adaptive theme colors
    final useAdaptiveTheme = themeProvider.adaptiveTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use
    ColorScheme? adaptiveScheme;
    if (useAdaptiveTheme) {
      adaptiveScheme = isDark ? _darkColorScheme : _lightColorScheme;
    }

    // Determine colors to use
    final backgroundColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.background
        : const Color(0xFF1a1a1a);

    final surfaceColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.surface
        : const Color(0xFF2a2a2a);

    final primaryColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primary
        : Colors.white;

    final textColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onSurface
        : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: backgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: textColor,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Hero(
                    tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId),
                    child: CircleAvatar(
                      radius: 100,
                      backgroundColor: Colors.white12,
                      backgroundImage:
                          imageUrl != null ? NetworkImage(imageUrl) : null,
                      child: imageUrl == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 100,
                              color: Colors.white54,
                            )
                          : null,
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
                    tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.artist.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Albums',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: primaryColor),
              ),
            )
          else if (_albums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No albums found',
                  style: TextStyle(
                    color: textColor.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
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
      ),
    );
  }

  Widget _buildAlbumCard(Album album, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(album, size: 256);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(album: album),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(12),
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? const Center(
                      child: Icon(
                        Icons.album_rounded,
                        size: 64,
                        color: Colors.white54,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.artistsString,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
