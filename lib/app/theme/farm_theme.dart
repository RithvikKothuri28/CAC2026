import 'package:flutter/material.dart';

abstract final class FarmTheme {
  static const forest = Color(0xFF234C3D);
  static const moss = Color(0xFF738950);
  static const cream = Color(0xFFF6F5EF);
  static const ink = Color(0xFF24372E);
  static const muted = Color(0xFF69756B);
  static const line = Color(0xFFE0E4DA);
  static const amber = Color(0xFFB67D36);
  static const danger = Color(0xFFAB4539);
  static const gap = 20.0;
  static const radius = 18.0;
  static const wide = 1050.0;
  static const tablet = 720.0;
  static const cropColors = [
    Color(0xFF82965D),
    Color(0xFFD1B969),
    Color(0xFF5F8C83),
    Color(0xFFAF896A),
    Color(0xFF8899AB),
    Color(0xFFA090B0),
    Color(0xFFCB927F),
    Color(0xFF97AE87),
  ];

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: forest,
      surface: cream,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: cream,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: cream,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: forest,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -.7,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, color: ink, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}
