import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Colors & Gradient
  static const Color primary = Color(0xFF00B4D8);
  static const Color primaryDark = Color(0xFF0096C7);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Background & Surfaces
  static const Color background = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color toggleBackground = Color(0xFFF5F7FA);
  static const Color inputFill = Color(0xFFFAFAFA);
  static const Color lightCyanTint = Color(0xFFEAFAFD);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textWhite = Color(0xFFFFFFFF);

  // Borders & Errors
  static const Color border = Color(0xFFEAEAFA);
  static const Color focusedBorder = Color(0xFF00B4D8);
  static const Color errorBorder = Color(0xFFE63946);
  static const Color errorText = Color(0xFFE63946);

  // SnackBar / Dark Surfaces
  static const Color snackBarBackground = Color(0xFF1A1A1A);
}
