import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/music_player_provider.dart';
import '../models/audio_track.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
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
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF1a1a1a),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: Colors.white,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Container(
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
                  Text(
                    widget.album.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.album.artistsString,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play Album'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1a1a1a),
                        disabledBackgroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Tracks',
                    style: TextStyle(
                      color: Colors.white,
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
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_tracks.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                    color: Colors.white54,
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
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${track.position ?? index + 1}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      track.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistsString,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: track.duration != null
                        ? Text(
                            _formatDuration(track.duration!),
                            style: const TextStyle(
                              color: Colors.white54,
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
