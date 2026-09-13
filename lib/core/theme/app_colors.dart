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

  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF00B4D8), Color(0xFF0096C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Background & Surfaces
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color toggleBackground = Color(0xFFF5F7FA);
  static const Color inputFill = Color(0xFFFAFAFA);
  static const Color lightCyanTint = Color(0xFFEAFAFD);

  // Chips
  static const Color chipInactiveBackground = Color(0xFFFFFFFF);
  static const Color chipInactiveBorder = Color(0xFFE2E8F0);
  static const Color chipActiveBackground = Color(0xFF00B4D8);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textWhite = Color(0xFFFFFFFF);

  // Borders & Errors
  static const Color border = Color(0xFFEAEAFA);
  static const Color subtleBorder = Color(0xFFF1F5F9);
  static const Color focusedBorder = Color(0xFF00B4D8);
  static const Color errorBorder = Color(0xFFE63946);
  static const Color errorText = Color(0xFFE63946);

  // Status Indicators & Badges
  static const Color statusPending = Color(0xFFFFB703);
  static const Color statusFailed = Color(0xFFE63946);
  static const Color statusProcessed = Color(0xFF00B4D8);
  static const Color notificationBadge = Color(0xFFEF4444);
  static const Color weatherSun = Color(0xFF00B4D8);
  static const Color iconSecondary = Color(0xFF64748B);

  // Unified Global Category Chip Colors (Cyan-Only System)
  static const Color categoryChipBackground = Color(0xFFEAFAFD);
  static const Color categoryChipBorder = Color(0xFFCCEBF5);
  static const Color categoryChipDarkCyan = Color(0xFF0096C7);
  static const Color categoryChipPrimaryCyan = Color(0xFF00B4D8);

  // Category Pill Colors - All unified to Cyan System (#EAFAFD bg, #CCEBF5 border, #0096C7 icon/text)
  static const Color categoryWorkIcon = Color(0xFF0096C7);
  static const Color categoryWorkBackground = Color(0xFFEAFAFD);
  static const Color categoryWorkBorder = Color(0xFFCCEBF5);
  static const Color categoryCyanText = Color(0xFF0096C7);

  static const Color categoryPersonalIcon = Color(0xFF0096C7);
  static const Color categoryPersonalBackground = Color(0xFFEAFAFD);
  static const Color categoryPersonalBorder = Color(0xFFCCEBF5);

  static const Color categoryStudyIcon = Color(0xFF0096C7);
  static const Color categoryStudyBackground = Color(0xFFEAFAFD);
  static const Color categoryStudyBorder = Color(0xFFCCEBF5);

  static const Color categoryTravelIcon = Color(0xFF0096C7);
  static const Color categoryTravelBackground = Color(0xFFEAFAFD);
  static const Color categoryTravelBorder = Color(0xFFCCEBF5);

  static const Color categoryFashionIcon = Color(0xFF0096C7);
  static const Color categoryFashionBackground = Color(0xFFEAFAFD);
  static const Color categoryFashionBorder = Color(0xFFCCEBF5);

  static const Color categoryFoodIcon = Color(0xFF0096C7);
  static const Color categoryFoodBackground = Color(0xFFEAFAFD);
  static const Color categoryFoodBorder = Color(0xFFCCEBF5);

  static const Color categoryFinanceIcon = Color(0xFF0096C7);
  static const Color categoryFinanceBackground = Color(0xFFEAFAFD);
  static const Color categoryFinanceBorder = Color(0xFFCCEBF5);

  static const Color categoryHealthIcon = Color(0xFF0096C7);
  static const Color categoryHealthBackground = Color(0xFFEAFAFD);
  static const Color categoryHealthBorder = Color(0xFFCCEBF5);

  // SnackBar / Dark Surfaces
  static const Color snackBarBackground = Color(0xFF1A1A1A);
}
