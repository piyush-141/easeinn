import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color brandPrimary = Color(0xFF6D28D9); // Rich Violet
  static const Color brandDark = Color(0xFF4C1D95);
  static const Color brandLight = Color(0xFFEDE9FE);
  static const Color brandAccent = Color(0xFF8B5CF6);

  // Surface & Slate
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color slateDark = Color(0xFF0F172A);
  static const Color slateCard = Color(0xFF1E293B);
  static const Color slateMuted = Color(0xFF64748B);
  static const Color slateBorder = Color(0xFFE2E8F0);

  // Hotel Status Colors
  static const Color statusVacant = Color(0xFF10B981); // Emerald
  static const Color statusVacantBg = Color(0xFFECFDF5);
  static const Color statusOccupied = Color(0xFF6366F1); // Indigo
  static const Color statusOccupiedBg = Color(0xFFEEF2FF);
  static const Color statusCleaning = Color(0xFFF59E0B); // Amber
  static const Color statusCleaningBg = Color(0xFFFEF3C7);
  static const Color statusReserved = Color(0xFF0EA5E9); // Sky
  static const Color statusReservedBg = Color(0xFFE0F2FE);

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
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700),
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
