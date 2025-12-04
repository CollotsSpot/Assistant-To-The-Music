import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/theme_provider.dart';
import 'expandable_player.dart';

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

/// Constants for bottom UI elements spacing
class BottomSpacing {
  /// Height of the bottom navigation bar
  static const double navBarHeight = 56.0;

  /// Space needed when only nav bar is visible (with some extra padding)
  static const double navBarOnly = navBarHeight + 16.0;
}

/// ValueNotifier for player expansion progress (0.0 to 1.0) and background color
class PlayerExpansionState {
  final double progress;
  final Color? backgroundColor;
  PlayerExpansionState(this.progress, this.backgroundColor);
}
final playerExpansionNotifier = ValueNotifier<PlayerExpansionState>(PlayerExpansionState(0.0, null));

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

  /// Get the current expansion progress (0.0 to 1.0)
  static double get expansionProgress =>
      globalPlayerKey.currentState?.expansionProgress ?? 0.0;

  /// Get the current expanded background color
  static Color? get expandedBackgroundColor =>
      globalPlayerKey.currentState?.currentExpandedBgColor;

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        // Add bottom padding to account for bottom nav + mini player
        Padding(
          padding: const EdgeInsets.only(bottom: 0), // Content manages its own padding
          child: widget.child,
        ),
        // Global persistent bottom navigation bar - positioned at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ListenableBuilder(
            listenable: navigationProvider,
            builder: (context, _) {
              return Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  // Use adaptive primary color for bottom nav when adaptive theme is enabled
                  var navSelectedColor = themeProvider.adaptiveTheme
                      ? themeProvider.adaptivePrimaryColor
                      : colorScheme.primary;

                  // Ensure nav color has sufficient contrast against the surface background
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  if (isDark && navSelectedColor.computeLuminance() < 0.2) {
                    final hsl = HSLColor.fromColor(navSelectedColor);
                    navSelectedColor = hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.8)).toColor();
                  } else if (!isDark && navSelectedColor.computeLuminance() > 0.8) {
                    final hsl = HSLColor.fromColor(navSelectedColor);
                    navSelectedColor = hsl.withLightness((hsl.lightness - 0.3).clamp(0.2, 1.0)).toColor();
                  }

                  return ValueListenableBuilder<PlayerExpansionState>(
                    valueListenable: playerExpansionNotifier,
                    builder: (context, expansionState, child) {
                      // Base background: use adaptive surface color if available, otherwise default surface
                      final baseBgColor = (themeProvider.adaptiveTheme && themeProvider.adaptiveSurfaceColor != null)
                          ? themeProvider.adaptiveSurfaceColor!
                          : colorScheme.surface;

                      // Lerp between base color and player background when expanded
                      final navBgColor = expansionState.progress > 0 && expansionState.backgroundColor != null
                          ? Color.lerp(baseBgColor, expansionState.backgroundColor, expansionState.progress)!
                          : baseBgColor;

                      return Container(
                        decoration: BoxDecoration(
                          color: navBgColor,
                          boxShadow: expansionState.progress < 0.5
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, -2),
                                  ),
                                ]
                              : null,
                        ),
                        child: BottomNavigationBar(
                          currentIndex: navigationProvider.selectedIndex,
                          onTap: (index) {
                            // Collapse player if expanded
                            if (GlobalPlayerOverlay.isPlayerExpanded) {
                              GlobalPlayerOverlay.collapsePlayer();
                            }

                            // Pop any pushed routes (album/artist details) first
                            navigationProvider.navigatorKey.currentState?.popUntil((route) => route.isFirst);

                            // Hide mini player on Settings screen, show on other screens
                            if (index == 3) {
                              GlobalPlayerOverlay.hidePlayer();
                            } else if (navigationProvider.selectedIndex == 3) {
                              GlobalPlayerOverlay.showPlayer();
                            }

                            navigationProvider.setSelectedIndex(index);
                          },
                          backgroundColor: Colors.transparent,
                          selectedItemColor: navSelectedColor,
                          unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                          elevation: 0,
                          type: BottomNavigationBarType.fixed,
                          selectedFontSize: 12,
                          unselectedFontSize: 12,
                          items: const [
                            BottomNavigationBarItem(
                              icon: Icon(Icons.home_outlined),
                              activeIcon: Icon(Icons.home_rounded),
                              label: 'Home',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(Icons.library_music_outlined),
                              activeIcon: Icon(Icons.library_music_rounded),
                              label: 'Library',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(Icons.search_rounded),
                              activeIcon: Icon(Icons.search_rounded),
                              label: 'Search',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(Icons.settings_outlined),
                              activeIcon: Icon(Icons.settings_rounded),
                              label: 'Settings',
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        // Global player overlay - slides down when hidden, renders ON TOP of bottom nav
        AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            return Consumer<MusicAssistantProvider>(
              builder: (context, maProvider, _) {
                // Only show player if connected and has a track
                if (!maProvider.isConnected ||
                    maProvider.currentTrack == null ||
                    maProvider.selectedPlayer == null) {
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
      ],
    );
  }
}
