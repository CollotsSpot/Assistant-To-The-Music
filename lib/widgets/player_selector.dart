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
      backgroundColor: const Color(0xFF2a2a2a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
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
                      await provider.refreshPlayers();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'No players available',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  final isSelected = player.playerId == provider.selectedPlayer?.playerId;

                  return ListTile(
                    leading: Icon(
                      _getPlayerIcon(player.name),
                      color: player.available ? Colors.white : Colors.white38,
                    ),
                    title: Text(
                      player.name,
                      style: TextStyle(
                        color: player.available ? Colors.white : Colors.white38,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      player.available
                          ? (player.isPlaying ? 'Playing' : 'Available')
                          : 'Unavailable',
                      style: TextStyle(
                        color: player.isPlaying
                            ? Colors.greenAccent
                            : (player.available ? Colors.white54 : Colors.white24),
                        fontSize: 12,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                        : null,
                    enabled: player.available,
                    onTap: () {
                      provider.selectPlayer(player);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
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
