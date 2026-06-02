import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

class ThemeController extends ChangeNotifier {
  static const String _themePaletteKey = 'encline_theme_palette';
  String _currentThemeName = 'techBlue';

  String get currentThemeName => _currentThemeName;

  ThemeController() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themePaletteKey) ?? 'techBlue';
    _applyTheme(savedTheme);
  }

  void setTheme(String name) {
    if (_currentThemeName == name) return;
    _applyTheme(name);
    _saveTheme(name);
  }

  void _applyTheme(String name) {
    _currentThemeName = name;
    final palette = AppPalettes.getByName(name);

    // Apply properties to AppColors
    AppColors.background = palette.background;
    AppColors.surface = palette.surface;
    AppColors.surfaceLight = palette.surfaceLight;
    AppColors.primary = palette.primary;
    AppColors.secondary = palette.secondary;
    AppColors.accent = palette.accent;

    notifyListeners();
  }

  Future<void> _saveTheme(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePaletteKey, name);
  }
}
