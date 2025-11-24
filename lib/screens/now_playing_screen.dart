import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../widgets/volume_control.dart';
import 'queue_screen.dart';
import '../constants/hero_tags.dart';
import '../widgets/animated_icon_button.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  PlayerQueue? _queue;
  bool _isLoadingQueue = true;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _startProgressTimer();
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

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          selectedPlayer.name,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
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
              Hero(
                tag: HeroTags.nowPlayingArt,
                flightShuttleBuilder: (
                  flightContext,
                  animation,
                  flightDirection,
                  fromHeroContext,
                  toHeroContext,
                ) {
                  final Hero toHero = toHeroContext.widget as Hero;
                  return ScaleTransition(
                    scale: animation.drive(
                      Tween<double>(begin: 0.0, end: 1.0).chain(
                        CurveTween(curve: Curves.fastOutSlowIn),
                      ),
                    ),
                    child: toHero.child,
                  );
                },
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                  child: AspectRatio(
                    aspectRatio: 1,
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
              ),
              const SizedBox(height: 40),

              // Track Info
              Text(
                currentTrack.name,
                style: const TextStyle(
                  color: Colors.white,
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
                style: const TextStyle(
                  color: Colors.white70,
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
                  style: const TextStyle(
                    color: Colors.white54,
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
                Slider(
                  value: selectedPlayer.currentElapsedTime.clamp(0, currentTrack.duration!.inSeconds.toDouble()),
                  max: currentTrack.duration!.inSeconds.toDouble(),
                  onChanged: null, // TODO: Implement seek
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(selectedPlayer.currentElapsedTime.toInt()),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        _formatDuration(currentTrack.duration!.inSeconds),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                      color: _queue?.shuffle == true ? Colors.blue : Colors.white54,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                          ? Colors.blue
                          : Colors.white54,
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
  final VoidCallback onPressed;

  const _AnimatedPlayButton({
    required this.isPlaying,
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
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            color: const Color(0xFF1a1a1a),
            iconSize: 42,
            onPressed: _handleTap,
          ),
        ),
      ),
    );
  }
}
