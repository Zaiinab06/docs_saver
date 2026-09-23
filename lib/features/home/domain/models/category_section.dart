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
          icon: Icons.description_outlined,
          backgroundColor: AppColors.catBlueBackground,
          borderColor: AppColors.catBlueBorder,
          iconColor: AppColors.catBlueIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Certificates & IDs',
          icon: Icons.badge_outlined,
          backgroundColor: AppColors.catCyanBackground,
          borderColor: AppColors.catCyanBorder,
          iconColor: AppColors.catCyanIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Cards',
          icon: Icons.credit_card_outlined,
          backgroundColor: AppColors.catVioletBackground,
          borderColor: AppColors.catVioletBorder,
          iconColor: AppColors.catVioletIcon,
          iconBackgroundColor: Colors.white,
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Contacts',
          icon: Icons.contact_phone_outlined,
          backgroundColor: AppColors.catEmeraldBackground,
          borderColor: AppColors.catEmeraldBorder,
          iconColor: AppColors.catEmeraldIcon,
          iconBackgroundColor: Colors.white,
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
          icon: Icons.work_outline_rounded,
          backgroundColor: AppColors.catIndigoBackground,
          borderColor: AppColors.catIndigoBorder,
          iconColor: AppColors.catIndigoIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Study & Education',
          icon: Icons.school_outlined,
          backgroundColor: AppColors.catPurpleBackground,
          borderColor: AppColors.catPurpleBorder,
          iconColor: AppColors.catPurpleIcon,
          iconBackgroundColor: Colors.white,
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
          icon: Icons.home_outlined,
          backgroundColor: AppColors.catAmberBackground,
          borderColor: AppColors.catAmberBorder,
          iconColor: AppColors.catAmberIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Water',
          icon: Icons.water_drop_outlined,
          backgroundColor: AppColors.catCyanBackground,
          borderColor: AppColors.catCyanBorder,
          iconColor: AppColors.catCyanIcon,
          iconBackgroundColor: Colors.white,
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Electricity',
          icon: Icons.bolt_outlined,
          backgroundColor: AppColors.catYellowBackground,
          borderColor: AppColors.catYellowBorder,
          iconColor: AppColors.catYellowIcon,
          iconBackgroundColor: Colors.white,
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Gas',
          icon: Icons.local_fire_department_outlined,
          backgroundColor: AppColors.catOrangeBackground,
          borderColor: AppColors.catOrangeBorder,
          iconColor: AppColors.catOrangeIcon,
          iconBackgroundColor: Colors.white,
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
          icon: Icons.person_outline_rounded,
          backgroundColor: AppColors.catRoseBackground,
          borderColor: AppColors.catRoseBorder,
          iconColor: AppColors.catRoseIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Medical & Health',
          icon: Icons.health_and_safety_outlined,
          backgroundColor: AppColors.catCyanBackground,
          borderColor: AppColors.catCyanBorder,
          iconColor: AppColors.catCyanIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Finance & Banking',
          icon: Icons.account_balance_outlined,
          backgroundColor: AppColors.catGreenBackground,
          borderColor: AppColors.catGreenBorder,
          iconColor: AppColors.catGreenIcon,
          iconBackgroundColor: Colors.white,
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Travel & Tickets',
          icon: Icons.flight_outlined,
          backgroundColor: AppColors.catOrangeBackground,
          borderColor: AppColors.catOrangeBorder,
          iconColor: AppColors.catOrangeIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Fashion',
          icon: Icons.checkroom_outlined,
          backgroundColor: AppColors.catPurpleBackground,
          borderColor: AppColors.catPurpleBorder,
          iconColor: AppColors.catPurpleIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Food',
          icon: Icons.restaurant_outlined,
          backgroundColor: AppColors.catAmberBackground,
          borderColor: AppColors.catAmberBorder,
          iconColor: AppColors.catAmberIcon,
          iconBackgroundColor: Colors.white,
        ),
        CategoryCardItem(
          name: 'Shopping & Products',
          icon: Icons.shopping_bag_outlined,
          backgroundColor: AppColors.catRoseBackground,
          borderColor: AppColors.catRoseBorder,
          iconColor: AppColors.catRoseIcon,
          iconBackgroundColor: Colors.white,
        ),
      ],
    ),
  ];
}
