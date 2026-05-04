import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF020E21);
  static const Color primarySpark = Color(0xFFFFE816);
  static const Color secondaryCian = Color(0xFF00D9F7);
  static const Color borderBlue = Color(0xFF0043AA);
  static const Color white = Color(0xFFFFFFFF);
  static const Color textDisabled = Color(0x33FFFFFF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primarySpark,
        background: AppColors.background,
        primary: AppColors.primarySpark,
        secondary: AppColors.secondaryCian,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.white,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          color: AppColors.white,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.white,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppColors.secondaryCian,
        ),
      ),
    );
  }
}
