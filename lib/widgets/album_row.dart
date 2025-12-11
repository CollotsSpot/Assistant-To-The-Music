import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_card.dart';

class AlbumRow extends StatefulWidget {
  final String title;
  final Future<List<Album>> Function() loadAlbums;
  final String? heroTagSuffix;
  final double? rowHeight;

  const AlbumRow({
    super.key,
    required this.title,
    required this.loadAlbums,
    this.heroTagSuffix,
    this.rowHeight,
  });

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Album>> _albumsFuture;
  List<Album>? _cachedAlbums; // Keep last loaded data to prevent flash
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
      _albumsFuture = widget.loadAlbums().then((albums) {
        _cachedAlbums = albums;
        return albums;
      });
      _hasLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content
    final totalHeight = widget.rowHeight ?? 237.0; // Default: 44 title + 193 content
    const titleHeight = 44.0; // 12 top padding + ~24 text + 8 bottom padding
    final contentHeight = totalHeight - titleHeight;

    return RepaintBoundary(
      child: SizedBox(
        height: totalHeight,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: Text(
              widget.title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Album>>(
              future: _albumsFuture,
              builder: (context, snapshot) {
                // Use cached data immediately if available (prevents flash on rebuild)
                final albums = snapshot.data ?? _cachedAlbums;

                // Only show loading if we have no data at all
                if (albums == null && snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError && albums == null) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (albums == null || albums.isEmpty) {
                  return Center(
                    child: Text(
                      'No albums found',
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                    ),
                  );
                }

                // Card layout: square artwork + text below
                // Text area: 8px gap + ~18px title + ~18px artist = ~44px
                const textAreaHeight = 44.0;
                final artworkSize = contentHeight - textAreaHeight;
                final cardWidth = artworkSize; // Card width = artwork width (square)
                final itemExtent = cardWidth + 12; // width + horizontal margins

                return ScrollConfiguration(
                  behavior: const _StretchScrollBehavior(),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    itemCount: albums.length,
                    itemExtent: itemExtent,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return Container(
                        key: ValueKey(album.uri ?? album.itemId),
                        width: cardWidth,
                        margin: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: AlbumCard(
                          album: album,
                          heroTagSuffix: widget.heroTagSuffix,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          ],
        ),
      ),
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

