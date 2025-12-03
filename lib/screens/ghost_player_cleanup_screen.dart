import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';

class GhostPlayerCleanupScreen extends StatefulWidget {
  const GhostPlayerCleanupScreen({super.key});

  @override
  State<GhostPlayerCleanupScreen> createState() => _GhostPlayerCleanupScreenState();
}

class _GhostPlayerCleanupScreenState extends State<GhostPlayerCleanupScreen> {
  final _logger = DebugLogger();
  List<Player> _allPlayers = [];
  String? _currentPlayerId;
  Set<String> _selectedForRemoval = {};
  bool _isLoading = true;
  bool _isRemoving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<MusicAssistantProvider>();
      _currentPlayerId = await SettingsService.getBuiltinPlayerId();
      _allPlayers = await provider.getAllPlayersUnfiltered();

      // Sort: current player first, then by name
      _allPlayers.sort((a, b) {
        if (a.playerId == _currentPlayerId) return -1;
        if (b.playerId == _currentPlayerId) return 1;
        return a.name.compareTo(b.name);
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.log('Error loading players: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load players: $e';
        });
      }
    }
  }

  PlayerCategory _categorizePlayer(Player player) {
    if (player.playerId == _currentPlayerId) {
      return PlayerCategory.current;
    }

    final id = player.playerId.toLowerCase();
    final isAppPlayer = id.startsWith('ensemble_') ||
                        id.startsWith('massiv_') ||
                        id.startsWith('ma_');

    if (!player.available) {
      return isAppPlayer ? PlayerCategory.ghostApp : PlayerCategory.ghostOther;
    }

    if (isAppPlayer) {
      return PlayerCategory.duplicateApp;
    }

    return PlayerCategory.normal;
  }

  Future<void> _removeSelectedPlayers() async {
    if (_selectedForRemoval.isEmpty) return;

    setState(() {
      _isRemoving = true;
    });

    final provider = context.read<MusicAssistantProvider>();
    int removed = 0;
    int failed = 0;

    for (final playerId in _selectedForRemoval) {
      try {
        _logger.log('Removing player: $playerId');
        await provider.api?.removePlayer(playerId);
        removed++;
      } catch (e) {
        _logger.log('Failed to remove $playerId: $e');
        failed++;
      }
    }

    if (mounted) {
      setState(() {
        _isRemoving = false;
        _selectedForRemoval.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Removed $removed player(s)'
                : 'Removed $removed, failed $failed',
          ),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
        ),
      );

      // Refresh the list
      await _loadPlayers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final ghostCount = _allPlayers.where((p) {
      final cat = _categorizePlayer(p);
      return cat == PlayerCategory.ghostApp ||
             cat == PlayerCategory.ghostOther ||
             cat == PlayerCategory.duplicateApp;
    }).length;

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
          'Ghost Players',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadPlayers,
            color: colorScheme.onBackground,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadPlayers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ghostCount > 0 ? Icons.warning_rounded : Icons.check_circle_rounded,
                            color: ghostCount > 0 ? Colors.orange : Colors.green,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ghostCount > 0
                                      ? '$ghostCount ghost player(s) found'
                                      : 'No ghost players',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Select players to remove from Music Assistant',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Legend
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildLegendItem(Colors.green, 'Current', colorScheme),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.red, 'Ghost', colorScheme),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.orange, 'Duplicate', colorScheme),
                          const SizedBox(width: 12),
                          _buildLegendItem(colorScheme.onSurfaceVariant, 'Other', colorScheme),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Player list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _allPlayers.length,
                        itemBuilder: (context, index) {
                          final player = _allPlayers[index];
                          final category = _categorizePlayer(player);
                          final isSelected = _selectedForRemoval.contains(player.playerId);
                          final canSelect = category != PlayerCategory.current;

                          return _buildPlayerCard(
                            player,
                            category,
                            isSelected,
                            canSelect,
                            colorScheme,
                            textTheme,
                          );
                        },
                      ),
                    ),

                    // Remove button
                    if (_selectedForRemoval.isNotEmpty)
                      SafeArea(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: _isRemoving ? null : _removeSelectedPlayers,
                              icon: _isRemoving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.delete_rounded),
                              label: Text(
                                _isRemoving
                                    ? 'Removing...'
                                    : 'Remove ${_selectedForRemoval.length} Player(s)',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildLegendItem(Color color, String label, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerCard(
    Player player,
    PlayerCategory category,
    bool isSelected,
    bool canSelect,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (category) {
      case PlayerCategory.current:
        statusColor = Colors.green;
        statusText = 'This device';
        statusIcon = Icons.phone_android_rounded;
        break;
      case PlayerCategory.ghostApp:
        statusColor = Colors.red;
        statusText = 'Ghost (unavailable)';
        statusIcon = Icons.error_rounded;
        break;
      case PlayerCategory.ghostOther:
        statusColor = Colors.red.shade300;
        statusText = 'Unavailable';
        statusIcon = Icons.cloud_off_rounded;
        break;
      case PlayerCategory.duplicateApp:
        statusColor = Colors.orange;
        statusText = 'Duplicate app player';
        statusIcon = Icons.content_copy_rounded;
        break;
      case PlayerCategory.normal:
        statusColor = colorScheme.onSurfaceVariant;
        statusText = player.state ?? 'idle';
        statusIcon = Icons.speaker_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? colorScheme.errorContainer.withOpacity(0.3)
          : colorScheme.surfaceVariant.withOpacity(0.3),
      child: InkWell(
        onTap: canSelect
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedForRemoval.remove(player.playerId);
                  } else {
                    _selectedForRemoval.add(player.playerId);
                  }
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Checkbox (disabled for current player)
              if (canSelect)
                Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedForRemoval.add(player.playerId);
                      } else {
                        _selectedForRemoval.remove(player.playerId);
                      }
                    });
                  },
                  activeColor: colorScheme.error,
                )
              else
                const SizedBox(width: 48), // Spacer for alignment

              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),

              const SizedBox(width: 12),

              // Player info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.playerId,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                          ),
                        ),
                        if (player.provider != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• ${player.provider}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum PlayerCategory {
  current,      // This device's player
  ghostApp,     // Unavailable app player (ensemble_*, massiv_*, ma_*)
  ghostOther,   // Unavailable non-app player
  duplicateApp, // Available app player that's not current (duplicate)
  normal,       // Regular player (not app-related)
}
