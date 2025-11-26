import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_card.dart';

class AlbumRow extends StatefulWidget {
  final String title;
  final Future<List<Album>> Function() loadAlbums;
  final String? heroTagSuffix;

  const AlbumRow({
    super.key,
    required this.title,
    required this.loadAlbums,
    this.heroTagSuffix,
  });

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Album>> _albumsFuture;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAlbumsOnce();
  }

  void _loadAlbumsOnce() {
    if (!_hasLoaded) {
      _albumsFuture = widget.loadAlbums();
      _hasLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            widget.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onBackground,
            ),
          ),
        ),
        SizedBox(
          height: 210, // Slightly increased for text
          child: FutureBuilder<List<Album>>(
            future: _albumsFuture,
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
                return Center(
                  child: Text(
                    'No albums found',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                physics: const BouncingScrollPhysics(),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return Container(
                    width: 150,
                    margin: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: AlbumCard(
                      album: album,
                      heroTagSuffix: widget.heroTagSuffix,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

