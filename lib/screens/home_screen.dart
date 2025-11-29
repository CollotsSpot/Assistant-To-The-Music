import 'package:flutter/material.dart';
import '../widgets/expandable_player.dart';
import 'new_home_screen.dart';
import 'new_library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();
  final GlobalKey<ExpandablePlayerState> _playerKey = GlobalKey<ExpandablePlayerState>();
  DateTime? _lastBackPress;

  void _showExitSnackBar() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Press back again to exit'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // If player is expanded, collapse it first
        if (_playerKey.currentState?.isExpanded == true) {
          _playerKey.currentState?.collapse();
          return;
        }

        // If not on home tab, navigate to home
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }

        // On home tab - check for double press to exit
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          // Double press detected, allow exit
          Navigator.of(context).pop();
        } else {
          // First press, show message
          _lastBackPress = now;
          _showExitSnackBar();
        }
      },
      child: Stack(
        children: [
          // Main scaffold with bottom nav
          Scaffold(
            backgroundColor: colorScheme.background,
            body: Stack(
              children: [
                // Home and Library use IndexedStack for state preservation
                Offstage(
                  offstage: _selectedIndex > 1,
                  child: IndexedStack(
                    index: _selectedIndex.clamp(0, 1),
                    children: const [
                      NewHomeScreen(),
                      NewLibraryScreen(),
                    ],
                  ),
                ),
                // Search and Settings are conditionally rendered (removed from tree when not visible)
                if (_selectedIndex == 2)
                  SearchScreen(key: _searchScreenKey),
                if (_selectedIndex == 3)
                  const SettingsScreen(),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });

                  // Auto-focus search field when switching to search tab
                  if (index == 2) {
                    // Use post-frame callback to ensure SearchScreen is built first
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _searchScreenKey.currentState?.requestFocus();
                    });
                  }
                },
                backgroundColor: Colors.transparent,
                selectedItemColor: colorScheme.primary,
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
            ),
          ),
          // Expandable player overlay - on top of everything including bottom nav
          // Hidden on settings screen
          if (_selectedIndex != 3)
            ExpandablePlayer(key: _playerKey, hasBottomNav: true),
        ],
      ),
    );
  }
}
