import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

class SystemThemeHelper {
  /// Attempts to get system color schemes from the device (Android 12+)
  /// Returns a tuple of (light, dark) ColorScheme if successful, null otherwise
  static Future<(ColorScheme, ColorScheme)?> getSystemColorSchemes() async {
    try {
      // Try to get dynamic color schemes from the system
      final corePalette = await DynamicColorPlugin.getCorePalette();

      if (corePalette != null) {
        // Generate color schemes from the core palette
        final lightScheme = corePalette.toColorScheme(brightness: Brightness.light);
        final darkScheme = corePalette.toColorScheme(brightness: Brightness.dark);

        return (lightScheme, darkScheme);
      } else {
        // Fallback: try to get just the accent color
        final accentColor = await DynamicColorPlugin.getAccentColor();

        if (accentColor != null) {
          // Generate color schemes from the accent color
          final lightScheme = ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.light,
          );

          final darkScheme = ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.dark,
          );

          return (lightScheme, darkScheme);
        }
      }
    } catch (e) {
      print('⚠️ Failed to get system colors: $e');
    }

    return null;
  }
}
