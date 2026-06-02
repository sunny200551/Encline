import 'package:flutter/material.dart';

class ThemePalette {
  final String name;
  final String displayName;
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color primary;
  final Color secondary;
  final Color accent;

  const ThemePalette({
    required this.name,
    required this.displayName,
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.primary,
    required this.secondary,
    required this.accent,
  });
}

class AppPalettes {
  static const ThemePalette techBlue = ThemePalette(
    name: 'techBlue',
    displayName: 'Tech Blue',
    background: Color(0xFF080C14),
    surface: Color(0xFF0F172A),
    surfaceLight: Color(0xFF1E293B),
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF06B6D4),
    accent: Color(0xFF8B5CF6),
  );

  static const ThemePalette nebulaPurple = ThemePalette(
    name: 'nebulaPurple',
    displayName: 'Nebula Purple',
    background: Color(0xFF0C0714),
    surface: Color(0xFF180F2A),
    surfaceLight: Color(0xFF291E3B),
    primary: Color(0xFF8B5CF6),
    secondary: Color(0xFFEC4899),
    accent: Color(0xFF3B82F6),
  );

  static const ThemePalette emeraldMatrix = ThemePalette(
    name: 'emeraldMatrix',
    displayName: 'Emerald Matrix',
    background: Color(0xFF050805),
    surface: Color(0xFF0B140B),
    surfaceLight: Color(0xFF172617),
    primary: Color(0xFF10B981),
    secondary: Color(0xFF34D399),
    accent: Color(0xFF3B82F6),
  );

  static const ThemePalette sunsetOrange = ThemePalette(
    name: 'sunsetOrange',
    displayName: 'Sunset Orange',
    background: Color(0xFF0F0B07),
    surface: Color(0xFF1C130B),
    surfaceLight: Color(0xFF2E2014),
    primary: Color(0xFFF97316),
    secondary: Color(0xFFF59E0B),
    accent: Color(0xFFEF4444),
  );

  static const ThemePalette stealthObsidian = ThemePalette(
    name: 'stealthObsidian',
    displayName: 'Stealth Obsidian',
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF171717),
    surfaceLight: Color(0xFF262626),
    primary: Color(0xFF94A3B8),
    secondary: Color(0xFFE2E8F0),
    accent: Color(0xFF64748B),
  );

  static const List<ThemePalette> all = [
    techBlue,
    nebulaPurple,
    emeraldMatrix,
    sunsetOrange,
    stealthObsidian,
  ];

  static ThemePalette getByName(String name) {
    return all.firstWhere((p) => p.name == name, orElse: () => techBlue);
  }
}

class AppColors {
  // Current values (mutated dynamically by ThemeController)
  static Color background = AppPalettes.techBlue.background;
  static Color surface = AppPalettes.techBlue.surface;
  static Color surfaceLight = AppPalettes.techBlue.surfaceLight;
  
  static Color primary = AppPalettes.techBlue.primary;
  static Color secondary = AppPalettes.techBlue.secondary;
  static Color accent = AppPalettes.techBlue.accent;
  
  // Static constants (stay same across themes)
  static const Color success = Color(0xFF10B981);      // Emerald Green
  static const Color warning = Color(0xFFF59E0B);      // Warning Gold
  static const Color error = Color(0xFFEF4444);        // Neon Red
  
  // Gradients
  static LinearGradient get primaryGradient => LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get accentGradient => LinearGradient(
    colors: [accent, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get warningGradient => LinearGradient(
    colors: [warning, error],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get darkCardGradient => LinearGradient(
    colors: [primary.withValues(alpha: 0.12), secondary.withValues(alpha: 0.02)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppGlow {
  static List<BoxShadow> get primaryGlow => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.3),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> get accentGlow => [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.3),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE2E8F0)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surfaceLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surfaceLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
    );
  }
}
