import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useMaterialTheme = false;
  bool _adaptiveTheme = true;
  Color _customColor = const Color(0xFF604CEC);

  ThemeProvider() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  bool get useMaterialTheme => _useMaterialTheme;
  bool get adaptiveTheme => _adaptiveTheme;
  Color get customColor => _customColor;

  Future<void> _loadSettings() async {
    final themeModeString = await SettingsService.getThemeMode();
    _themeMode = _parseThemeMode(themeModeString);

    _useMaterialTheme = await SettingsService.getUseMaterialTheme();
    _adaptiveTheme = await SettingsService.getAdaptiveTheme();

    final colorString = await SettingsService.getCustomColor();
    if (colorString != null) {
      _customColor = _parseColor(colorString);
    }

    notifyListeners();
  }

  ThemeMode _parseThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Color _parseColor(String colorString) {
    try {
      // Remove # if present
      final hex = colorString.replaceAll('#', '');
      // Add FF for alpha if not present
      final hexWithAlpha = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(hexWithAlpha, radix: 16));
    } catch (e) {
      return const Color(0xFF604CEC); // Default color
    }
  }

  String _colorToString(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.saveThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setUseMaterialTheme(bool enabled) async {
    _useMaterialTheme = enabled;
    await SettingsService.saveUseMaterialTheme(enabled);
    notifyListeners();
  }

  Future<void> setAdaptiveTheme(bool enabled) async {
    _adaptiveTheme = enabled;
    await SettingsService.saveAdaptiveTheme(enabled);
    notifyListeners();
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await SettingsService.saveCustomColor(_colorToString(color));
    notifyListeners();
  }
}
