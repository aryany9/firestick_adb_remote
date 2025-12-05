import 'package:flutter/material.dart';

/// Google Material 3 inspired theme for Firestick ADB Remote
/// Uses a modern, clean color palette with proper accessibility
class AppTheme {
  // Primary colors inspired by Google's design system
  static const Color _primaryLight = Color(0xFF1F4788); // Deep Blue
  static const Color _primaryDark = Color(0xFFB3E5FC); // Light Blue

  static const Color _secondaryLight = Color(0xFF546E7A); // Blue Grey
  static const Color _secondaryDark = Color(0xFFCFD8DC); // Light Blue Grey

  static const Color _tertiaryLight = Color(0xFF0097A7); // Cyan
  static const Color _tertiaryDark = Color(0xFF80DEEA); // Light Cyan

  // ============================================================================
  // Light Theme
  // ============================================================================
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _primaryLight,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD6E4FF),
        onPrimaryContainer: Color(0xFF001056),
        secondary: _secondaryLight,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFCFD8DC),
        onSecondaryContainer: Color(0xFF0D1B22),
        tertiary: _tertiaryLight,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFB2EBFA),
        onTertiaryContainer: Color(0xFF001F28),
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFF9DEDC),
        onErrorContainer: Color(0xFF410E0B),
        outline: Color(0xFF79747E),
        outlineVariant: Color(0xFFCAC7D0),
        surface: Color(0xFFFAFAFA),
        onSurface: Color(0xFF1C1B1F),
        surfaceVariant: Color(0xFFEAE7F0),
        onSurfaceVariant: Color(0xFF49454E),
        inverseSurface: Color(0xFF313033),
        onInverseSurface: Color(0xFFF5EFF7),
        inversePrimary: _primaryDark,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,

      // AppBar Theme
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 1,
        backgroundColor: _primaryLight,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        surfaceTintColor: _primaryLight,
      ),

      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: _primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Filled Button Theme
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: _primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Field Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCAC7D0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCAC7D0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryLight, width: 2),
        ),
        labelStyle: const TextStyle(color: _secondaryLight),
        hintStyle: const TextStyle(color: Color(0xFF79747E)),
      ),

      // Switch Theme
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _primaryLight;
          }
          return Color(0xFFF5F5F5);
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _primaryLight.withOpacity(0.3);
          }
          return Color(0xFFE0E0E0);
        }),
      ),

      // ListTile Theme
      listTileTheme: ListTileThemeData(
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: Colors.black.withOpacity(0.6),
          fontSize: 14,
        ),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(color: _primaryLight, size: 24),

      // Text Themes
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1C1B1F),
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1B1F),
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1B1F),
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Color(0xFF1C1B1F),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF1C1B1F),
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF49454E),
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1B1F),
        ),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: Color(0xFFCAC7D0),
        thickness: 1,
        space: 16,
      ),
    );
  }

  // ============================================================================
  // Dark Theme (optional, for future use)
  // ============================================================================
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _primaryDark,
        onPrimary: Color(0xFF001056),
        primaryContainer: Color(0xFF0D47A1),
        onPrimaryContainer: Color(0xFFD6E4FF),
        secondary: _secondaryDark,
        onSecondary: Color(0xFF0D1B22),
        secondaryContainer: Color(0xFF375962),
        onSecondaryContainer: Color(0xFFCFD8DC),
        tertiary: _tertiaryDark,
        onTertiary: Color(0xFF001F28),
        tertiaryContainer: Color(0xFF00495F),
        onTertiaryContainer: Color(0xFFB2EBFA),
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF601410),
        errorContainer: Color(0xFF8C1C1A),
        onErrorContainer: Color(0xFFF9DEDC),
        outline: Color(0xFF938F99),
        outlineVariant: Color(0xFF49454E),
        surface: Color(0xFF1C1B1F),
        onSurface: Color(0xFFE6E1E6),
        surfaceVariant: Color(0xFF49454E),
        onSurfaceVariant: Color(0xFFCAC7D0),
        inverseSurface: Color(0xFFE6E1E6),
        onInverseSurface: Color(0xFF313033),
        inversePrimary: _primaryLight,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      scaffoldBackgroundColor: Color(0xFF1C1B1F),
      appBarTheme: AppBarTheme(
        elevation: 1,
        backgroundColor: Color(0xFF1F1B24),
        foregroundColor: _primaryDark,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Color(0xFF2A2730),
      ),
    );
  }
}
