import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';

class PlayerSelector extends StatelessWidget {
  const PlayerSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;
    final availablePlayers = maProvider.availablePlayers;

    return IconButton(
      icon: Stack(
        children: [
          const Icon(Icons.speaker_group_rounded),
          if (selectedPlayer != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1a1a1a), width: 1),
                ),
              ),
            ),
        ],
      ),
      tooltip: selectedPlayer?.name ?? 'Select Player',
      onPressed: () => _showPlayerSelector(context, maProvider, availablePlayers),
    );
  }

  void _showPlayerSelector(
    BuildContext context,
    MusicAssistantProvider provider,
    List players,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        // Use Consumer to listen for updates while sheet is open
        return Consumer<MusicAssistantProvider>(
          builder: (context, maProvider, child) {
            // Use the fresh list of players from the provider
            final currentPlayers = maProvider.availablePlayers;

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF2a2a2a),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Icon(Icons.speaker_group_rounded, color: Colors.white),
                            const SizedBox(width: 12),
                            const Text(
                              'Select Player',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                              onPressed: () async {
                                await maProvider.refreshPlayers();
                              },
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
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                                ),
                              )
                            : GridView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 1.6, // Shorter cards
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: currentPlayers.length,
                                itemBuilder: (context, index) {
                                  final player = currentPlayers[index];
                                  final isSelected =
                                      player.playerId == maProvider.selectedPlayer?.playerId;
                                  // isOn checks if the player is powered on
                                  final isOn = player.available && player.powered;
                                  
                                  final colorScheme = Theme.of(context).colorScheme;

                                  return InkWell(
                                    onTap: () {
                                      maProvider.selectPlayer(player);
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        // Tint whole card based on theme if selected
                                        color: isSelected
                                            ? colorScheme.primary.withOpacity(0.15)
                                            : colorScheme.surfaceVariant.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(16),
                                        // No border, just tint
                                      ),
                                      child: Stack(
                                        children: [
                                          // Power/Status Indicator (Functional)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: IconButton(
                                              icon: Icon(
                                                Icons.power_settings_new_rounded,
                                                size: 24,
                                                color: player.available 
                                                    ? (isOn ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.5)) 
                                                    : colorScheme.onSurface.withOpacity(0.1), 
                                              ),
                                              onPressed: player.available
                                                  ? () {
                                                      maProvider.togglePower(player.playerId);
                                                      // Don't close the sheet
                                                    }
                                                  : null,
                                            ),
                                          ),
                                          // Content
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Icon(
                                                  _getPlayerIcon(player.name),
                                                  color: player.available
                                                      ? (isSelected ? colorScheme.primary : colorScheme.onSurface)
                                                      : colorScheme.onSurface.withOpacity(0.38),
                                                  size: 28,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  player.name,
                                                  style: TextStyle(
                                                    color: player.available
                                                        ? colorScheme.onSurface
                                                        : colorScheme.onSurface.withOpacity(0.38),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  player.available
                                                      ? (player.state == 'playing'
                                                          ? 'Playing'
                                                          : (player.state == 'paused'
                                                              ? 'Paused'
                                                              : 'Idle'))
                                                      : 'Unavailable',
                                                  style: TextStyle(
                                                    color: player.available
                                                        ? colorScheme.onSurfaceVariant
                                                        : colorScheme.onSurface.withOpacity(0.24),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
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
