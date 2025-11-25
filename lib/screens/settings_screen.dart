import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../theme/theme_provider.dart';
import '../utils/layout_debug.dart';
import 'debug_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// ... (rest of state class until build) ...

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // ... (existing scaffold params) ...
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ... (existing settings widgets: connection, server url, port, connect button, theme section, debug logs button) ...
            
            // (I will match the surrounding context in the replace call to insert at the end)
            
            // ...
            
            const SizedBox(height: 32),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Connection Info',
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Default ports: 443 for HTTPS, 8095 for HTTP\n'
                    '• You can override the port in the WebSocket Port field\n'
                    '• Use domain name or IP address for server\n'
                    '• Make sure your device can reach the server\n'
                    '• Check debug logs if connection fails',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
        return Icons.check_circle_rounded;
      case MAConnectionState.connecting:
        return Icons.sync_rounded;
      case MAConnectionState.error:
        return Icons.error_rounded;
      case MAConnectionState.disconnected:
        return Icons.cloud_off_rounded;
    }
  }

  Color _getStatusColor(MAConnectionState state, ColorScheme colorScheme) {
    switch (state) {
      case MAConnectionState.connected:
        return Colors.green; // Keep green for success
      case MAConnectionState.connecting:
        return Colors.orange; // Keep orange for pending
      case MAConnectionState.error:
        return colorScheme.error;
      case MAConnectionState.disconnected:
        return colorScheme.onSurface.withOpacity(0.5);
    }
  }

  String _getStatusText(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
        return 'Connected';
      case MAConnectionState.connecting:
        return 'Connecting...';
      case MAConnectionState.error:
        return 'Connection Error';
      case MAConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}
