import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../widgets/volume_control.dart';
import 'queue_screen.dart';
import '../constants/hero_tags.dart';
import '../widgets/animated_icon_button.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  PlayerQueue? _queue;
  bool _isLoadingQueue = true;
  Timer? _progressTimer;
  double? _seekPosition; // Track seek position while dragging
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl; // Track last image URL to avoid re-extracting

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _startProgressTimer();
  }

  Future<void> _extractColors(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return; // Skip if same image
    _lastImageUrl = imageUrl;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      print('⚠️ Failed to extract colors for now playing: $e');
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startProgressTimer() {
    // Update UI every second when playing to show progress
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // Just trigger rebuild to update elapsed time
        });
      }
    });
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoadingQueue = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player != null && maProvider.api != null) {
      final queue = await maProvider.api!.getQueue(player.playerId);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoadingQueue = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingQueue = false;
        });
      }
    }
  }

  Future<void> _toggleShuffle() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.toggleShuffle(_queue!.playerId);
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.cycleRepeatMode(_queue!.playerId, _queue!.repeatMode);
    await _loadQueue();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        if (currentTrack == null || selectedPlayer == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text(
                'No track playing',
                style: TextStyle(color: Colors.grey[600], fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final imageUrl = maProvider.getImageUrl(currentTrack, size: 512);

    // Extract colors if adaptive theme is enabled and we have an image URL
    if (themeProvider.adaptiveTheme && imageUrl != null) {
      _extractColors(imageUrl);
    }

    // Determine if we should use adaptive theme colors
    final useAdaptiveTheme = themeProvider.adaptiveTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use
    ColorScheme? adaptiveScheme;
    if (useAdaptiveTheme) {
      adaptiveScheme = isDark ? _darkColorScheme : _lightColorScheme;
    }

    // Determine colors to use
    final backgroundColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.background
        : const Color(0xFF1a1a1a);

    final surfaceColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.surface
        : const Color(0xFF2a2a2a);

    final primaryColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primary
        : Colors.white;

    final textColor = useAdaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onSurface
        : Colors.white;

    return Hero(
      tag: HeroTags.nowPlayingBackground,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            selectedPlayer.name,
            style: TextStyle(
              color: textColor.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w300,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.queue_music, color: textColor),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QueueScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
            children: [
              const Spacer(),
              // Album Art with Hero animation
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth.clamp(200.0, 400.0);
                  return Center(
                    child: Hero(
                      tag: HeroTags.nowPlayingArt,
                      child: Container(
                        width: size,
                        height: size,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: imageUrl != null
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 1024,
                                  cacheHeight: 1024,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: const Color(0xFF2a2a2a),
                                      child: const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white24,
                                        size: 120,
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: const Color(0xFF2a2a2a),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white24,
                                    size: 120,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),

              // Track Info
              Text(
                currentTrack.name,
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                currentTrack.artistsString,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (currentTrack.album != null) ...[
                const SizedBox(height: 4),
                Text(
                  currentTrack.album!.name,
                  style: TextStyle(
                    color: textColor.withOpacity(0.54),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 32),

              // Progress Bar (showing elapsed time)
              if (currentTrack.duration != null) ...[
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: (_seekPosition ?? selectedPlayer.currentElapsedTime).clamp(0, currentTrack.duration!.inSeconds.toDouble()),
                    max: currentTrack.duration!.inSeconds.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _seekPosition = value;
                      });
                    },
                    onChangeStart: (value) {
                      setState(() {
                        _seekPosition = value;
                      });
                    },
                    onChangeEnd: (value) async {
                      final targetPosition = value.round();
                      print('🎯 Seek slider released at $targetPosition seconds');
                      try {
                        await maProvider.seek(selectedPlayer.playerId, targetPosition);
                        print('✅ Seek command completed');

                        // Wait briefly for server to update position
                        await Future.delayed(const Duration(milliseconds: 200));
                      } catch (e) {
                        print('❌ Error seeking: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error seeking: $e')),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _seekPosition = null;
                            print('🎯 Cleared seek position');
                          });
                        }
                      }
                    },
                    activeColor: primaryColor,
                    inactiveColor: primaryColor.withOpacity(0.24),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration((_seekPosition ?? selectedPlayer.currentElapsedTime).toInt()),
                        style: TextStyle(color: textColor.withOpacity(0.54), fontSize: 12),
                      ),
                      Text(
                        _formatDuration(currentTrack.duration!.inSeconds),
                        style: TextStyle(color: textColor.withOpacity(0.54), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else
                // Show indeterminate progress if no duration available
                const LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              const SizedBox(height: 16),

              // Playback Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: _queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.54),
                    ),
                    iconSize: 24,
                    onPressed: _isLoadingQueue ? null : _toggleShuffle,
                  ),
                  const SizedBox(width: 12),
                  // Previous
                  Hero(
                    tag: HeroTags.nowPlayingPreviousButton,
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedIconButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        iconSize: 42,
                        onPressed: () async {
                          try {
                            await maProvider.previousTrackSelectedPlayer();
                          } catch (e) {
                            print('❌ Error in previous track: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Play/Pause
                  Hero(
                    tag: HeroTags.nowPlayingPlayButton,
                    child: Material(
                      color: Colors.transparent,
                      child: _AnimatedPlayButton(
                        isPlaying: selectedPlayer.isPlaying,
                        primaryColor: primaryColor,
                        backgroundColor: backgroundColor,
                        onPressed: () async {
                          try {
                            await maProvider.playPauseSelectedPlayer();
                          } catch (e) {
                            print('❌ Error in play/pause: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Next
                  Hero(
                    tag: HeroTags.nowPlayingNextButton,
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedIconButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        iconSize: 42,
                        onPressed: () async {
                          try {
                            await maProvider.nextTrackSelectedPlayer();
                          } catch (e) {
                            print('❌ Error in next track: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Repeat
                  IconButton(
                    icon: Icon(
                      _queue?.repeatMode == 'one'
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                          ? primaryColor
                          : textColor.withOpacity(0.54),
                    ),
                    iconSize: 24,
                    onPressed: _isLoadingQueue ? null : _cycleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Volume Control
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: VolumeControl(compact: false),
              ),
              const Spacer(),
            ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Animated play/pause button with scale animation
class _AnimatedPlayButton extends StatefulWidget {
  final bool isPlaying;
  final Color primaryColor;
  final Color backgroundColor;
  final VoidCallback onPressed;

  const _AnimatedPlayButton({
    required this.isPlaying,
    required this.primaryColor,
    required this.backgroundColor,
    required this.onPressed,
  });

  @override
  State<_AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends State<_AnimatedPlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    // Animate press
    await _controller.forward();
    await _controller.reverse();

    // Call the callback
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: widget.primaryColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            color: widget.backgroundColor,
            iconSize: 42,
            onPressed: _handleTap,
          ),
        ),
      ),
    );
  }
}
