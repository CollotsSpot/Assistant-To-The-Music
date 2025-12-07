import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import 'global_player_overlay.dart'; // For isPlayerExpanded and collapsePlayer

class PlayerSelector extends StatelessWidget {
  const PlayerSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;
    final availablePlayers = maProvider.availablePlayers;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _showPlayerSelector(context, maProvider, availablePlayers),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedPlayer != null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      selectedPlayer.name,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  MdiIcons.castAudio,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPlayerSelector(
    BuildContext context,
    MusicAssistantProvider provider,
    List players,
  ) {
    // Collapse player if expanded before showing sheet
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
    }

    // Slide mini player down out of the way
    GlobalPlayerOverlay.hidePlayer();

    // Show the bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) {
        return _PlayerSelectorSheet();
      },
    ).whenComplete(() {
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }
}

class _PlayerSelectorSheet extends StatefulWidget {
  @override
  State<_PlayerSelectorSheet> createState() => _PlayerSelectorSheetState();
}

class _PlayerSelectorSheetState extends State<_PlayerSelectorSheet> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Preload all player track info for display
    context.read<MusicAssistantProvider>().preloadAllPlayerTracks();

    // Auto-refresh at configured polling interval
    _refreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted) {
        final provider = context.read<MusicAssistantProvider>();
        provider.refreshPlayers();
        provider.preloadAllPlayerTracks();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final currentPlayers = maProvider.availablePlayers;
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final currentTrack = maProvider.currentTrack;

        final screenHeight = MediaQuery.of(context).size.height;
        final sheetHeight = screenHeight * 0.7; // Fixed 70% height

        return GestureDetector(
          onTap: () => Navigator.pop(context), // Tap outside to dismiss
          behavior: HitTestBehavior.opaque,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Prevent taps on sheet from dismissing
              child: Container(
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.speaker_group_rounded, color: colorScheme.onSurface),
                          const SizedBox(width: 12),
                          Text(
                            'Select Player',
                            style: textTheme.titleLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          // Show last refresh indicator
                          Icon(
                            Icons.sync,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: currentPlayers.isEmpty
                          ? Center(
                              child: Text(
                                'No players available',
                                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.54)),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(12, 8, 12, BottomSpacing.navBarOnly),
                              itemCount: currentPlayers.length,
                            itemBuilder: (context, index) {
                              final player = currentPlayers[index];
                              final isSelected = player.playerId == maProvider.selectedPlayer?.playerId;
                              final isOn = player.available && player.powered;
                              final isPlaying = player.state == 'playing';
                              final isPaused = player.state == 'paused';

                              // Get track info - use current track for selected player, cache for others
                              final playerTrack = isSelected
                                  ? currentTrack
                                  : maProvider.getCachedTrackForPlayer(player.playerId);

                              // Get album art for any playing/paused player
                              String? albumArtUrl;
                              if (playerTrack != null && isOn && (isPlaying || isPaused)) {
                                albumArtUrl = maProvider.getImageUrl(
                                  playerTrack.album ?? playerTrack,
                                  size: 128,
                                );
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () {
                                    maProvider.selectPlayer(player);
                                    Navigator.pop(context);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primary.withOpacity(0.15)
                                          : colorScheme.surfaceVariant.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        // Album art or player icon
                                        Padding(
                                          padding: const EdgeInsets.only(left: 12),
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceVariant,
                                              borderRadius: BorderRadius.circular(8),
                                              image: albumArtUrl != null
                                                  ? DecorationImage(
                                                      image: CachedNetworkImageProvider(albumArtUrl),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                            ),
                                            child: albumArtUrl == null
                                                ? Icon(
                                                    _getPlayerIcon(player.name),
                                                    color: player.available
                                                        ? (isSelected ? colorScheme.primary : colorScheme.onSurface)
                                                        : colorScheme.onSurface.withOpacity(0.38),
                                                    size: 24,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Player info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                player.name,
                                                style: TextStyle(
                                                  color: player.available
                                                      ? colorScheme.onSurface
                                                      : colorScheme.onSurface.withOpacity(0.38),
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  // Status indicator dot
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: !player.available
                                                          ? colorScheme.onSurface.withOpacity(0.24)
                                                          : !isOn
                                                              ? colorScheme.onSurface.withOpacity(0.3)
                                                              : isPlaying
                                                                  ? Colors.green
                                                                  : isPaused
                                                                      ? Colors.orange
                                                                      : colorScheme.onSurfaceVariant.withOpacity(0.5),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      !player.available
                                                          ? 'Unavailable'
                                                          : !isOn
                                                              ? 'Off'
                                                              : (isPlaying || isPaused) && playerTrack != null
                                                                  ? playerTrack.name
                                                                  : 'Idle',
                                                      style: TextStyle(
                                                        color: player.available
                                                            ? colorScheme.onSurfaceVariant
                                                            : colorScheme.onSurface.withOpacity(0.24),
                                                        fontSize: 13,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isSelected) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.primary.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        'Selected',
                                                        style: TextStyle(
                                                          color: colorScheme.primary,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Play/Pause button
                                        if (player.available && isOn)
                                          IconButton(
                                            icon: Icon(
                                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              color: colorScheme.onSurface,
                                              size: 28,
                                            ),
                                            onPressed: () {
                                              if (isPlaying) {
                                                maProvider.pausePlayer(player.playerId);
                                              } else {
                                                maProvider.resumePlayer(player.playerId);
                                              }
                                            },
                                          ),
                                        // Power button
                                        IconButton(
                                          icon: Icon(
                                            Icons.power_settings_new_rounded,
                                            size: 24,
                                            color: player.available
                                                ? (isOn ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.5))
                                                : colorScheme.onSurface.withOpacity(0.2),
                                          ),
                                          onPressed: player.available
                                              ? () => maProvider.togglePower(player.playerId)
                                              : null,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getPlayerIcon(String playerName) {
    final nameLower = playerName.toLowerCase();

    if (nameLower.contains('music assistant mobile') || nameLower.contains('builtin')) {
      return Icons.phone_android_rounded;
    } else if (nameLower.contains('group') || nameLower.contains('sync')) {
      return Icons.speaker_group_rounded;
    } else if (nameLower.contains('bedroom') || nameLower.contains('living') ||
        nameLower.contains('kitchen') || nameLower.contains('dining')) {
      return Icons.speaker_rounded;
    } else if (nameLower.contains('tv') || nameLower.contains('television')) {
      return Icons.tv_rounded;
    } else if (nameLower.contains('cast') || nameLower.contains('chromecast')) {
      return Icons.cast_rounded;
    } else {
      return Icons.speaker_rounded;
    }
  }
}
