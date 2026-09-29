import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ==========================================
  // Brand & Surface Tokens — Light Mode (Sage & Ivory)
  // ==========================================
  static const Color primary = Color(0xFF1F6B57);
  static const Color secondary = Color(0xFFA8C9B5);
  static const Color accent = Color(0xFFFF9B78);
  static const Color accent2 = Color(0xFFF6C66A);
  static const Color background = Color(0xFFF8F6F0);
  static const Color cardBackground = Color(0xFFFCFBF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF17332D);
  static const Color textSecondary = Color(0xFF71827B);
  static const Color textMuted = Color(0xFF8D9A93);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textDarkest = textPrimary;
  static const Color scaffoldLight = background;
  static const Color white = Color(0xFFFFFFFF);

  // Backward compatibility aliases
  static const Color royalVelvet = primary;
  static const Color royalVelvetDark = Color(0xFF2A836C);
  static const Color royalVelvetLight = Color(0xFFEAF1EC);
  static const Color royalSlateBlue = primary;
  static const Color royalSlateBlueDark = Color(0xFF2A836C);
  static const Color royalSlateBlueLight = Color(0xFFEAF1EC);
  static const Color imperialSapphire = primary;
  static const Color midnightNavy = Color(0xFF17332D);
  static const Color burnishedGold = primary;
  static const Color burnishedGoldDark = Color(0xFF2A836C);
  static const Color burnishedGoldLight = Color(0xFFEAF1EC);
  static const Color emeraldTeal = secondary;
  static const Color emeraldTealDark = Color(0xFF0891B2);
  static const Color slateTint = background;

  // Velvet / Indigo Palette Scales
  static const Color slateBlue50 = Color(0xFFF2F5F0);
  static const Color slateBlue100 = Color(0xFFE1E8E2);
  static const Color slateBlue200 = Color(0xFFC9D9CD);
  static const Color slateBlue300 = secondary;
  static const Color slateBlue400 = Color(0xFF6D9E87);
  static const Color slateBlue500 = primary;
  static const Color slateBlue600 = Color(0xFF2A836C);
  static const Color slateBlue700 = Color(0xFF1F6B57);
  static const Color slateBlue800 = Color(0xFF17332D);
  static const Color slateBlue900 = Color(0xFF10251F);

  // Gold aliases preserved for backward compatibility
  static const Color gold50 = Color(0xFFFFF8E8);
  static const Color gold100 = Color(0xFFFCECCB);
  static const Color gold200 = Color(0xFFF6C66A);
  static const Color gold300 = Color(0xFFE9B44F);
  static const Color gold400 = Color(0xFFD9A43B);
  static const Color gold500 = Color(0xFFC18A2C);
  static const Color gold600 = Color(0xFFA87522);
  static const Color gold700 = Color(0xFF8D601B);
  static const Color gold800 = Color(0xFF714D18);
  static const Color gold900 = Color(0xFF563B15);

  // Indigo / Periwinkle compatibility aliases
  static const Color indigo50 = slateBlue50;
  static const Color indigo100 = slateBlue100;
  static const Color indigo200 = slateBlue200;
  static const Color indigo300 = slateBlue300;
  static const Color indigo400 = slateBlue400;
  static const Color indigo500 = primary;
  static const Color indigo600 = slateBlue600;
  static const Color indigo700 = slateBlue700;
  static const Color indigo800 = slateBlue800;
  static const Color indigo900 = slateBlue900;

  static const Color periwinkle50 = slateBlue50;
  static const Color periwinkle100 = slateBlue100;
  static const Color periwinkle200 = slateBlue200;
  static const Color periwinkle300 = slateBlue300;
  static const Color periwinkle400 = slateBlue400;
  static const Color periwinkle500 = primary;
  static const Color periwinkle600 = slateBlue600;
  static const Color periwinkle700 = slateBlue700;
  static const Color periwinkle800 = slateBlue800;
  static const Color periwinkle900 = slateBlue900;

  // ==========================================
  // Primary Actions & Header Gradients
  // ==========================================
  // Single unified tone for the status bar, header, and center nav button.
  static const Color kDeepSagePine = Color(0xFF0F3E32);
  static const Color primaryDark = Color(0xFF174B40);
  static const Color primaryHover = Color(0xFF2A836C);
  static const Color primaryActive = Color(0xFF174B40);
  static const Color primaryDisabled = Color(0xFFA8C9B5);

  static const LinearGradient headerGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0B2F23), // Exact dark status-bar pine green
      Color(0xFF0F3E30),
      Color(0xFF144D3C),
      Color(0xFF1E634E),
    ],
    stops: [0.0, 0.25, 0.65, 1.0],
  );

  static const LinearGradient headerGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0C1412), Color(0xFF131D1B)],
  );

  static const LinearGradient headerGradient = headerGradientLight;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1F6B57), Color(0xFF2A836C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientDark = LinearGradient(
    colors: [Color(0xFF174B40), Color(0xFF2A836C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Top header container colors
  static const Color headerBackground = primary;
  static const Color headerStart = Color(0xFF1F6B57);
  static const Color headerEnd = Color(0xFFA8C9B5);

  // Surfaces & Fills
  static const Color toggleBackground = Color(0xFFEAF1EC);
  static const Color inputFill = white;
  static const Color softPillBackground = Color(0xFFEAF1EC);
  static const Color lightCyanTint = Color(0xFFEAF1EC);
  static const Color lightBlueTint = Color(0xFFEAF1EC);
  static const Color lightLavenderTint = Color(0xFFF8F6F0);

  // ==========================================
  // Dark Theme Tokens (High Saturation & Contrast)
  // ==========================================
  static const Color darkPrimary = Color(0xFF2A836C);
  static const Color darkSecondary = Color(0xFFA8C9B5);
  static const Color darkAccent = Color(0xFFFF9B78);
  static const Color darkBackground = Color(0xFF0F1715);
  static const Color darkCardBackground = Color(0xFF162320);
  static const Color darkSurface = Color(0xFF162320);
  static const Color darkSubtleBorder = Color(0x0FFFFFFF);
  static const Color darkBorder = Color(0x0FFFFFFF);
  static const Color darkTextPrimary = Color(0xFFF4F6F0);
  static const Color darkTextSecondary = Color(0xFFB5C2B9);
  static const Color darkTextMuted = Color(0xFF8D9A93);
  static const Color darkToggleBackground = Color(0xFF263B33);

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
      isDark(context) ? const Color(0xFF23332F) : lightCyanTint;

  static LinearGradient headerGradientOf(BuildContext context) =>
      isDark(context) ? headerGradientDark : headerGradientLight;

  static LinearGradient primaryGradientOf(BuildContext context) =>
      isDark(context) ? primaryGradientDark : primaryGradient;

  static Color primaryOf(BuildContext context) =>
      isDark(context) ? darkPrimary : primary;

  static Color secondaryOf(BuildContext context) =>
      isDark(context) ? darkSecondary : secondary;

  static Color accentOf(BuildContext context) =>
      isDark(context) ? darkAccent : accent;

  // ==========================================
  // Chips
  // ==========================================
  static const Color chipInactiveBackground = white;
  static const Color chipInactiveBorder = Color(0xFFE1E8E2);
  static const Color chipActiveBackground = primary;

  // ==========================================
  // Borders & Errors
  // ==========================================
  static const Color border = Color(0xFFE1E8E2);
  static const Color subtleBorder = Color(0xFFE1E8E2);
  static const Color focusedBorder = primary;
  static const Color errorBorder = Color(0xFFEF4444);
  static const Color errorText = Color(0xFFEF4444);

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
