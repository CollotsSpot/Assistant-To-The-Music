import 'package:flutter/material.dart';
import '../widgets/mini_player.dart';
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
  late PageController _pageController;
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;

        setState(() {
          _selectedIndex = 0;
          _pageController.jumpToPage(0);
        });
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(), // Disable swipe navigation
          onPageChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          children: [
            const NewHomeScreen(),
            const NewLibraryScreen(),
            SearchScreen(key: _searchScreenKey),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini player
            const MiniPlayer(),

            // Bottom navigation bar
            Container(
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
                  if (_selectedIndex == index) return;

                  setState(() {
                    _selectedIndex = index;
                  });

                  _pageController.jumpToPage(index);

                  // Request focus on search field when switching to search tab
                  if (index == 2) {
                    Future.delayed(const Duration(milliseconds: 100), () {
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
          ],
        ),
      ),
    );
  }
}
