import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ==========================================
  // Brand & Surface Tokens — Theme: Deep Royal Violet
  // Deep Royal Violet (#4E3985), Rich Deep Plum Slate (#48347D), Soft Violet Tint (#ECE8F6)
  // ==========================================
  static const Color royalVelvet = Color(0xFF4E3985); // #4E3985 Primary Brand Color
  static const Color royalVelvetDark = Color(0xFF48347D); // #48347D Deep Violet / Header transition
  static const Color royalVelvetLight = Color(0xFFECE8F6); // #ECE8F6 Secondary soft tinted surface
  static const Color scaffoldLight = Color(0xFFF8F9FD); // #F8F9FD Clean soft slate off-white
  static const Color white = Color(0xFFFFFFFF); // #FFFFFF Crisp Pure White

  // Backward compatibility aliases
  static const Color royalSlateBlue = royalVelvet;
  static const Color royalSlateBlueDark = royalVelvetDark;
  static const Color royalSlateBlueLight = royalVelvetLight;
  static const Color imperialSapphire = royalVelvet;
  static const Color midnightNavy = Color(0xFF271E3C);
  static const Color burnishedGold = royalVelvet;
  static const Color burnishedGoldDark = royalVelvetDark;
  static const Color burnishedGoldLight = royalVelvetLight;
  static const Color emeraldTeal = royalVelvet;
  static const Color emeraldTealDark = royalVelvetDark;
  static const Color slateTint = scaffoldLight;

  // Velvet Palette Scales
  static const Color slateBlue50 = Color(0xFFECE8F6);
  static const Color slateBlue100 = Color(0xFFDFD9EE);
  static const Color slateBlue200 = Color(0xFFC7BCE0);
  static const Color slateBlue300 = Color(0xFFA696CC);
  static const Color slateBlue400 = Color(0xFF7B66AC);
  static const Color slateBlue500 = royalVelvet; // #4E3985
  static const Color slateBlue600 = royalVelvetDark; // #48347D
  static const Color slateBlue700 = Color(0xFF3F2D6F);
  static const Color slateBlue800 = Color(0xFF322359);
  static const Color slateBlue900 = Color(0xFF271E3C);

  // Gold aliases preserved for backward compatibility
  static const Color gold50 = Color(0xFFFFFBEB);
  static const Color gold100 = Color(0xFFFEF3C7);
  static const Color gold200 = Color(0xFFFDE68A);
  static const Color gold300 = Color(0xFFFCD34D);
  static const Color gold400 = Color(0xFFFBBF24);
  static const Color gold500 = Color(0xFFF59E0B);
  static const Color gold600 = royalVelvet;
  static const Color gold700 = royalVelvetDark;
  static const Color gold800 = Color(0xFF3F2D6F);
  static const Color gold900 = Color(0xFF271E3C);

  // Indigo / Periwinkle compatibility aliases mapped to Velvet scale
  static const Color indigo50 = Color(0xFFECE8F6);
  static const Color indigo100 = Color(0xFFDFD9EE);
  static const Color indigo200 = Color(0xFFC7BCE0);
  static const Color indigo300 = Color(0xFFA696CC);
  static const Color indigo400 = Color(0xFF7B66AC);
  static const Color indigo500 = royalVelvet;
  static const Color indigo600 = royalVelvetDark;
  static const Color indigo700 = Color(0xFF3F2D6F);
  static const Color indigo800 = Color(0xFF322359);
  static const Color indigo900 = Color(0xFF271E3C);

  static const Color periwinkle50 = Color(0xFFECE8F6);
  static const Color periwinkle100 = Color(0xFFDFD9EE);
  static const Color periwinkle200 = Color(0xFFC7BCE0);
  static const Color periwinkle300 = Color(0xFFA696CC);
  static const Color periwinkle400 = Color(0xFF7B66AC);
  static const Color periwinkle500 = royalVelvet;
  static const Color periwinkle600 = royalVelvetDark;
  static const Color periwinkle700 = Color(0xFF3F2D6F);
  static const Color periwinkle800 = Color(0xFF271E3C);
  static const Color periwinkle900 = Color(0xFF271E3C);

  // ==========================================
  // Primary Actions & Header
  // ==========================================
  static const Color primary = royalVelvet; // #4E3985 Primary Brand Color
  static const Color primaryDark = royalVelvetDark; // #48347D Deep Violet / Header transition
  static const Color primaryHover = royalVelvetDark;
  static const Color primaryActive = Color(0xFF3F2D6F);
  static const Color primaryDisabled = Color(0xFFB5A9D2);

  // Rich Royal Velvet gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [royalVelvet, royalVelvetDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Top header container: Royal Velvet #4E3985
  static const Color headerBackground = royalVelvet; // #4E3985
  static const Color headerStart = royalVelvet; // #4E3985
  static const Color headerEnd = royalVelvetDark; // #48347D

  static const LinearGradient headerGradient = LinearGradient(
    colors: [royalVelvet, royalVelvetDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ==========================================
  // Background & Surfaces
  // ==========================================
  static const Color background = scaffoldLight; // #F8F9FD Clean soft slate off-white
  static const Color cardBackground = white; // #FFFFFF Crisp Pure White
  static const Color toggleBackground = Color(0xFFECE8F6); // #ECE8F6
  static const Color inputFill = white; // #FFFFFF
  static const Color softPillBackground = Color(0xFFECE8F6); // #ECE8F6 Soft tinted badge surface
  static const Color lightCyanTint = Color(0xFFECE8F6); // Soft tinted surface
  static const Color lightBlueTint = Color(0xFFECE8F6); // Neutral Soft Tint
  static const Color lightLavenderTint = Color(0xFFECE8F6); // Soft Tint

  // ==========================================
  // Dark Theme Tokens (Deep Slate Vault)
  // ==========================================
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkCardBackground = Color(0xFF1E293B);
  static const Color darkSubtleBorder = Color(0xFF334155);
  static const Color darkBorder = Color(0xFF475569);
  static const Color darkTextPrimary = Color(0xFFF8F9FD);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color darkToggleBackground = Color(0xFF334155);

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
  static const Color chipInactiveBorder = Color(0xFFE5E7EB); // #E5E7EB
  static const Color chipActiveBackground = royalVelvet; // #4E3985

  // ==========================================
  // Text Colors
  // ==========================================
  static const Color textDarkest = Color(0xFF271E3C); // #271E3C Rich deep violet-black
  static const Color textPrimary = Color(0xFF271E3C); // #271E3C Rich deep violet-black
  static const Color textSecondary = Color(0xFF6B7280); // #6B7280 Refined Slate
  static const Color textMuted = Color(0xFF8F9BB3); // #8F9BB3 Refined Slate
  static const Color textWhite = white; // #FFFFFF Crisp Pure White

  // ==========================================
  // Borders & Errors
  // ==========================================
  static const Color border = Color(0xFFE5E7EB); // #E5E7EB Subtle Border
  static const Color subtleBorder = Color(0xFFF1F5F9); // #F1F5F9
  static const Color focusedBorder = royalVelvet; // #4E3985
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
