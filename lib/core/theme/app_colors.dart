import 'package:flutter/material.dart';

/// Charte du logo Conacce TV : bleu marine + soleil jaune → orange.
class AppColors {
  AppColors._();

  // Bleus (logo et fond à vagues)
  static const navy = Color(0xFF0B1463);       // gauche du logo
  static const navyDeep = Color(0xFF080F43);   // droite du logo
  static const night = Color(0xFF050A2E);      // bas des vagues
  static const royal = Color(0xFF0D2389);      // haut des vagues

  // Soleil du logo
  static const sunYellow = Color(0xFFF9CA22);
  static const sunGold = Color(0xFFF9B91B);
  static const sunMid = Color(0xFFFD9113);
  static const sunDeep = Color(0xFFFC6306);
  static const sunOrange = Color(0xFFFA5304);

  // Textes
  static const white = Colors.white;
  static const mist = Color(0xFFDCE3FF);
  static const muted = Color(0xFFAEB8E6);

  static const live = Color(0xFFE5002B);       // badge EN DIRECT

  /// Dégradé du soleil (boutons principaux, éléments actifs).
  static const sunGradient = LinearGradient(
    colors: [sunYellow, sunGold, sunMid, sunDeep, sunOrange],
    stops: [0, .3, .6, .85, 1],
  );

  /// Cartes : marine du logo, légèrement transparent pour se fondre dans les vagues.
  static const cardGradient = LinearGradient(
    begin: Alignment(-1, -.2),
    end: Alignment(1, .2),
    colors: [Color(0xB80B1463), Color(0x61080F43)],
  );
}
