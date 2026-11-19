import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Polices : Poppins pour les titres, Urbanist (proche de Gilroy) pour les textes.
class AppTheme {
  AppTheme._();

  static TextStyle title({double size = 20, FontWeight weight = FontWeight.w700, Color color = AppColors.white}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color, height: 1.2);

  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final body = GoogleFonts.urbanistTextTheme(base.textTheme).apply(bodyColor: AppColors.white, displayColor: AppColors.white);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.night,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.sunYellow,
        secondary: AppColors.sunOrange,
        surface: AppColors.navyDeep,
        onPrimary: AppColors.navy,
      ),
      textTheme: body.copyWith(
        headlineSmall: title(size: 22, weight: FontWeight.w800),
        titleLarge: title(size: 18, weight: FontWeight.w700),
        titleMedium: title(size: 15, weight: FontWeight.w600),
        bodyMedium: GoogleFonts.urbanist(fontSize: 14, color: AppColors.white),
        bodySmall: GoogleFonts.urbanist(fontSize: 12, color: AppColors.mist),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: title(size: 17),
        foregroundColor: AppColors.white,
      ),
      snackBarTheme: const SnackBarThemeData(backgroundColor: AppColors.navy, contentTextStyle: TextStyle(color: AppColors.white)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.sunYellow),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x800B1463),
        hintStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
