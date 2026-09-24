import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryColor = Color(0xFF1B5E20);      // Deep Green (Islamic)
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF0D3B12);
  static const Color accentColor = Color(0xFFD4AF37);        // Gold
  static const Color accentLight = Color(0xFFE6C85A);
  
  static bool isUrdu = false;

  static TextStyle getFontStyle({double? fontSize, FontWeight? fontWeight, Color? color, double? letterSpacing, double? height, TextDecoration? decoration}) {
    final double scale = isUrdu ? 1.25 : 1.15;
    final double? adjustedSize = fontSize != null ? fontSize * scale : null;

    if (isUrdu) {
      return TextStyle(
        fontFamily: 'JameelNooriNastaleeq',
        fontSize: adjustedSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height ?? 1.3,
        decoration: decoration,
      );
    }
    return GoogleFonts.outfit(
      fontSize: adjustedSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    ).copyWith(fontFamilyFallback: const ['JameelNooriNastaleeq']);
  }
  
  // Semantic Colors
  static const Color successColor = Color(0xFF2E7D32);
  static const Color warningColor = Color(0xFFF57F17);
  static const Color errorColor = Color(0xFFC62828);
  static const Color infoColor = Color(0xFF1565C0);

  static TextStyle _getTextStyle(String? fontFamily, {double? fontSize, FontWeight? fontWeight, Color? color}) {
    final double scale = isUrdu ? 1.25 : 1.15;
    final double? adjustedSize = fontSize != null ? fontSize * scale : null;

    if (fontFamily != null) {
      return TextStyle(
        fontFamily: fontFamily, 
        fontSize: adjustedSize, 
        fontWeight: fontWeight, 
        color: color,
        height: fontFamily == 'JameelNooriNastaleeq' ? 1.3 : null,
        fontFamilyFallback: const ['JameelNooriNastaleeq'],
      );
    }
    return GoogleFonts.outfit(
      fontSize: adjustedSize, 
      fontWeight: fontWeight, 
      color: color,
    ).copyWith(fontFamilyFallback: const ['JameelNooriNastaleeq']);
  }

  // ─── Light Theme ──────────────────────────────────────────
  static ThemeData lightTheme([String? fontFamily]) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      fontFamily: fontFamily ?? GoogleFonts.outfit().fontFamily,
      textTheme: _textTheme(Brightness.light, fontFamily),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        titleTextStyle: _getTextStyle(
          fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1A2E),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: _getTextStyle(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: primaryColor),
          textStyle: _getTextStyle(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F2F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: _getTextStyle(fontFamily, color: Colors.grey.shade600),
        hintStyle: _getTextStyle(fontFamily, color: Colors.grey.shade400),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: const IconThemeData(color: primaryColor),
        unselectedIconTheme: IconThemeData(color: Colors.grey.shade500),
        indicatorColor: primaryColor.withAlpha(30),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
    );
  }

  // ─── Dark Theme ───────────────────────────────────────────
  static ThemeData darkTheme([String? fontFamily]) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: primaryColor,
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      fontFamily: fontFamily ?? GoogleFonts.outfit().fontFamily,
      textTheme: _textTheme(Brightness.dark, fontFamily),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: const Color(0xFF161625),
        foregroundColor: Colors.white,
        titleTextStyle: _getTextStyle(
          fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withAlpha(15)),
        ),
        color: const Color(0xFF1A1A2E),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          textStyle: _getTextStyle(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: primaryLight),
          textStyle: _getTextStyle(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E32),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: _getTextStyle(fontFamily, color: Colors.grey.shade400),
        hintStyle: _getTextStyle(fontFamily, color: Colors.grey.shade600),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF161625),
        selectedIconTheme: const IconThemeData(color: primaryLight),
        unselectedIconTheme: IconThemeData(color: Colors.grey.shade600),
        indicatorColor: primaryLight.withAlpha(30),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Color(0xFF161625),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withAlpha(15),
        thickness: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryLight,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
    );
  }

  // ─── Text Theme ───────────────────────────────────────────
  static TextTheme _textTheme(Brightness brightness, String? fontFamily) {
    final color = brightness == Brightness.light
        ? const Color(0xFF1A1A2E)
        : Colors.white;

    return TextTheme(
      displayLarge: _getTextStyle(fontFamily, fontSize: 32, fontWeight: FontWeight.w700, color: color),
      displayMedium: _getTextStyle(fontFamily, fontSize: 28, fontWeight: FontWeight.w700, color: color),
      displaySmall: _getTextStyle(fontFamily, fontSize: 24, fontWeight: FontWeight.w600, color: color),
      headlineLarge: _getTextStyle(fontFamily, fontSize: 22, fontWeight: FontWeight.w600, color: color),
      headlineMedium: _getTextStyle(fontFamily, fontSize: 20, fontWeight: FontWeight.w600, color: color),
      headlineSmall: _getTextStyle(fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleLarge: _getTextStyle(fontFamily, fontSize: 16, fontWeight: FontWeight.w600, color: color),
      titleMedium: _getTextStyle(fontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: color),
      titleSmall: _getTextStyle(fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: color),
      bodyLarge: _getTextStyle(fontFamily, fontSize: 16, fontWeight: FontWeight.w400, color: color),
      bodyMedium: _getTextStyle(fontFamily, fontSize: 14, fontWeight: FontWeight.w400, color: color),
      bodySmall: _getTextStyle(fontFamily, fontSize: 12, fontWeight: FontWeight.w400, color: color.withAlpha(180)),
      labelLarge: _getTextStyle(fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: color),
      labelMedium: _getTextStyle(fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: color),
      labelSmall: _getTextStyle(fontFamily, fontSize: 10, fontWeight: FontWeight.w500, color: color.withAlpha(180)),
    );
  }
}
