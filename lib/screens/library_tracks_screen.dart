import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/common/empty_state.dart';

class LibraryTracksScreen extends StatelessWidget {
  const LibraryTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
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
          'Tracks',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
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
    final colorScheme = Theme.of(context).colorScheme;

    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (provider.tracks.isEmpty) {
      return EmptyState.tracks(onRefresh: provider.loadLibrary);
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
              ? DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.music_note_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        track.name,
        style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistsString,
        style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.54)),
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
    final tracks = maProvider.tracks;
    if (tracks.isEmpty) return;

    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    // Use Music Assistant to play tracks on the selected player
    await maProvider.playTracks(
      maProvider.selectedPlayer!.playerId,
      tracks,
      startIndex: startIndex,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
