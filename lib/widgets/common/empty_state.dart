import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

/// A reusable empty state widget for displaying when no data is available.
///
/// Shows an icon, message, and optional action button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 64,
  });

  /// Creates an empty state for artists
  factory EmptyState.artists({VoidCallback? onRefresh}) => EmptyState(
        icon: Icons.person_outline_rounded,
        message: 'No artists found',
        actionLabel: onRefresh != null ? 'Refresh' : null,
        onAction: onRefresh,
      );

  /// Creates an empty state for albums
  factory EmptyState.albums({VoidCallback? onRefresh}) => EmptyState(
        icon: Icons.album_outlined,
        message: 'No albums found',
        actionLabel: onRefresh != null ? 'Refresh' : null,
        onAction: onRefresh,
      );

  /// Creates an empty state for tracks
  factory EmptyState.tracks({VoidCallback? onRefresh}) => EmptyState(
        icon: Icons.music_note_outlined,
        message: 'No tracks found',
        actionLabel: onRefresh != null ? 'Refresh' : null,
        onAction: onRefresh,
      );

  /// Creates an empty state for playlists
  factory EmptyState.playlists({VoidCallback? onRefresh}) => EmptyState(
        icon: Icons.playlist_play_rounded,
        message: 'No playlists found',
        actionLabel: onRefresh != null ? 'Refresh' : null,
        onAction: onRefresh,
      );

  /// Creates an empty state for queue
  factory EmptyState.queue() => const EmptyState(
        icon: Icons.queue_music,
        message: 'Queue is empty',
      );

  /// Creates an empty state for search results
  factory EmptyState.search() => const EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No results found',
      );

  /// Creates a custom empty state with title and subtitle
  factory EmptyState.custom({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onRefresh,
  }) =>
      _CustomEmptyState(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onRefresh: onRefresh,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: Spacing.paddingAll24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: colorScheme.onSurface.withOpacity(0.38),
            ),
            Spacing.vGap16,
            Text(
              message,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              Spacing.vGap24,
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.surfaceVariant,
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A custom empty state with title and optional subtitle
class _CustomEmptyState extends EmptyState {
  final String title;
  final String? subtitle;
  final VoidCallback? onRefresh;

  const _CustomEmptyState({
    required super.icon,
    required this.title,
    this.subtitle,
    this.onRefresh,
  }) : super(message: title);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: Spacing.paddingAll24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: colorScheme.onSurface.withOpacity(0.38),
            ),
            Spacing.vGap16,
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              Spacing.vGap8,
              Text(
                subtitle!,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRefresh != null) ...[
              Spacing.vGap24,
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.surfaceVariant,
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
