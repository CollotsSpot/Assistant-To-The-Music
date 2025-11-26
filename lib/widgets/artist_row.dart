import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'artist_card.dart';

class ArtistRow extends StatefulWidget {
  final String title;
  final Future<List<Artist>> Function() loadArtists;
  final String? heroTagSuffix;

  const ArtistRow({
    super.key,
    required this.title,
    required this.loadArtists,
    this.heroTagSuffix,
  });

  @override
  State<ArtistRow> createState() => _ArtistRowState();
}

class _ArtistRowState extends State<ArtistRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Artist>> _artistsFuture;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadArtistsOnce();
  }

  void _loadArtistsOnce() {
    if (!_hasLoaded) {
      _artistsFuture = widget.loadArtists();
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
          height: 180,
          child: FutureBuilder<List<Artist>>(
            future: _artistsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              final artists = snapshot.data ?? [];
              if (artists.isEmpty) {
                return Center(
                  child: Text(
                    'No artists found',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                physics: const BouncingScrollPhysics(),
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ArtistCard(
                      artist: artist,
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
