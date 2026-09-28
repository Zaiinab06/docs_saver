import 'package:flutter/material.dart';

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
          backgroundColor: Color(0xFFE8F1FD),
          borderColor: Color(0xFFD0E1FD),
          iconColor: Color(0xFF1E6FD9),
          iconBackgroundColor: Color(0xFFE8F1FD),
        ),
        CategoryCardItem(
          name: 'Certificates & IDs',
          icon: Icons.badge_rounded,
          backgroundColor: Color(0xFFEDE7F6),
          borderColor: Color(0xFFD1C4E9),
          iconColor: Color(0xFF5E35B1),
          iconBackgroundColor: Color(0xFFEDE7F6),
        ),
        CategoryCardItem(
          name: 'Cards',
          icon: Icons.credit_card_rounded,
          backgroundColor: Color(0xFFFDE8EC),
          borderColor: Color(0xFFF8BBD0),
          iconColor: Color(0xFFD81B60),
          iconBackgroundColor: Color(0xFFFDE8EC),
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Contacts',
          icon: Icons.perm_contact_calendar_rounded,
          backgroundColor: Color(0xFFE8F5E9),
          borderColor: Color(0xFFC8E6C9),
          iconColor: Color(0xFF2E7D32),
          iconBackgroundColor: Color(0xFFE8F5E9),
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
          backgroundColor: Color(0xFFFFF3E0),
          borderColor: Color(0xFFFFE0B2),
          iconColor: Color(0xFFEF6C00),
          iconBackgroundColor: Color(0xFFFFF3E0),
        ),
        CategoryCardItem(
          name: 'Study & Education',
          icon: Icons.school_rounded,
          backgroundColor: Color(0xFFF3E5F5),
          borderColor: Color(0xFFE1BEE7),
          iconColor: Color(0xFF8E24AA),
          iconBackgroundColor: Color(0xFFF3E5F5),
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
          backgroundColor: Color(0xFFE8F5E9),
          borderColor: Color(0xFFC8E6C9),
          iconColor: Color(0xFF2E7D32),
          iconBackgroundColor: Color(0xFFE8F5E9),
        ),
        CategoryCardItem(
          name: 'Water',
          icon: Icons.water_drop_rounded,
          backgroundColor: Color(0xFFE0F7FA),
          borderColor: Color(0xFFB2EBF2),
          iconColor: Color(0xFF0097A7),
          iconBackgroundColor: Color(0xFFE0F7FA),
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Electricity',
          icon: Icons.bolt_rounded,
          backgroundColor: Color(0xFFFFF8E1),
          borderColor: Color(0xFFFFECB3),
          iconColor: Color(0xFFF57F17),
          iconBackgroundColor: Color(0xFFFFF8E1),
          templateType: 'bill',
        ),
        CategoryCardItem(
          name: 'Gas',
          icon: Icons.local_fire_department_rounded,
          backgroundColor: Color(0xFFFBE9E7),
          borderColor: Color(0xFFFFCCBC),
          iconColor: Color(0xFFD84315),
          iconBackgroundColor: Color(0xFFFBE9E7),
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
          backgroundColor: Color(0xFFF3E5F5),
          borderColor: Color(0xFFE1BEE7),
          iconColor: Color(0xFF7B1FA2),
          iconBackgroundColor: Color(0xFFF3E5F5),
        ),
        CategoryCardItem(
          name: 'Medical & Health',
          icon: Icons.health_and_safety_rounded,
          backgroundColor: Color(0xFFFFEBEE),
          borderColor: Color(0xFFFFCDD2),
          iconColor: Color(0xFFE53935),
          iconBackgroundColor: Color(0xFFFFEBEE),
        ),
        CategoryCardItem(
          name: 'Finance & Banking',
          icon: Icons.account_balance_rounded,
          backgroundColor: Color(0xFFE0F2F1),
          borderColor: Color(0xFFB2DFDB),
          iconColor: Color(0xFF00897B),
          iconBackgroundColor: Color(0xFFE0F2F1),
          templateType: 'bank_card',
        ),
        CategoryCardItem(
          name: 'Travel & Tickets',
          icon: Icons.flight_rounded,
          backgroundColor: Color(0xFFFBE9E7),
          borderColor: Color(0xFFFFCCBC),
          iconColor: Color(0xFFF4511E),
          iconBackgroundColor: Color(0xFFFBE9E7),
        ),
        CategoryCardItem(
          name: 'Fashion',
          icon: Icons.checkroom_rounded,
          backgroundColor: Color(0xFFFCE4EC),
          borderColor: Color(0xFFF8BBD0),
          iconColor: Color(0xFFC2185B),
          iconBackgroundColor: Color(0xFFFCE4EC),
        ),
        CategoryCardItem(
          name: 'Food',
          icon: Icons.restaurant_rounded,
          backgroundColor: Color(0xFFFFF8E1),
          borderColor: Color(0xFFFFE082),
          iconColor: Color(0xFFFB8C00),
          iconBackgroundColor: Color(0xFFFFF8E1),
        ),
        CategoryCardItem(
          name: 'Shopping & Products',
          icon: Icons.shopping_bag_rounded,
          backgroundColor: Color(0xFFEDE7F6),
          borderColor: Color(0xFFD1C4E9),
          iconColor: Color(0xFF5E35B1),
          iconBackgroundColor: Color(0xFFEDE7F6),
        ),
      ],
    ),
  ];
}
