import 'package:flutter/material.dart';

class StudioTheme {
  // Primary dark canvas colors
  static const Color background = Color(0xFF030712); // Deep midnight black-blue
  static const Color surface = Color(0xFF0B132B); // Deep navy container
  static const Color surfaceVariant = Color(0xFF131D3F); // Elevated navy card
  static const Color surfaceElevated = Color(0xFF1C274C); // Highlighted card

  // Neon & Accent Colors matching UI reference
  static const Color cyanAccent = Color(0xFF00E5FF); // Neon cyan
  static const Color neonCyan = cyanAccent;
  static const Color cyanGlow = Color(0xFF00B4D8);
  static const Color purpleAccent = Color(0xFF7928CA); // Electric violet/purple
  static const Color magentaGlow = Color(0xFFFF0080);
  static const Color goldAccent = Color(0xFFFFB703); // Royal cinematic gold
  static const Color accentGold = goldAccent;
  static const Color goldLight = Color(0xFFFFD166);

  // Border & divider colors
  static const Color borderCyan = Color(0xFF00E5FF);
  static const Color borderSubtle = Color(0xFF1F2E55);
  static const Color borderCard = Color(0xFF22315B);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF7928CA)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD166), Color(0xFFFF9E00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF0D1836), Color(0xFF091024)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonCyanPurple = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF8A2BE2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient buttonGold = LinearGradient(
    colors: [Color(0xFF241E15), Color(0xFF15141E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Box Shadows & Glows
  static List<BoxShadow> cyanGlowShadow({double blur = 12, double spread = 0}) => [
        BoxShadow(
          color: cyanAccent.withValues(alpha: 0.35),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];

  static List<BoxShadow> purpleGlowShadow({double blur = 12}) => [
        BoxShadow(
          color: purpleAccent.withValues(alpha: 0.40),
          blurRadius: blur,
        ),
      ];

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: cyanAccent,
      fontFamily: 'KantumruyPro',
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: purpleAccent,
        surface: surface,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderCard, width: 1.2),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
