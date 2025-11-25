import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class PaletteHelper {
  /// Extract a color palette from an image
  static Future<PaletteGenerator?> extractPalette(ImageProvider imageProvider) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 20,
      );
      return palette;
    } catch (e) {
      print('⚠️ Failed to extract palette: $e');
      return null;
    }
  }

  /// Generate color schemes from a palette
  static (ColorScheme, ColorScheme)? generateColorSchemes(PaletteGenerator? palette) {
    if (palette == null) return null;

    // Get the dominant color as the seed color
    Color seedColor = palette.dominantColor?.color ??
                     palette.vibrantColor?.color ??
                     palette.mutedColor?.color ??
                     const Color(0xFF604CEC); // Fallback to brand color

    // Generate light and dark color schemes from the seed color
    final lightScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    final darkScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      // Use darker background colors for better contrast
      surface: const Color(0xFF2a2a2a),
      background: const Color(0xFF1a1a1a),
    );

    return (lightScheme, darkScheme);
  }

  /// Extract color schemes from an image provider in one call
  static Future<(ColorScheme, ColorScheme)?> extractColorSchemes(ImageProvider imageProvider) async {
    final palette = await extractPalette(imageProvider);
    return generateColorSchemes(palette);
  }

  /// Get primary color for use in UI elements
  static Color? getPrimaryColor(PaletteGenerator? palette) {
    if (palette == null) return null;

    return palette.vibrantColor?.color ??
           palette.dominantColor?.color ??
           palette.lightVibrantColor?.color;
  }

  /// Get background color for use in UI
  static Color? getBackgroundColor(PaletteGenerator? palette, {required bool isDark}) {
    if (palette == null) return null;

    if (isDark) {
      return palette.darkMutedColor?.color ??
             palette.mutedColor?.color?.withOpacity(0.3) ??
             const Color(0xFF1a1a1a);
    } else {
      return palette.lightMutedColor?.color ??
             palette.mutedColor?.color?.withOpacity(0.9) ??
             Colors.white;
    }
  }
}
