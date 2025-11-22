import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/album_details_screen.dart';

class AlbumRow extends StatelessWidget {
  final String title;
  final Future<List<Album>> Function() loadAlbums;

  const AlbumRow({
    super.key,
    required this.title,
    required this.loadAlbums,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: FutureBuilder<List<Album>>(
            future: loadAlbums(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              final albums = snapshot.data ?? [];
              if (albums.isEmpty) {
                return const Center(
                  child: Text('No albums found'),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return _AlbumCard(album: album);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(album, size: 200);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(
              album: album,
              provider: album.provider,
              itemId: album.itemId,
            ),
          ),
        );
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 150,
                          height: 150,
                          color: Colors.grey[800],
                          child: const Icon(Icons.album, size: 64),
                        );
                      },
                    )
                  : Container(
                      width: 150,
                      height: 150,
                      color: Colors.grey[800],
                      child: const Icon(Icons.album, size: 64),
                    ),
            ),
            const SizedBox(height: 8),
            // Album title
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            // Artist name
            if (album.artists.isNotEmpty)
              Text(
                album.artists.first.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
