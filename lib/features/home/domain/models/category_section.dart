import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Represents an individual category card displayed in the Category Detail Screen.
class CategoryCardItem {
  final String name;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String? templateType;

  const CategoryCardItem({
    required this.name,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.iconBackgroundColor,
    this.templateType,
  });

  bool get isCardTemplate =>
      templateType == 'bank_card' ||
      name == 'Cards' ||
      name == 'Finance & Banking';

  bool get isBillTemplate =>
      templateType == 'bill' ||
      name == 'Electricity' ||
      name == 'Water' ||
      name == 'Gas';
}

/// Represents a top-level category section card displayed on the Home Screen.
class CategorySectionItem {
  final String id;
  final String title;
  final IconData icon;
  final List<CategoryCardItem> categories;

  const CategorySectionItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.categories,
  });
}

/// Centralized, static, and reusable configuration for the 4 category sections
/// and their respective final subcategories.
class CategorySectionsData {
  CategorySectionsData._();

  static const List<CategorySectionItem> sections = [
    // 1. Documents & Records
    CategorySectionItem(
      id: 'documents_records',
      title: 'Documents & Records',
      icon: Icons.folder_outlined,
      categories: [
        CategoryCardItem(
          name: 'Documents',
          icon: Icons.description_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF2563EB),
          iconBackgroundColor: Color(0xFFE8EEF8),
        ),
        CategoryCardItem(
          name: 'Certificates & IDs',
          icon: Icons.badge_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFD97706),
          iconBackgroundColor: Color(0xFFFEF3C7),
        ),
        CategoryCardItem(
          name: 'Cards',
          icon: Icons.credit_card_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFE11D48),
          iconBackgroundColor: Color(0xFFFFE4E6),
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Contacts',
          icon: Icons.perm_contact_calendar_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF0284C7),
          iconBackgroundColor: Color(0xFFE0F2FE),
        ),
      ],
    ),

    // 2. Work & Learning
    CategorySectionItem(
      id: 'work_learning',
      title: 'Work & Learning',
      icon: Icons.auto_stories_outlined,
      categories: [
        CategoryCardItem(
          name: 'Work',
          icon: Icons.work_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFD97706),
          iconBackgroundColor: Color(0xFFFEF3C7),
        ),
        CategoryCardItem(
          name: 'Study & Education',
          icon: Icons.school_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF0284C7),
          iconBackgroundColor: Color(0xFFE0F2FE),
        ),
      ],
    ),

    // 3. Home & Utilities
    CategorySectionItem(
      id: 'home_utilities',
      title: 'Home & Utilities',
      icon: Icons.cottage_outlined,
      categories: [
        CategoryCardItem(
          name: 'Home',
          icon: Icons.home_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF9333EA),
          iconBackgroundColor: Color(0xFFF3E8FF),
        ),
        CategoryCardItem(
          name: 'Water',
          icon: Icons.water_drop_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF0891B2),
          iconBackgroundColor: Color(0xFFCFFAFE),
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Electricity',
          icon: Icons.bolt_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFB45309),
          iconBackgroundColor: Color(0xFFFDE68A),
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Gas',
          icon: Icons.local_fire_department_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFC2410C),
          iconBackgroundColor: Color(0xFFFFE4D6),
          templateType: 'bill',
        ),
      ],
    ),

    // 4. Personal Life
    CategorySectionItem(
      id: 'personal_life',
      title: 'Personal Life',
      icon: Icons.favorite_outline_rounded,
      categories: [
        CategoryCardItem(
          name: 'Personal',
          icon: Icons.person_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFE11D48),
          iconBackgroundColor: Color(0xFFFFE4E6),
        ),
        CategoryCardItem(
          name: 'Medical & Health',
          icon: Icons.health_and_safety_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF16A34A),
          iconBackgroundColor: Color(0xFFDCFCE7),
        ),
        CategoryCardItem(
          name: 'Finance & Banking',
          icon: Icons.account_balance_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF4F46E5),
          iconBackgroundColor: Color(0xFFE0E7FF),
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Travel & Tickets',
          icon: Icons.flight_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFEA580C),
          iconBackgroundColor: Color(0xFFFFEDD5),
        ),
        CategoryCardItem(
          name: 'Fashion',
          icon: Icons.checkroom_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFDB2777),
          iconBackgroundColor: Color(0xFFFCE7F3),
        ),
        CategoryCardItem(
          name: 'Food',
          icon: Icons.restaurant_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFFCA8A04),
          iconBackgroundColor: Color(0xFFFEF9C3),
        ),
        CategoryCardItem(
          name: 'Shopping & Products',
          icon: Icons.shopping_bag_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: Color(0xFF0D9488),
          iconBackgroundColor: Color(0xFFCCFBF1),
        ),
      ],
    ),
  ];
}
