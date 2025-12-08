import 'package:flutter/material.dart';

/// A reusable widget for displaying disconnected/offline state.
class DisconnectedState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final double iconSize;

  const DisconnectedState({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.iconSize = 64,
  });

  /// Simple disconnected state without action button
  factory DisconnectedState.simple() => const DisconnectedState(
        title: 'Not connected to Music Assistant',
      );

  /// Disconnected state with settings button for navigation
  factory DisconnectedState.withSettingsAction({
    required VoidCallback onSettings,
  }) =>
      DisconnectedState(
        title: 'Not connected to Music Assistant',
        actionLabel: 'Configure Server',
        actionIcon: Icons.settings_rounded,
        onAction: onSettings,
      );

  /// Full disconnected state with title, subtitle, and action (for home screen)
  factory DisconnectedState.full({
    required VoidCallback onSettings,
  }) =>
      DisconnectedState(
        title: 'Not Connected',
        subtitle: 'Connect to your Music Assistant server to start listening',
        actionLabel: 'Configure Server',
        actionIcon: Icons.settings_rounded,
        onAction: onSettings,
        iconSize: 80,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: iconSize,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            SizedBox(height: iconSize > 64 ? 24 : 16),
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(subtitle != null ? 1.0 : 0.7),
                fontSize: subtitle != null ? 24 : 16,
                fontWeight: subtitle != null ? FontWeight.w300 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: subtitle != null ? 32 : 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: actionIcon != null ? Icon(actionIcon) : const SizedBox.shrink(),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: subtitle != null ? 32 : 24,
                    vertical: subtitle != null ? 16 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
