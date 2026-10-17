import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors (Apple Action Blue & System Palette)
  static const Color brandPrimary = Color(0xFF0066CC); // Apple Action Blue (#0066cc)
  static const Color brandDark = Color(0xFF004499);    // Deeper Focus Navy
  static const Color brandLight = Color(0xFFEBF5FF);   // Ultra-light Apple Blue tint
  static const Color brandAccent = Color(0xFF0071E3);  // Apple Bright Interactive Blue

  // Surface & Canvas (Apple Design Canvas & Ink)
  static const Color background = Color(0xFFF5F5F7);   // Apple Canvas Parchment (#f5f5f7)
  static const Color surface = Colors.white;           // Pure Canvas White
  static const Color slateDark = Color(0xFF1D1D1F);    // Apple System Ink (#1d1d1f)
  static const Color slateCard = Color(0xFF272729);    // Apple Dark Surface Tile
  static const Color slateMuted = Color(0xFF86868B);   // Apple System Gray (#86868b)
  static const Color slateBorder = Color(0xFFE5E5EA);  // Apple System Hairline/Divider

  // Hotel Status Colors (Clean Apple System Accents)
  static const Color statusVacant = Color(0xFF34C759); // Apple System Green
  static const Color statusVacantBg = Color(0xFFE8F9ED);
  static const Color statusOccupied = Color(0xFF0066CC); // Apple System Blue
  static const Color statusOccupiedBg = Color(0xFFEBF5FF);
  static const Color statusCleaning = Color(0xFFFF9500); // Apple System Amber / Orange
  static const Color statusCleaningBg = Color(0xFFFFF7ED);
  static const Color statusReserved = Color(0xFF5AC8FA); // Apple System Teal / Sky
  static const Color statusReservedBg = Color(0xFFF0F9FF);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: brandPrimary,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandPrimary,
        primary: brandPrimary,
        secondary: statusOccupied,
        surface: surface,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.inter(fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.inter(fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600),
      ),
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: brandPrimary.withValues(alpha: 0.08),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: Colors.black45,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: slateDark,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: slateBorder, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.outfit(
          color: slateDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: slateDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: slateDark,
          side: const BorderSide(color: slateBorder),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}
