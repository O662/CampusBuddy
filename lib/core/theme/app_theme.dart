import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// App-wide theme. Surfaces are intentionally transparent so the animated
/// gradient background shows through frosted glass panels.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.outfitTextTheme(base.textTheme).apply(
      bodyColor: AppPalette.textPrimary,
      displayColor: AppPalette.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppPalette.accent,
        secondary: AppPalette.mint,
        surface: AppPalette.scaffoldBase,
        onPrimary: const Color(0xFF14122B),
        onSurface: AppPalette.textPrimary,
        error: AppPalette.danger,
      ),
      splashFactory: InkSparkle.splashFactory,
      dividerColor: AppPalette.glassStroke,
      iconTheme: const IconThemeData(color: AppPalette.textSecondary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xCC241F45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppPalette.textPrimary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.accent,
          foregroundColor: const Color(0xFF14122B),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppPalette.lavender),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.glassFill,
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppPalette.textFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.glassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.accent, width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.glassStroke),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xE6261F47),
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xF21E1A3C)),
    );
  }
}
