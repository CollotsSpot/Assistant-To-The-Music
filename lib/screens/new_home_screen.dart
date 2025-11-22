import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/library_stats.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatelessWidget {
  const NewHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Music Assistant',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchScreen(),
                ),
              );
            },
          ),
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: !maProvider.isConnected
            ? _buildDisconnectedView(context, maProvider)
            : _buildConnectedView(context, maProvider),
      ),
    );
  }

  Widget _buildDisconnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 80,
              color: Colors.white54,
            ),
            const SizedBox(height: 24),
            const Text(
              'Not Connected',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Connect to your Music Assistant server to start listening',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Configure Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1a1a1a),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Welcome message
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Welcome',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Discover your music',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Library stats
          LibraryStats(
            loadStats: () async {
              if (provider.api == null) {
                return {'artists': 0, 'albums': 0, 'tracks': 0};
              }
              return await provider.api!.getLibraryStats();
            },
          ),
          const SizedBox(height: 24),

          // Recently played albums
          AlbumRow(
            title: 'Recently Played',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRecentAlbums(limit: 10);
            },
          ),
          const SizedBox(height: 16),

          // Random albums
          AlbumRow(
            title: 'Discover',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRandomAlbums(limit: 10);
            },
          ),
          const SizedBox(height: 16),

          // All albums
          AlbumRow(
            title: 'Albums',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getAlbums(limit: 20);
            },
          ),
          const SizedBox(height: 80), // Space for mini player
        ],
      ),
    );
  }
}
