import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import 'animated_icon_button.dart';
import 'global_player_overlay.dart';
import 'volume_control.dart';
import 'player/player_widgets.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// This widget is designed to be used as a global overlay, positioned above
/// the bottom navigation bar. It uses smooth morphing animations where each
/// element transitions from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  /// Slide offset for hiding the mini player (0.0 = visible, 1.0 = hidden below screen)
  final double slideOffset;

  const ExpandablePlayer({
    super.key,
    this.slideOffset = 0.0,
  });

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Queue panel slide animation
  late AnimationController _queuePanelController;
  late Animation<double> _queuePanelAnimation;

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  bool _isLoadingQueue = false;

  // Progress timer for elapsed time updates
  Timer? _progressTimer;
  double? _seekPosition;
  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double?> _seekPositionNotifier = ValueNotifier<double?>(null);

  // Dimensions
  static const double _collapsedHeight = 64.0;
  static const double _collapsedMargin = 12.0; // Increased from 8 to 12 (4px more gap above nav bar)
  static const double _collapsedBorderRadius = 16.0;
  static const double _collapsedArtSize = 64.0;
  static const double _bottomNavHeight = 56.0;
  static const double _edgeDeadZone = 40.0; // Dead zone for Android back gesture

  // Track horizontal drag start position
  double? _horizontalDragStartX;

  // Slide animation for device switching - now supports finger-following
  late AnimationController _slideController;
  double _slideOffset = 0.0; // -1 to 1, negative = sliding left, positive = sliding right
  bool _isSliding = false;
  bool _isDragging = false; // True while finger is actively dragging

  // For peek preview - track which player we'd switch to
  dynamic _peekPlayer; // The player that would be selected if swipe commits
  String? _peekImageUrl; // Image URL for peek player's current track

  // Flag to indicate we're in the middle of a player switch transition
  // When true, we hide main content and show peek content at center
  bool _inTransition = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Notify listeners of expansion progress changes
    _controller.addListener(_notifyExpansionProgress);

    // Queue panel animation
    _queuePanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _queuePanelAnimation = CurvedAnimation(
      parent: _queuePanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Slide animation for device switching - used for snap/spring animations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        _loadQueue();
        _startProgressTimer();
      } else if (status == AnimationStatus.dismissed) {
        _progressTimer?.cancel();
        // Close queue panel when player collapses
        _queuePanelController.reverse();
      }
    });

    // Auto-refresh queue when panel is open
    _queuePanelController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startQueueRefreshTimer();
      } else if (status == AnimationStatus.dismissed) {
        _stopQueueRefreshTimer();
      }
    });
  }

  Timer? _queueRefreshTimer;

  void _startQueueRefreshTimer() {
    _stopQueueRefreshTimer();
    // Refresh queue at configured interval when panel is open
    _queueRefreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted && isQueuePanelOpen) {
        _loadQueue();
      }
    });
  }

  void _stopQueueRefreshTimer() {
    _queueRefreshTimer?.cancel();
    _queueRefreshTimer = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _queuePanelController.dispose();
    _slideController.dispose();
    _progressTimer?.cancel();
    _queueRefreshTimer?.cancel();
    _progressNotifier.dispose();
    _seekPositionNotifier.dispose();
    super.dispose();
  }

  void expand() {
    _controller.forward();
  }

  void collapse() {
    // Instantly hide queue panel when collapsing to avoid visual glitches
    // during Android's predictive back gesture
    _queuePanelController.value = 0;
    _controller.reverse();
  }

  bool get isExpanded => _controller.value > 0.5;

  double get expansionProgress => _controller.value;

  Color? _currentExpandedBgColor;
  Color? get currentExpandedBgColor => _currentExpandedBgColor;

  void _notifyExpansionProgress() {
    playerExpansionNotifier.value = PlayerExpansionState(
      _controller.value,
      _currentExpandedBgColor,
    );
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    // Use local player report interval for progress updates (1 second)
    // Update only the progress notifier to avoid rebuilding the entire widget tree
    _progressTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) {
      if (mounted && isExpanded) {
        final maProvider = context.read<MusicAssistantProvider>();
        final selectedPlayer = maProvider.selectedPlayer;
        if (selectedPlayer != null) {
          _progressNotifier.value = selectedPlayer.currentElapsedTime.toInt();
        }
      }
    });
  }

  Future<void> _loadQueue() async {
    if (_isLoadingQueue) return;

    setState(() => _isLoadingQueue = true);

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
        setState(() => _isLoadingQueue = false);
      }
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });

        // Share adaptive colors globally via ThemeProvider
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2);
      }
    } catch (e) {
      // Silently ignore color extraction errors
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

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleQueuePanel() {
    if (_queuePanelController.isAnimating) return;
    if (_queuePanelController.value == 0) {
      _queuePanelController.forward();
    } else {
      _queuePanelController.reverse();
    }
  }

  bool get isQueuePanelOpen => _queuePanelController.value > 0.5;

  /// Get available players sorted alphabetically (consistent with device selector)
  List<dynamic> _getAvailablePlayersSorted(MusicAssistantProvider maProvider) {
    // Use the provider's already-sorted list, filter for available only
    return maProvider.availablePlayers.where((p) => p.available).toList();
  }

  /// Get the next or previous player relative to current selection
  dynamic _getAdjacentPlayer(MusicAssistantProvider maProvider, {required bool next}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return null;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    if (currentIndex == -1) return players[0];

    int adjacentIndex;
    if (next) {
      adjacentIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    } else {
      adjacentIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    }

    return players[adjacentIndex];
  }

  // Cache for peek track data
  dynamic _peekTrack;

  /// Cycle to the next available player (for swipe gesture)
  void _cycleToNextPlayer(MusicAssistantProvider maProvider, {bool reverse = false}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    // If current player not found in list, start from beginning
    if (currentIndex == -1) {
      HapticFeedback.mediumImpact();
      maProvider.selectPlayer(players[0]);
      return;
    }

    int nextIndex;
    if (reverse) {
      nextIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    } else {
      nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    }

    // Haptic feedback on device switch
    HapticFeedback.mediumImpact();

    // Animate slide transition
    _animateSlide(reverse ? 1 : -1, () {
      maProvider.selectPlayer(players[nextIndex]);
    });
  }

  /// Handle real-time drag updates for finger-following swipe
  void _handleHorizontalDragUpdate(DragUpdateDetails details, MusicAssistantProvider maProvider, double containerWidth) {
    if (_isSliding) return;

    // Start tracking if not already
    if (!_isDragging) {
      _isDragging = true;
      _peekPlayer = null;
      _peekImageUrl = null;
      _peekTrack = null;
    }

    // Calculate normalized offset (-1 to 1 range)
    // Negative = dragging left (showing next player from right)
    // Positive = dragging right (showing previous player from left)
    final delta = details.primaryDelta ?? 0;
    final normalizedDelta = delta / containerWidth;
    final newSlideOffset = (_slideOffset + normalizedDelta).clamp(-1.0, 1.0);

    // Update peek player based on drag direction (must be inside setState to trigger rebuild)
    setState(() {
      _slideOffset = newSlideOffset;
      if (_slideOffset != 0) {
        _updatePeekPlayerState(maProvider, _slideOffset);
      }
    });
  }

  /// Update peek player state variables (called inside setState)
  void _updatePeekPlayerState(MusicAssistantProvider maProvider, double dragDirection) {
    // dragDirection < 0 means swiping left (next player)
    // dragDirection > 0 means swiping right (previous player)
    final isNext = dragDirection < 0;
    final newPeekPlayer = _getAdjacentPlayer(maProvider, next: isNext);

    if (newPeekPlayer?.playerId != _peekPlayer?.playerId) {
      _peekPlayer = newPeekPlayer;
      // Get the peek player's current track image if available
      if (_peekPlayer != null) {
        _peekTrack = maProvider.getCachedTrackForPlayer(_peekPlayer.playerId);
        _peekImageUrl = _peekTrack != null ? maProvider.getImageUrl(_peekTrack, size: 512) : null;
      } else {
        _peekTrack = null;
        _peekImageUrl = null;
      }
    }
  }

  /// Handle drag end - either commit to next player or snap back
  void _handleHorizontalDragEnd(DragEndDetails details, MusicAssistantProvider maProvider) {
    if (!_isDragging || _isSliding) {
      _isDragging = false;
      return;
    }

    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;

    // Thresholds for committing the swipe
    const commitThreshold = 0.3; // 30% of width
    const velocityThreshold = 500.0; // px/s

    final shouldCommit = _slideOffset.abs() > commitThreshold || velocity.abs() > velocityThreshold;
    final direction = _slideOffset != 0 ? _slideOffset.sign : (velocity != 0 ? -velocity.sign : 0);

    if (shouldCommit && _peekPlayer != null && direction != 0) {
      // Commit: animate to full slide, switch player, then reset
      // Note: Don't clear _peekPlayer here - let _animateCommit handle cleanup
      // so the peek content can remain visible during the transition
      _animateCommit(direction.toInt(), () {
        HapticFeedback.mediumImpact();
        maProvider.selectPlayer(_peekPlayer);
      });
    } else {
      // Cancel: spring back to center
      _animateSnapBack();
    }
  }

  /// Animate committing to the next/previous player
  void _animateCommit(int direction, VoidCallback onSwitch) {
    if (_isSliding) return;
    _isSliding = true;

    // Mark transition BEFORE animation - this keeps peek content visible
    // and hides main content to prevent any flash
    _inTransition = true;

    final startOffset = _slideOffset;
    final targetOffset = direction < 0 ? -1.0 : 1.0;

    _slideController.reset();

    void animateToTarget() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutCubic.transform(_slideController.value);
      setState(() {
        _slideOffset = startOffset + (targetOffset - startOffset) * curvedValue;
      });
    }

    _slideController.addListener(animateToTarget);
    _slideController.duration = const Duration(milliseconds: 150);

    _slideController.forward().then((_) {
      if (!mounted) return;

      _slideController.removeListener(animateToTarget);

      // Cache the peek data BEFORE switching - we'll use this to crossfade
      final cachedPeekPlayer = _peekPlayer;
      final cachedPeekTrack = _peekTrack;
      final cachedPeekImageUrl = _peekImageUrl;

      // Switch the player - this sets currentTrack from cache in the provider
      onSwitch();

      // Get the new track state
      final maProvider = context.read<MusicAssistantProvider>();
      final newTrack = maProvider.currentTrack;

      // Move peek content to center position (slideOffset = 0) while keeping it visible.
      // The main content is hidden via _inTransition flag.
      // This creates a seamless visual - peek content is already at center.
      setState(() {
        _slideOffset = 0.0;
        _isSliding = false;
        // Keep _inTransition = true and peek data intact
      });

      if (newTrack != null) {
        // Switching to a playing player - need to wait for image to be ready
        // before showing main content and hiding peek
        final newImageUrl = maProvider.getImageUrl(newTrack, size: 512);

        if (newImageUrl != null && newImageUrl == cachedPeekImageUrl) {
          // Same image - can transition immediately
          _completeTransition();
        } else if (newImageUrl != null) {
          // Different image - precache it first, then transition
          _precacheAndTransition(newImageUrl);
        } else {
          // No image - transition after frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      } else {
        // Switching to non-playing player - DeviceSelectorBar will show
        // Wait for it to render, then complete transition
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        });
      }

      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Precache an image and then complete the transition
  void _precacheAndTransition(String imageUrl) {
    // Use CachedNetworkImage's cache to ensure image is ready
    final imageProvider = CachedNetworkImageProvider(imageUrl);
    final imageStream = imageProvider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;

    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        imageStream.removeListener(listener);
        if (mounted) {
          // Image is now in memory cache - safe to transition
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      },
      onError: (exception, stackTrace) {
        imageStream.removeListener(listener);
        // Even on error, complete the transition
        if (mounted) _completeTransition();
      },
    );

    imageStream.addListener(listener);

    // Safety timeout - don't wait forever
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _inTransition) {
        imageStream.removeListener(listener);
        _completeTransition();
      }
    });
  }

  /// Complete the transition by hiding peek content and showing main content
  void _completeTransition() {
    if (!mounted) return;
    setState(() {
      _inTransition = false;
      _peekPlayer = null;
      _peekTrack = null;
      _peekImageUrl = null;
    });
  }

  /// Animate snapping back to center (cancelled swipe)
  void _animateSnapBack() {
    if (_isSliding) return;
    _isSliding = true;

    final startOffset = _slideOffset;
    _slideController.reset();

    void animateBack() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutBack.transform(_slideController.value);
      setState(() {
        _slideOffset = startOffset * (1.0 - curvedValue);
      });
    }

    _slideController.addListener(animateBack);
    _slideController.duration = const Duration(milliseconds: 300);

    _slideController.forward().then((_) {
      if (!mounted) return;
      _slideController.removeListener(animateBack);
      setState(() {
        _slideOffset = 0.0;
        _isSliding = false;
        _peekPlayer = null;
        _peekImageUrl = null;
      });
      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Legacy method - now calls new commit animation
  void _animateSlide(int direction, VoidCallback onComplete) {
    _animateCommit(direction, onComplete);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show if no player selected
        if (selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        // Get image URL for current track
        final imageUrl = currentTrack != null
            ? maProvider.getImageUrl(currentTrack, size: 512)
            : null;

        // Extract colors for adaptive theme
        if (themeProvider.adaptiveTheme && imageUrl != null) {
          _extractColors(imageUrl);
        }

        return AnimatedBuilder(
          animation: Listenable.merge([_expandAnimation, _queuePanelAnimation]),
          builder: (context, _) {
            // If no track is playing, show device selector bar
            if (currentTrack == null) {
              return _buildDeviceSelectorBar(context, maProvider, selectedPlayer, themeProvider);
            }
            return _buildMorphingPlayer(
              context,
              maProvider,
              selectedPlayer,
              currentTrack,
              imageUrl,
              themeProvider,
            );
          },
        );
      },
    );
  }

  /// Build a compact device selector bar when no track is playing
  Widget _buildDeviceSelectorBar(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    ThemeProvider themeProvider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    final backgroundColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    final textColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;

    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final bottomOffset = bottomNavSpace + _collapsedMargin;
    final width = screenSize.width - (_collapsedMargin * 2);

    // Apply slide offset for hiding
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + bottomOffset + 20);
    final adjustedBottomOffset = bottomOffset - slideDownAmount;

    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;

    return Positioned(
      left: _collapsedMargin,
      right: _collapsedMargin,
      bottom: adjustedBottomOffset,
      child: DeviceSelectorBar(
        selectedPlayer: selectedPlayer,
        peekPlayer: _peekPlayer,
        hasMultiplePlayers: hasMultiplePlayers,
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: width,
        height: _collapsedHeight,
        borderRadius: _collapsedBorderRadius,
        slideOffset: _slideOffset,
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, width);
        },
        onHorizontalDragEnd: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          _handleHorizontalDragEnd(details, maProvider);
        },
      ),
    );
  }

  Widget _buildMorphingPlayer(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    ThemeProvider themeProvider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Animation progress
    final t = _expandAnimation.value;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    // Color transitions - mini player uses adaptive primaryContainer (darker tinted color)
    final collapsedBg = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF121212);
    // Only update if we have adaptive colors, otherwise keep previous value
    if (adaptiveScheme != null) {
      _currentExpandedBgColor = expandedBg;
    } else if (_currentExpandedBgColor == null) {
      _currentExpandedBgColor = expandedBg; // First time fallback
    }
    final backgroundColor = Color.lerp(collapsedBg, expandedBg, t)!;

    final collapsedTextColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;
    final expandedTextColor = adaptiveScheme?.onSurface ?? Colors.white;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    final primaryColor = adaptiveScheme?.primary ?? Colors.white;

    // Always position above bottom nav bar
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    final expandedBottomOffset = bottomNavSpace;
    final expandedHeight = screenSize.height - bottomNavSpace;

    // Apply slide offset to hide mini player (slides down off-screen)
    // Only apply when collapsed (t == 0), don't affect expanded state
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + collapsedBottomOffset + 20);
    final slideAdjustedBottomOffset = t < 0.1
        ? collapsedBottomOffset - slideDownAmount
        : _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);

    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final width = _lerpDouble(collapsedWidth, screenSize.width, t);
    final height = _lerpDouble(_collapsedHeight, expandedHeight, t);
    final horizontalMargin = _lerpDouble(_collapsedMargin, 0, t);
    // Use slide-adjusted offset when collapsed, normal lerp otherwise
    final bottomOffset = slideAdjustedBottomOffset;
    final borderRadius = _lerpDouble(_collapsedBorderRadius, 0, t);

    // ===========================================
    // EXPANDED LAYOUT - Vertical rhythm based design
    // ===========================================
    // Using 8px grid for consistent spacing
    // Header: 48px (player name area)
    // Art: proportional to screen, centered
    // Track info: clear hierarchy with breathing room
    // Progress: slim, elegant
    // Controls: generously spaced
    // Volume: bottom anchored

    final headerHeight = 48.0;
    final contentPadding = 32.0; // horizontal padding for content

    // Art sizing - larger on bigger screens, max 85% of width
    final maxArtSize = screenSize.width - (contentPadding * 2);
    final expandedArtSize = (maxArtSize * 0.92).clamp(280.0, 400.0);
    final artSize = _lerpDouble(_collapsedArtSize, expandedArtSize, t);
    final artBorderRadius = _lerpDouble(0, 12, t); // Square in mini player, rounded when expanded

    // Art position
    final collapsedArtLeft = 0.0;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final artLeft = _lerpDouble(collapsedArtLeft, expandedArtLeft, t);

    final collapsedArtTop = 0.0;
    final expandedArtTop = topPadding + headerHeight + 16;
    final artTop = _lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Typography - clear hierarchy
    // Title: bold, prominent (24px)
    // Artist: medium weight, secondary (18px expanded, was 16px)
    // Album: light, tertiary (15px expanded, was 13px)
    final titleFontSize = _lerpDouble(16.0, 24.0, t);
    final artistFontSize = _lerpDouble(14.0, 18.0, t); // Increased from 16 to 18

    final collapsedTitleLeft = _collapsedArtSize + 8; // Reduced from 12 to 8 (4px less)
    final expandedTitleLeft = contentPadding;
    final titleLeft = _lerpDouble(collapsedTitleLeft, expandedTitleLeft, t);

    final collapsedTitleTop = (_collapsedHeight - 36) / 2; // Centered vertically (adjusted for increased track/artist gap)

    final collapsedTitleWidth = screenSize.width - _collapsedArtSize - 150;
    final expandedTitleWidth = screenSize.width - (contentPadding * 2);
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Measure actual title height for dynamic layout
    final titleStyle = TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: currentTrack.name, style: titleStyle),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: expandedTitleWidth);
    final expandedTitleHeight = titlePainter.height;

    // Calculate track info block height (title + gap + artist + gap + album)
    final titleToArtistGap = 12.0;
    final artistToAlbumGap = 8.0;
    final artistHeight = 22.0; // Approximate height for 18px font
    final albumHeight = currentTrack.album != null ? 20.0 : 0.0; // Album line or nothing
    final trackInfoBlockHeight = expandedTitleHeight + titleToArtistGap + artistHeight +
        (currentTrack.album != null ? artistToAlbumGap + albumHeight : 0.0);

    // Controls section heights (from bottom up):
    // - Volume slider: 48px
    // - Gap: 40px (was 88-48=40 from volumeTop calculation)
    // - Controls row: ~70px (centered at expandedControlsTop)
    // - Gap: 64px (from expandedControlsTop = expandedProgressTop + 64)
    // - Progress bar + times: ~70px
    // Total from bottom edge: ~48 + 40 + 70 + 64 = 222, plus safe area padding
    // Position progress bar so controls section is anchored at bottom
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final controlsSectionHeight = 222.0; // Total height of progress + controls + volume
    final playButtonHalfHeight = 36.0; // Half of the 72px play button container
    final expandedProgressTop = screenSize.height - bottomSafeArea - controlsSectionHeight - 24 - playButtonHalfHeight;

    // Calculate available space between art bottom and progress bar
    final artBottom = expandedArtTop + expandedArtSize;
    final availableSpace = expandedProgressTop - artBottom;

    // Center the track info block in available space
    final trackInfoTopMargin = (availableSpace - trackInfoBlockHeight) / 2;
    final expandedTitleTop = artBottom + trackInfoTopMargin;
    final titleTop = _lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    // Artist positioned dynamically based on actual title height
    final collapsedArtistTop = collapsedTitleTop + 22; // Increased gap from 18 to 22
    final expandedArtistTop = expandedTitleTop + expandedTitleHeight + titleToArtistGap;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Album - subtle, below artist
    final expandedAlbumTop = expandedArtistTop + artistHeight + artistToAlbumGap;

    // Controls - main row with comfortable touch targets
    final collapsedControlsRight = 8.0;
    final collapsedControlsTop = (_collapsedHeight - 34) / 2 - 6;
    final expandedControlsTop = expandedProgressTop + 64;
    final controlsTop = _lerpDouble(collapsedControlsTop, expandedControlsTop, t);

    // Button sizes - larger in expanded for better touch targets
    final skipButtonSize = _lerpDouble(28, 36, t);
    final playButtonSize = _lerpDouble(34, 44, t);
    final playButtonContainerSize = _lerpDouble(34, 72, t);

    final expandedElementsOpacity = Curves.easeIn.transform((t - 0.5).clamp(0, 0.5) * 2);

    // Volume - anchored near bottom with breathing room
    final volumeTop = expandedControlsTop + 88;

    // Queue panel slide amount (0 = hidden, 1 = fully visible)
    final queueT = _queuePanelAnimation.value;

    // Check if we have multiple players for swipe gesture
    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;
    final selectedPlayerId = selectedPlayer.playerId;

    // Calculate slide offset for mini player content (only when collapsed)
    final miniPlayerSlideOffset = t < 0.1 ? _slideOffset * collapsedWidth : 0.0;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        // Use translucent to allow child widgets (like buttons) to receive taps
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!isExpanded) expand();
        },
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < -10 && !isExpanded) {
            expand();
          } else if (details.primaryDelta! > 10 && isExpanded && !isQueuePanelOpen) {
            collapse();
          }
        },
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          // Only handle in collapsed mode with multiple players
          if (isExpanded || !hasMultiplePlayers) return;

          // Ignore drags that started in the edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, collapsedWidth);
        },
        onHorizontalDragEnd: (details) {
          // Ignore swipes that started near the edges (Android back gesture zone)
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          if (isExpanded) {
            // Expanded mode: swipe to open/close queue
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -300 && !isQueuePanelOpen) {
                _toggleQueuePanel();
              } else if (details.primaryVelocity! > 300 && isQueuePanelOpen) {
                _toggleQueuePanel();
              }
            }
          } else if (hasMultiplePlayers) {
            // Collapsed mode: use finger-following handler
            _handleHorizontalDragEnd(details, maProvider);
          }
        },
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          elevation: _lerpDouble(4, 0, t),
          shadowColor: Colors.black.withOpacity(0.3),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Peek player content (shows when dragging OR during transition)
                // Show when: actively dragging (slideOffset != 0) OR in transition state
                // Must have peek data to render
                if (t < 0.1 && _peekPlayer != null && (_slideOffset.abs() > 0.01 || _inTransition))
                  _buildPeekContent(
                    maProvider: maProvider,
                    peekPlayer: _peekPlayer,
                    peekImageUrl: _peekImageUrl,
                    slideOffset: _slideOffset,
                    containerWidth: collapsedWidth,
                    artSize: _collapsedArtSize,
                    titleLeft: collapsedTitleLeft,
                    titleTop: collapsedTitleTop,
                    titleWidth: collapsedTitleWidth,
                    artistTop: collapsedArtistTop,
                    titleFontSize: 16.0,
                    artistFontSize: 14.0,
                    textColor: textColor,
                    colorScheme: colorScheme,
                  ),

                // Album art - with slide animation when collapsed
                // Hidden during transition to prevent flash (peek content shows instead)
                Positioned(
                  left: artLeft + miniPlayerSlideOffset,
                  top: artTop,
                  child: Opacity(
                    opacity: _inTransition && t < 0.1 ? 0.0 : 1.0,
                    child: Container(
                      width: artSize,
                      height: artSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(artBorderRadius),
                        boxShadow: t > 0.3
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3 * t),
                                  blurRadius: 24 * t,
                                  offset: Offset(0, 8 * t),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(artBorderRadius),
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: t > 0.5 ? 1024 : 256,
                                memCacheHeight: t > 0.5 ? 1024 : 256,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholderFadeInDuration: Duration.zero,
                                placeholder: (_, __) => _buildPlaceholderArt(colorScheme, t),
                                errorWidget: (_, __, ___) => _buildPlaceholderArt(colorScheme, t),
                              )
                            : _buildPlaceholderArt(colorScheme, t),
                      ),
                    ),
                  ),
                ),

                // Track title - with slide animation when collapsed
                // Hidden during transition to prevent flash
                Positioned(
                  left: titleLeft + miniPlayerSlideOffset,
                  top: titleTop,
                  child: Opacity(
                    opacity: _inTransition && t < 0.1 ? 0.0 : 1.0,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        currentTrack.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: titleFontSize,
                          fontWeight: t > 0.5 ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: t > 0.5 ? -0.5 : 0,
                          height: 1.2,
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: t > 0.5 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),

                // Artist name - with slide animation when collapsed
                // Hidden during transition to prevent flash
                Positioned(
                  left: titleLeft + miniPlayerSlideOffset,
                  top: artistTop,
                  child: Opacity(
                    opacity: _inTransition && t < 0.1 ? 0.0 : 1.0,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        currentTrack.artistsString,
                        style: TextStyle(
                          color: textColor.withOpacity(t > 0.5 ? 0.7 : 0.6),
                          fontSize: artistFontSize,
                          fontWeight: t > 0.5 ? FontWeight.w400 : FontWeight.normal,
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),

                // Album name (expanded only)
                if (currentTrack.album != null && t > 0.3)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: Text(
                        currentTrack.album!.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.45),
                          fontSize: 15, // Increased from 13 to 15
                          fontWeight: FontWeight.w300,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Progress bar (expanded only)
                if (t > 0.5 && currentTrack.duration != null)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedProgressTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progressNotifier,
                        builder: (context, elapsedTime, child) {
                          return ValueListenableBuilder<double?>(
                            valueListenable: _seekPositionNotifier,
                            builder: (context, seekPosition, child) {
                              final currentProgress = seekPosition ?? elapsedTime.toDouble();
                              return Column(
                                children: [
                                  SizedBox(
                                    height: 48, // Increase touch target height
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                                        trackShape: const RoundedRectSliderTrackShape(),
                                      ),
                                      child: Slider(
                                        value: currentProgress.clamp(0.0, currentTrack.duration!.inSeconds.toDouble()).toDouble(),
                                        max: currentTrack.duration!.inSeconds.toDouble(),
                                        onChanged: (value) => _seekPositionNotifier.value = value,
                                        onChangeStart: (value) => _seekPositionNotifier.value = value,
                                        onChangeEnd: (value) async {
                                          try {
                                            await maProvider.seek(selectedPlayer.playerId, value.round());
                                            await Future.delayed(const Duration(milliseconds: 200));
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error seeking: $e')),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              _seekPositionNotifier.value = null;
                                              _seekPosition = null;
                                            }
                                          }
                                        },
                                        activeColor: primaryColor,
                                        inactiveColor: primaryColor.withOpacity(0.2),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(currentProgress.toInt()),
                                          style: TextStyle(
                                            color: textColor.withOpacity(0.5),
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        Text(
                                          _formatDuration(currentTrack.duration!.inSeconds),
                                          style: TextStyle(
                                            color: textColor.withOpacity(0.5),
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                // Playback controls - with slide animation when collapsed
                Positioned(
                  left: t > 0.5 ? 0 : null,
                  right: t > 0.5 ? 0 : collapsedControlsRight - miniPlayerSlideOffset,
                  top: controlsTop,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: t > 0.5 ? MainAxisAlignment.center : MainAxisAlignment.end,
                    children: [
                      // Shuffle (expanded only)
                      if (t > 0.5)
                        Opacity(
                          opacity: expandedElementsOpacity,
                          child: _buildSecondaryButton(
                            icon: Icons.shuffle_rounded,
                            color: _queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.5),
                            onPressed: _isLoadingQueue ? null : _toggleShuffle,
                          ),
                        ),
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),

                      // Previous
                      _buildControlButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.previousTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

                      // Play/Pause
                      _buildPlayButton(
                        isPlaying: selectedPlayer.isPlaying,
                        textColor: textColor,
                        primaryColor: primaryColor,
                        backgroundColor: backgroundColor,
                        size: playButtonSize,
                        containerSize: playButtonContainerSize,
                        progress: t,
                        onPressed: () => maProvider.playPauseSelectedPlayer(),
                        onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

                      // Next
                      _buildControlButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.nextTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),

                      // Repeat (expanded only)
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),
                      if (t > 0.5)
                        Opacity(
                          opacity: expandedElementsOpacity,
                          child: _buildSecondaryButton(
                            icon: _queue?.repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                            color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                                ? primaryColor
                                : textColor.withOpacity(0.5),
                            onPressed: _isLoadingQueue ? null : _cycleRepeat,
                          ),
                        ),
                    ],
                  ),
                ),

                // Volume control (expanded only)
                if (t > 0.5)
                  Positioned(
                    left: 48,
                    right: 48,
                    top: volumeTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: const VolumeControl(compact: false),
                    ),
                  ),

                // Collapse button (expanded only)
                if (t > 0.3)
                  Positioned(
                    top: topPadding + 4,
                    left: 4,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                        onPressed: collapse,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),

                // Queue button (expanded only) - hide when queue panel is open
                if (t > 0.3 && queueT < 0.5)
                  Positioned(
                    top: topPadding + 4,
                    right: 4,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0) * (1 - queueT * 2).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.queue_music_rounded, color: textColor, size: 24),
                        onPressed: _toggleQueuePanel,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),

                // Player name (expanded only)
                if (t > 0.5)
                  Positioned(
                    top: topPadding + 12,
                    left: 56,
                    right: 56,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: ((t - 0.5) / 0.5).clamp(0.0, 1.0),
                        child: Text(
                          selectedPlayer.name,
                          style: TextStyle(
                            color: textColor.withOpacity(0.6),
                            fontSize: 15, // Increased from 13 to 15
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                // Queue panel (slides in from right)
                if (t > 0.5 && queueT > 0)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(_queuePanelAnimation),
                        child: QueuePanel(
                          maProvider: maProvider,
                          queue: _queue,
                          isLoading: _isLoadingQueue,
                          textColor: textColor,
                          primaryColor: primaryColor,
                          backgroundColor: expandedBg,
                          topPadding: topPadding,
                          onClose: _toggleQueuePanel,
                          onRefresh: _loadQueue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the peek player content that slides in from the edge during drag
  Widget _buildPeekContent({
    required MusicAssistantProvider maProvider,
    required dynamic peekPlayer,
    required String? peekImageUrl,
    required double slideOffset,
    required double containerWidth,
    required double artSize,
    required double titleLeft,
    required double titleTop,
    required double titleWidth,
    required double artistTop,
    required double titleFontSize,
    required double artistFontSize,
    required Color textColor,
    required ColorScheme colorScheme,
  }) {
    // Calculate sliding position
    // During transition (_inTransition = true), peek should be at center (offset 0)
    // When sliding left (negative offset), peek comes from right
    // When sliding right (positive offset), peek comes from left

    double peekBaseOffset;

    if (_inTransition && slideOffset.abs() < 0.01) {
      // During transition with slideOffset at 0, show peek at center
      peekBaseOffset = 0.0;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();

      // Position calculation:
      // From right: starts at containerWidth (off right edge), moves to 0 as progress increases
      // From left: starts at -containerWidth (off left edge), moves to 0 as progress increases
      peekBaseOffset = isFromRight
          ? containerWidth * (1 - peekProgress)  // Slides in from right
          : -containerWidth * (1 - peekProgress); // Slides in from left
    }

    // Check if peek player has a track - if not, show device info instead
    final hasTrack = _peekTrack != null && peekImageUrl != null;
    final peekTrackName = hasTrack ? _peekTrack!.name : (peekPlayer?.name ?? 'Unknown');
    final peekArtistName = hasTrack ? (_peekTrack!.artistsString ?? '') : 'Swipe to switch device';

    return Stack(
      children: [
        // Peek album art / device icon
        Positioned(
          left: peekBaseOffset,
          top: 0,
          child: Container(
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
            ),
            child: hasTrack
                ? CachedNetworkImage(
                    imageUrl: peekImageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 256,
                    memCacheHeight: 256,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    placeholder: (_, __) => _buildMiniPlaceholderArt(colorScheme),
                    errorWidget: (_, __, ___) => _buildMiniPlaceholderArt(colorScheme),
                  )
                : _buildDeviceIcon(peekPlayer?.name ?? '', artSize, colorScheme),
          ),
        ),

        // Peek track title / device name
        Positioned(
          left: titleLeft + peekBaseOffset,
          top: titleTop,
          child: SizedBox(
            width: titleWidth,
            child: Text(
              peekTrackName,
              style: TextStyle(
                color: textColor,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // Peek artist name / device hint
        Positioned(
          left: titleLeft + peekBaseOffset,
          top: artistTop,
          child: SizedBox(
            width: titleWidth,
            child: Text(
              peekArtistName,
              style: TextStyle(
                color: textColor.withOpacity(0.6),
                fontSize: artistFontSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// Build device icon for non-playing peek player
  Widget _buildDeviceIcon(String playerName, double size, ColorScheme colorScheme) {
    final nameLower = playerName.toLowerCase();
    IconData icon;
    if (nameLower.contains('phone') || nameLower.contains('ensemble')) {
      icon = Icons.phone_android_rounded;
    } else if (nameLower.contains('group') || nameLower.contains('all')) {
      icon = Icons.speaker_group_rounded;
    } else if (nameLower.contains('tv') || nameLower.contains('television')) {
      icon = Icons.tv_rounded;
    } else if (nameLower.contains('cast') || nameLower.contains('chromecast')) {
      icon = Icons.cast_rounded;
    } else {
      icon = Icons.speaker_rounded;
    }

    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          color: colorScheme.onSurfaceVariant,
          size: size * 0.5,
        ),
      ),
    );
  }

  /// Simplified placeholder for mini player peek
  Widget _buildMiniPlaceholderArt(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, double t) {
    return Container(
      color: Color.lerp(colorScheme.surfaceVariant, const Color(0xFF2a2a2a), t),
      child: Icon(
        Icons.music_note_rounded,
        color: Color.lerp(colorScheme.onSurfaceVariant, Colors.white24, t),
        size: _lerpDouble(24, 120, t),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    required bool useAnimation,
  }) {
    if (useAnimation) {
      return AnimatedIconButton(
        icon: icon,
        color: color,
        iconSize: size,
        onPressed: onPressed,
      );
    }
    return IconButton(
      icon: Icon(icon),
      color: color,
      iconSize: size,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon),
        color: color,
        iconSize: 22,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildPlayButton({
    required bool isPlaying,
    required Color textColor,
    required Color primaryColor,
    required Color backgroundColor,
    required double size,
    required double containerSize,
    required double progress,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    final bgColor = Color.lerp(Colors.transparent, primaryColor, progress);
    final iconColor = Color.lerp(textColor, backgroundColor, progress);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: containerSize,
        height: containerSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: iconColor,
          iconSize: size,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
