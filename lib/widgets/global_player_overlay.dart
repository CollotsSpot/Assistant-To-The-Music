import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import 'expandable_player.dart';

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

/// Wrapper widget that provides a global player overlay above all navigation.
///
/// This ensures the mini player and expanded player are consistent across
/// all screens (home, library, album details, artist details, etc.) without
/// needing separate player instances in each screen.
class GlobalPlayerOverlay extends StatefulWidget {
  final Widget child;

  GlobalPlayerOverlay({
    required this.child,
  }) : super(key: _overlayStateKey);

  @override
  State<GlobalPlayerOverlay> createState() => _GlobalPlayerOverlayState();

  /// Collapse the player if it's expanded
  static void collapsePlayer() {
    globalPlayerKey.currentState?.collapse();
  }

  /// Check if the player is currently expanded
  static bool get isPlayerExpanded =>
      globalPlayerKey.currentState?.isExpanded ?? false;

  /// Hide the mini player temporarily (e.g., when showing device selector)
  /// The player slides down off-screen with animation
  static void hidePlayer() {
    _overlayStateKey.currentState?._setHidden(true);
  }

  /// Show the mini player again (slides back up)
  static void showPlayer() {
    _overlayStateKey.currentState?._setHidden(false);
  }
}

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    if (hidden) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        widget.child,
        // Global player overlay - wrapped in RepaintBoundary for isolation
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Selector<MusicAssistantProvider, (bool, bool, bool)>(
                selector: (_, p) => (p.isConnected, p.currentTrack != null, p.selectedPlayer != null),
                builder: (context, data, _) {
                  final (isConnected, hasTrack, hasPlayer) = data;
                  // Only show player if connected and has a track
                  if (!isConnected || !hasTrack || !hasPlayer) {
                    return const SizedBox.shrink();
                  }
                  return ExpandablePlayer(
                    key: globalPlayerKey,
                    slideOffset: _slideAnimation.value,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
