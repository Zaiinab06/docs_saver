import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/category_section.dart';
import 'category_memories_screen.dart';

class CategoryDetailScreen extends StatelessWidget {
  final CategorySectionItem section;
  final void Function(CategoryCardItem category)? onCategoryTap;
  final VoidCallback? onCaptureTap;

  const CategoryDetailScreen({
    super.key,
    required this.section,
    this.onCategoryTap,
    this.onCaptureTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textWhite,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          section.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textWhite,
            letterSpacing: -0.3,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subtle badge with section icon and category count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.toggleBackgroundOf(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.borderOf(context),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      section.icon,
                      size: 15,
                      color: AppColors.violetTwilight500,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${section.categories.length} Categories',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Responsive 2-column grid of premium rounded category cards
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                itemCount: section.categories.length,
                itemBuilder: (context, index) {
                  final category = section.categories[index];
                  return _buildCategoryCard(context, category, isDark);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, CategoryCardItem category, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onCategoryTap != null) {
            onCategoryTap!(category);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryMemoriesScreen(
                  category: category,
                  onCaptureTap: onCaptureTap,
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBackground : category.backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? category.iconColor.withValues(alpha: 0.3)
                  : category.borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.violetTwilight500.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBackground
                      : category.iconBackgroundColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violetTwilight500.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    category.icon,
                    size: 22,
                    color: category.iconColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                category.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.violetTwilight800,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
