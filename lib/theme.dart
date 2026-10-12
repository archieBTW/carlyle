import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AccentOption {
  final String name;
  final Color color;

  const AccentOption({required this.name, required this.color});
}

class AppTheme {
  static const Color defaultPrimaryColor = Color(0xFF00E5FF); // Neon cyan
  static const Color defaultAccentColor = Color(0xFFFF007F); // Neon pink
  
  static const Color darkBackground = Color(0xFF0D0E11);
  static const Color darkSurface = Color(0xFF16181D);
  static const Color darkCard = Color(0xFF1E2129);

  static const Color lightBackground = Color(0xFFF4F6F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);

  // Preset options for accent colors
  static const List<AccentOption> accentPresets = [
    AccentOption(name: 'Neon Cyan', color: Color(0xFF00E5FF)),
    AccentOption(name: 'Cyber Pink', color: Color(0xFFFF007F)),
    AccentOption(name: 'Electric Orange', color: Color(0xFFFF6D00)),
    AccentOption(name: 'Hyper Green', color: Color(0xFF00E676)),
    AccentOption(name: 'Acid Purple', color: Color(0xFFD500F9)),
    AccentOption(name: 'Turbo Blue', color: Color(0xFF2979FF)),
    AccentOption(name: 'Apex Gold', color: Color(0xFFFFD600)),
    AccentOption(name: 'Redline Crimson', color: Color(0xFFFF1744)),
  ];

  static bool get _isTesting => Platform.environment.containsKey('FLUTTER_TEST');

  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    if (_isTesting) {
      return base;
    }

    final isDark = brightness == Brightness.dark;
    return GoogleFonts.outfitTextTheme(base).copyWith(
      displayLarge: GoogleFonts.outfit(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : const Color(0xFF11141A),
      ),
      displayMedium: GoogleFonts.outfit(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : const Color(0xFF11141A),
      ),
      titleLarge: GoogleFonts.outfit(
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : const Color(0xFF11141A),
      ),
      bodyLarge: GoogleFonts.inter(
        color: isDark ? Colors.white : const Color(0xFF2D3139),
      ),
      bodyMedium: GoogleFonts.inter(
        color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF5E6573),
      ),
    );
  }

  static ThemeData buildDarkTheme({Color? accentColor}) {
    final accent = accentColor ?? defaultPrimaryColor;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: accent,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: darkSurface,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _isTesting
            ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)
            : GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: _isTesting
              ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
              : GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        floatingLabelStyle: TextStyle(color: accent),
      ),
    );
  }

  static ThemeData buildLightTheme({Color? accentColor}) {
    final accent = accentColor ?? const Color(0xFF007AFF);
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      primaryColor: accent,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: accent,
        surface: lightSurface,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _isTesting
            ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF11141A))
            : GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: const Color(0xFF11141A)),
        iconTheme: const IconThemeData(color: Color(0xFF11141A)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: _isTesting
              ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
              : GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        labelStyle: const TextStyle(color: Color(0xFF5E6573)),
      ),
    );
  }

  // Deprecated backward-compatible getter
  static ThemeData get darkTheme => buildDarkTheme();
}
