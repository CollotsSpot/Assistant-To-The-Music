import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.album.favorite ?? false;
    _loadTracks();
    _extractColors();
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

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
      print('⚠️ Failed to extract colors for album: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    try {
      final newState = await maProvider.api!.toggleFavorite(
        'album',
        widget.album.itemId,
        widget.album.provider,
      );

      setState(() {
        _isFavorite = newState;
      });

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
      print('Error toggling favorite: $e');
    }
  }

  Future<void> _loadTracks() async {
    final provider = context.read<MusicAssistantProvider>();
    final tracks = await provider.getAlbumTracks(
      widget.album.provider,
      widget.album.itemId,
    );

    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  Future<void> _playAlbum() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      print('🎵 Queueing album on ${player.name}: ${player.playerId}');

      // Queue all tracks via Music Assistant
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      print('✓ Album queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error playing album: $e');
      _showError('Failed to play album: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      print('🎵 Queueing tracks on ${player.name} starting at index $index');

      // Queue tracks starting at the selected index
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      print('✓ Tracks queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

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
                    tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        image: imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: imageUrl == null
                          ? const Icon(
                              Icons.album_rounded,
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
                    tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Hero(
                    tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.artistsString,
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play Album'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: backgroundColor,
                              disabledBackgroundColor: primaryColor.withOpacity(0.38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          color: _isFavorite ? Colors.red : Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _toggleFavorite,
                          icon: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: _isFavorite ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tracks',
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
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                    color: textColor.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${track.position ?? index + 1}',
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      track.name,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistsString,
                      style: TextStyle(
                        color: textColor.withOpacity(0.54),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: track.duration != null
                        ? Text(
                            _formatDuration(track.duration!),
                            style: TextStyle(
                              color: textColor.withOpacity(0.54),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    onTap: () => _playTrack(index),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
