import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF17365D);
  static const teal = Color(0xFF16A6A0);
  static const emerald = Color(0xFF24B47E);
  static const amber = Color(0xFFE2AD4F);
  static const danger = Color(0xFFE05B62);
  static const darkBackground = Color(0xFF10191E);
  static const darkSurface = Color(0xFF1B292F);
  static const darkCard = Color(0xFF22333A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
      primary: navy,
      secondary: teal,
      surface: const Color(0xFFFFFFFF),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Color(0xFFF5F7FA),
        foregroundColor: navy,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE4E9EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: teal, width: 1.4),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF65D4CC),
      onPrimary: Color(0xFF003735),
      secondary: Color(0xFF8EC9F2),
      onSecondary: Color(0xFF062D42),
      error: Color(0xFFFF8A8A),
      onError: Color(0xFF4A0000),
      surface: darkSurface,
      onSurface: Color(0xFFEAF2F4),
      onSurfaceVariant: Color(0xFFB3C2C7),
      outline: Color(0xFF42545B),
      outlineVariant: Color(0xFF314249),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFEAF2F4),
      onInverseSurface: darkBackground,
      inversePrimary: Color(0xFF087E8B),
      surfaceTint: Color(0xFF65D4CC),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF30434A)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: darkBackground,
        foregroundColor: Color(0xFFEAF2F4),
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: const Color(0xFF285B5B),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? const Color(0xFF65D4CC)
                : const Color(0xFFB3C2C7),
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF17252B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF35484F)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF35484F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF65D4CC), width: 1.4),
        ),
      ),
      dividerColor: const Color(0xFF34464D),
    );
  }
}
