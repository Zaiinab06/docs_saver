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
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Certificates & IDs',
          icon: Icons.badge_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Cards',
          icon: Icons.credit_card_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent,
          iconBackgroundColor: AppColors.toggleBackground,
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Contacts',
          icon: Icons.perm_contact_calendar_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.secondary,
          iconBackgroundColor: AppColors.toggleBackground,
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
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Study & Education',
          icon: Icons.school_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.secondary,
          iconBackgroundColor: AppColors.toggleBackground,
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
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Water',
          icon: Icons.water_drop_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.secondary,
          iconBackgroundColor: AppColors.toggleBackground,
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Electricity',
          icon: Icons.bolt_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent2,
          iconBackgroundColor: AppColors.gold50,
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Gas',
          icon: Icons.local_fire_department_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent,
          iconBackgroundColor: AppColors.toggleBackground,
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
          iconColor: AppColors.accent,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Medical & Health',
          icon: Icons.health_and_safety_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Finance & Banking',
          icon: Icons.account_balance_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.primary,
          iconBackgroundColor: AppColors.toggleBackground,
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Travel & Tickets',
          icon: Icons.flight_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Fashion',
          icon: Icons.checkroom_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
        CategoryCardItem(
          name: 'Food',
          icon: Icons.restaurant_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.accent2,
          iconBackgroundColor: AppColors.gold50,
        ),
        CategoryCardItem(
          name: 'Shopping & Products',
          icon: Icons.shopping_bag_rounded,
          backgroundColor: AppColors.cardBackground,
          borderColor: AppColors.border,
          iconColor: AppColors.secondary,
          iconBackgroundColor: AppColors.toggleBackground,
        ),
      ],
    ),
  ];
}
