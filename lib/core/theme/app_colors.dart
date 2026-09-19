import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ==========================================
  // Primary Palette Scale (50-900)
  // Sophisticated periwinkle / indigo-violet
  // ==========================================
  static const Color periwinkle50 = Color(0xFFEDEDF7);
  static const Color periwinkle100 = Color(0xFFDBDBF0);
  static const Color periwinkle200 = Color(0xFFB8B8E0);
  static const Color periwinkle300 = Color(0xFF9494D1);
  static const Color periwinkle400 = Color(0xFF7070C2);
  static const Color periwinkle500 = Color(0xFF4D4DB3);
  static const Color periwinkle600 = Color(0xFF3D3D8F);
  static const Color periwinkle700 = Color(0xFF2E2E6B);
  static const Color periwinkle800 = Color(0xFF1F1F47);
  static const Color periwinkle900 = Color(0xFF0F0F24);
  static const Color white = Color(0xFFFFFFFF);

  // ==========================================
  // Primary Actions & Header
  // ==========================================
  static const Color primary = periwinkle500; // #4D4DB3
  static const Color primaryDark = periwinkle600; // #3D3D8F
  static const Color primaryHover = periwinkle600; // #3D3D8F
  static const Color primaryActive = periwinkle700; // #2E2E6B
  static const Color primaryDisabled = periwinkle400; // #7070C2

  // Subtle tonal transition within the palette
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [periwinkle500, periwinkle600],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color headerStart = periwinkle500; // #4D4DB3
  static const Color headerEnd = periwinkle600; // #3D3D8F

  static const LinearGradient headerGradient = LinearGradient(
    colors: [headerStart, headerEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ==========================================
  // Background & Surfaces
  // ==========================================
  static const Color background = periwinkle50; // #EDEDF7
  static const Color cardBackground = white; // #FFFFFF
  static const Color toggleBackground = periwinkle100; // #DBDBF0
  static const Color inputFill = white; // #FFFFFF
  static const Color lightCyanTint =
      periwinkle50; // #EDEDF7 (soft icon badge containers)
  static const Color lightBlueTint = periwinkle50; // #EDEDF7
  static const Color lightLavenderTint = periwinkle100; // #DBDBF0

  // ==========================================
  // Dark Theme Tokens (Obsidian / Deep Periwinkle)
  // ==========================================
  static const Color darkBackground = Color(0xFF0F0F1E);
  static const Color darkCardBackground = Color(0xFF181829);
  static const Color darkSubtleBorder = Color(0xFF262640);
  static const Color darkBorder = Color(0xFF333355);
  static const Color darkTextPrimary = Color(0xFFF0F0FA);
  static const Color darkTextSecondary = Color(0xFFB0B0D0);
  static const Color darkTextMuted = Color(0xFF7575A5);
  static const Color darkToggleBackground = Color(0xFF222238);

  // ==========================================
  // Context-aware Theme Helpers
  // ==========================================
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundOf(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color cardBackgroundOf(BuildContext context) =>
      isDark(context) ? darkCardBackground : cardBackground;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? darkTextPrimary : textPrimary;

  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? darkTextSecondary : textSecondary;

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? darkTextMuted : textMuted;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? darkBorder : border;

  static Color subtleBorderOf(BuildContext context) =>
      isDark(context) ? darkSubtleBorder : subtleBorder;

  static Color toggleBackgroundOf(BuildContext context) =>
      isDark(context) ? darkToggleBackground : toggleBackground;

  static Color inputFillOf(BuildContext context) =>
      isDark(context) ? darkCardBackground : inputFill;

  static Color surfaceTintOf(BuildContext context) =>
      isDark(context) ? darkCardBackground : lightCyanTint;

  // ==========================================
  // Chips
  // ==========================================
  static const Color chipInactiveBackground = white; // #FFFFFF
  static const Color chipInactiveBorder = periwinkle100; // #DBDBF0
  static const Color chipActiveBackground = periwinkle500; // #4D4DB3

  // ==========================================
  // Text Colors
  // ==========================================
  static const Color textDarkest =
      periwinkle900; // #0F0F24 (strong contrast / headings)
  static const Color textPrimary = periwinkle800; // #1F1F47 (primary text)
  static const Color textSecondary = periwinkle700; // #2E2E6B (secondary text)
  static const Color textMuted = periwinkle400; // #7070C2 (muted text)
  static const Color textWhite = white; // #FFFFFF

  // ==========================================
  // Borders & Errors
  // ==========================================
  static const Color border = periwinkle100; // #DBDBF0
  static const Color subtleBorder = periwinkle50; // #EDEDF7
  static const Color focusedBorder = periwinkle500; // #4D4DB3
  static const Color errorBorder = Color(0xFFE63946);
  static const Color errorText = Color(0xFFE63946);

  // ==========================================
  // Status Indicators & Badges
  // ==========================================
  static const Color statusPending = Color(0xFFFFB703);
  static const Color statusFailed = Color(0xFFE63946);
  static const Color statusProcessed = periwinkle500; // #4D4DB3
  static const Color notificationBadge = periwinkle300; // #9494D1
  static const Color weatherSun = periwinkle400; // #7070C2
  static const Color iconSecondary = periwinkle700; // #2E2E6B

  // ==========================================
  // Unified Global Category Chip Colors
  // ==========================================
  static const Color categoryChipBackground = periwinkle50; // #EDEDF7
  static const Color categoryChipBorder = periwinkle100; // #DBDBF0
  static const Color categoryChipDarkCyan = periwinkle600; // #3D3D8F
  static const Color categoryChipPrimaryCyan = periwinkle500; // #4D4DB3
  static const Color categoryCyanText = periwinkle700; // #2E2E6B

  // Category Pill Colors
  static const Color categoryWorkIcon = periwinkle500;
  static const Color categoryWorkBackground = periwinkle50;
  static const Color categoryWorkBorder = periwinkle100;

  static const Color categoryPersonalIcon = periwinkle600;
  static const Color categoryPersonalBackground = periwinkle50;
  static const Color categoryPersonalBorder = periwinkle100;

  static const Color categoryStudyIcon = periwinkle500;
  static const Color categoryStudyBackground = periwinkle50;
  static const Color categoryStudyBorder = periwinkle100;

  static const Color categoryTravelIcon = periwinkle600;
  static const Color categoryTravelBackground = periwinkle50;
  static const Color categoryTravelBorder = periwinkle100;

  static const Color categoryFashionIcon = periwinkle500;
  static const Color categoryFashionBackground = periwinkle50;
  static const Color categoryFashionBorder = periwinkle100;

  static const Color categoryFoodIcon = periwinkle600;
  static const Color categoryFoodBackground = periwinkle50;
  static const Color categoryFoodBorder = periwinkle100;

  static const Color categoryFinanceIcon = periwinkle500;
  static const Color categoryFinanceBackground = periwinkle50;
  static const Color categoryFinanceBorder = periwinkle100;

  static const Color categoryHealthIcon = periwinkle600;
  static const Color categoryHealthBackground = periwinkle50;
  static const Color categoryHealthBorder = periwinkle100;

  // SnackBar / Dark Surfaces
  static const Color snackBarBackground = periwinkle900; // #0F0F24

  // ==========================================
  // Violet Twilight / Accent Palette Mapped to Periwinkle Scale
  // ==========================================
  static const Color violetTwilight50 = periwinkle50; // #EDEDF7
  static const Color violetTwilight100 = periwinkle100; // #DBDBF0
  static const Color violetTwilight200 = periwinkle200; // #B8B8E0
  static const Color violetTwilight300 = periwinkle300; // #9494D1
  static const Color violetTwilight400 = periwinkle400; // #7070C2
  static const Color violetTwilight500 =
      periwinkle500; // #4D4DB3 (Primary action / icons)
  static const Color violetTwilight600 =
      periwinkle600; // #3D3D8F (Secondary action / icons)
  static const Color violetTwilight700 =
      periwinkle700; // #2E2E6B (Secondary text)
  static const Color violetTwilight800 =
      periwinkle800; // #1F1F47 (Headings & App Bar titles)
  static const Color violetTwilight900 =
      periwinkle900; // #0F0F24 (Darkest text)
  static const Color violetTwilight950 = periwinkle900; // #0F0F24

  // ==========================================
  // Category Card Palette Variations (Harmonious Periwinkle Tonal System)
  // ==========================================
  static const Color pastelLavender = periwinkle50; // #EDEDF7
  static const Color pastelPaleViolet = Color(
    0xFFF2F2FB,
  ); // Light Periwinkle Tint
  static const Color pastelMutedBlueLavender = periwinkle100; // #DBDBF0
  static const Color pastelPinkLavender = periwinkle50; // #EDEDF7
  static const Color pastelLightPurple = Color(
    0xFFE8E8F5,
  ); // Soft Periwinkle Tint
  static const Color pastelSoftIris = periwinkle100; // #DBDBF0
  static const Color pastelGentleAmethyst = periwinkle50; // #EDEDF7

  // ==========================================
  // Semantic Category Card Color Tokens
  // Strong saturated accent icon + subtle border + light pastel tint background
  // ==========================================
  // Blue / Documents
  static const Color catBlueIcon = Color(0xFF4361EE);
  static const Color catBlueBackground = Color(0xFFF0F3FF);
  static const Color catBlueBorder = Color(0xFFD5DEFF);

  // Cyan / Certificates & IDs & Water & Medical
  static const Color catCyanIcon = Color(0xFF0284C7);
  static const Color catCyanBackground = Color(0xFFF0F9FF);
  static const Color catCyanBorder = Color(0xFFBAE6FD);

  // Violet / Cards
  static const Color catVioletIcon = Color(0xFF7C3AED);
  static const Color catVioletBackground = Color(0xFFF5F3FF);
  static const Color catVioletBorder = Color(0xFFDDD6FE);

  // Emerald / Contacts
  static const Color catEmeraldIcon = Color(0xFF059669);
  static const Color catEmeraldBackground = Color(0xFFECFDF5);
  static const Color catEmeraldBorder = Color(0xFFA7F3D0);

  // Indigo / Work
  static const Color catIndigoIcon = Color(0xFF4F46E5);
  static const Color catIndigoBackground = Color(0xFFEEF2FF);
  static const Color catIndigoBorder = Color(0xFFC7D2FE);

  // Purple / Study & Education & Fashion
  static const Color catPurpleIcon = Color(0xFF9333EA);
  static const Color catPurpleBackground = Color(0xFFFAF5FF);
  static const Color catPurpleBorder = Color(0xFFE9D5FF);

  // Amber / Home & Food
  static const Color catAmberIcon = Color(0xFFD97706);
  static const Color catAmberBackground = Color(0xFFFFFBEB);
  static const Color catAmberBorder = Color(0xFFFDE68A);

  // Yellow / Electricity
  static const Color catYellowIcon = Color(0xFFCA8A04);
  static const Color catYellowBackground = Color(0xFFFEFCE8);
  static const Color catYellowBorder = Color(0xFFFEF08A);

  // Orange / Gas & Travel
  static const Color catOrangeIcon = Color(0xFFEA580C);
  static const Color catOrangeBackground = Color(0xFFFFF7ED);
  static const Color catOrangeBorder = Color(0xFFFED7AA);

  // Rose / Personal & Shopping
  static const Color catRoseIcon = Color(0xFFE11D48);
  static const Color catRoseBackground = Color(0xFFFFF1F2);
  static const Color catRoseBorder = Color(0xFFFECDD3);

  // Green / Finance & Banking
  static const Color catGreenIcon = Color(0xFF16A34A);
  static const Color catGreenBackground = Color(0xFFF0FDF4);
  static const Color catGreenBorder = Color(0xFFBBF7D0);

  // ==========================================
  // Legacy Aliases Mapped to the Periwinkle Scale
  // ==========================================
  static const Color primaryPink = periwinkle500;
  static const Color secondarySkyBlue = periwinkle600;
  static const Color accentLavender = periwinkle200;
  static const Color lightPink = periwinkle400;
  static const Color lightLavender = periwinkle100;
  static const Color softBackground = periwinkle50;
  static const Color primaryText = periwinkle800;
  static const Color secondaryText = periwinkle700;
  static const Color softBlueBackground = periwinkle50;
  static const Color softPinkBackground = periwinkle50;
  static const Color softLavenderBackground = periwinkle100;
  static const Color headerPinkStart = Color.fromARGB(255, 57, 57, 141);
  static const Color headerPinkEnd = headerEnd;
}
