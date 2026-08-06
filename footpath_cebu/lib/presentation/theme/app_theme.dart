import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';

/// The app's youth-facing design system.
///
/// Brand colours live here so every screen stays on-theme: teal as the
/// primary brand colour, coral as the energetic accent for CTAs, streaks, and
/// "on fire" states. Type is Fredoka (display/headings, rounded and friendly)
/// over Nunito (body, highly legible for younger readers).
class AppColors {
  AppColors._();

  /// Primary brand colour — teal.
  static const teal = Color(0xFF1D9E75);
  static const tealLight = Color(0xFFE1F5EE);

  /// A darkened teal for small (normal-size) brand-coloured text on a light
  /// surface, where [teal] itself only reaches ~3.3:1 (fine for large text and
  /// non-text, short of the 4.5:1 AA minimum for body text). This clears AA at
  /// ~6.5:1 on white.
  static const tealDark = Color(0xFF0F6B4E);

  /// Accent brand colour — coral. CTAs, streaks, "on fire" states, badges.
  static const coral = Color(0xFFD85A30);
  static const coralLight = Color(0xFFFAECE7);

  /// FUT-style card tiers — literal medal colours, not brand identity, so
  /// these stay bronze/silver/gold regardless of the brand palette.
  static const bronze = Color(0xFFCD7F32);
  static const silver = Color(0xFFBFC7CF);
  static const gold = Color(0xFFE7C86A);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    // Secondary is left to auto-derive from the teal seed (a harmonious muted
    // teal tone) — the brand is a deliberate two-colour system, teal + coral,
    // not three.
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      primary: AppColors.teal,
      tertiary: AppColors.coral,
      brightness: Brightness.light,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.tealLight,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
    );

    // Fredoka for display/titles, Nunito for body — applied over the M3
    // baseline so sizes/weights stay sensible.
    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.fredoka(textStyle: base.textTheme.displayLarge),
      displayMedium: GoogleFonts.fredoka(
        textStyle: base.textTheme.displayMedium,
      ),
      displaySmall: GoogleFonts.fredoka(textStyle: base.textTheme.displaySmall),
      headlineLarge: GoogleFonts.fredoka(
        textStyle: base.textTheme.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.fredoka(
        textStyle: base.textTheme.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.fredoka(
        textStyle: base.textTheme.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.fredoka(
        textStyle: base.textTheme.titleLarge,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.fredoka(
        textStyle: base.textTheme.titleMedium,
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.teal,
        // White at 22px/w700 clears the WCAG large-text AA threshold (3:1)
        // against teal — verified 3.4:1. Smaller/lighter text on a solid
        // brand colour should use a dark foreground instead (see the button
        // themes below), not white.
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fredoka(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: AppColors.teal.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
          // White text at this size falls short of WCAG AA (measured ~3.4:1
          // on teal, ~3.9:1 on coral vs the 4.5:1 normal-text minimum) — a
          // dark foreground clears AA comfortably (~6:1 / ~5.4:1) on both.
          foregroundColor: Colors.black,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800),
          // Same AA reasoning as filledButtonTheme — the default M3 foreground
          // (colorScheme.primary, i.e. teal) only hits ~3.4:1 against a white
          // surface at this text size, short of the 4.5:1 minimum.
          foregroundColor: Colors.black,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}
