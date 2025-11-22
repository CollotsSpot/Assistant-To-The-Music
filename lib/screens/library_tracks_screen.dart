import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/music_player_provider.dart';
import '../models/media_item.dart';
import '../models/audio_track.dart';

class LibraryTracksScreen extends StatelessWidget {
  const LibraryTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: const Text(
          'Tracks',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildTracksList(context, provider),
    );
  }

  Widget _buildTracksList(
      BuildContext context, MusicAssistantProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (provider.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_note_outlined,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            const Text(
              'No tracks found',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1a1a1a),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.tracks.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final track = provider.tracks[index];
        return _buildTrackTile(context, track, provider, index);
      },
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    Track track,
    MusicAssistantProvider maProvider,
    int index,
  ) {
    final imageUrl = track.album != null
        ? maProvider.getImageUrl(track.album!, size: 128)
        : null;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? const Icon(Icons.music_note_rounded, color: Colors.white54)
            : null,
      ),
      title: Text(
        track.name,
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistsString,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      onTap: () => _playTrack(context, maProvider, index),
    );
  }

  Future<void> _playTrack(
    BuildContext context,
    MusicAssistantProvider maProvider,
    int startIndex,
  ) async {
    final playerProvider = context.read<MusicPlayerProvider>();
    final tracks = maProvider.tracks;

    // Convert all tracks to AudioTrack objects
    final audioTracks = tracks.map((track) {
      final streamUrl = maProvider.getStreamUrl(
        track.provider,
        track.itemId,
        uri: track.uri,
        providerMappings: track.providerMappings,
      );
      return AudioTrack(
        id: track.itemId,
        title: track.name,
        artist: track.artistsString,
        album: track.album?.name ?? '',
        filePath: streamUrl,
        duration: track.duration,
      );
    }).toList();

    await playerProvider.setPlaylist(audioTracks, initialIndex: startIndex);
    await playerProvider.play();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
