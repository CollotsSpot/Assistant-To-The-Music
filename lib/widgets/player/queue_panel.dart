import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_assistant_provider.dart';
import '../../models/player.dart';
import '../common/empty_state.dart';

/// Panel that displays the current playback queue
class QueuePanel extends StatelessWidget {
  final MusicAssistantProvider maProvider;
  final PlayerQueue? queue;
  final bool isLoading;
  final Color textColor;
  final Color primaryColor;
  final Color backgroundColor;
  final double topPadding;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  const QueuePanel({
    super.key,
    required this.maProvider,
    required this.queue,
    required this.isLoading,
    required this.textColor,
    required this.primaryColor,
    required this.backgroundColor,
    required this.topPadding,
    required this.onClose,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + 4, left: 4, right: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 24),
                  onPressed: onClose,
                  padding: const EdgeInsets.all(12),
                ),
                const Spacer(),
                Text(
                  'Queue',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: textColor.withOpacity(0.7), size: 22),
                  onPressed: onRefresh,
                  padding: const EdgeInsets.all(12),
                ),
              ],
            ),
          ),

          // Queue content
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : queue == null || queue!.items.isEmpty
                    ? _buildEmptyState()
                    : _buildQueueList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState.queue();
  }

  Widget _buildQueueList() {
    final currentIndex = queue!.currentIndex ?? 0;
    final items = queue!.items;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      cacheExtent: 500,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isCurrentItem = index == currentIndex;
        final isPastItem = index < currentIndex;
        final imageUrl = maProvider.api?.getImageUrl(item.track, size: 80);

        return Opacity(
          opacity: isPastItem ? 0.5 : 1.0,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isCurrentItem ? primaryColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: textColor.withOpacity(0.1),
                            child: Icon(Icons.music_note, color: textColor.withOpacity(0.3), size: 20),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: textColor.withOpacity(0.1),
                            child: Icon(Icons.music_note, color: textColor.withOpacity(0.3), size: 20),
                          ),
                        )
                      : Container(
                          color: textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: textColor.withOpacity(0.3), size: 20),
                        ),
                ),
              ),
              title: Text(
                item.track.name,
                style: TextStyle(
                  color: isCurrentItem ? primaryColor : textColor,
                  fontSize: 14,
                  fontWeight: isCurrentItem ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.track.artists != null && item.track.artists!.isNotEmpty
                  ? Text(
                      item.track.artists!.first.name,
                      style: TextStyle(
                        color: textColor.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: isCurrentItem
                  ? Icon(Icons.play_arrow_rounded, color: primaryColor, size: 20)
                  : null,
              onTap: () {
                // TODO: Jump to this track in queue
                // Music Assistant API doesn't currently expose a skip_to_index or play_queue_item endpoint
                // Would need to add API method like skipToQueueIndex(queueId, index) if MA supports it
                // Alternative: Could use multiple next() calls but that's inefficient and unreliable
              },
            ),
          ),
        );
      },
    );
  }
}
