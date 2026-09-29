import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/presentation/widgets/bank_card_template_sheet.dart';
import '../../../capture/presentation/widgets/bill_template_sheet.dart';
import '../../domain/models/category_section.dart';
import 'category_memories_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
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
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    final itemCount = widget.section.categories.length;
    // 50ms stagger per item with a baseline duration for smooth fluid entrance
    final totalDurationMs = 400 + (itemCount * 50);
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalDurationMs),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool _matchesCategory(String memoryCategory, String targetCategoryName) {
    final mem = memoryCategory.trim().toLowerCase();
    final target = targetCategoryName.trim().toLowerCase();
    if (mem == target) return true;

    if (target.contains('&')) {
      final parts = target
          .split('&')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty);
      for (final part in parts) {
        if (mem == part || mem.contains(part)) return true;
      }
    }

    if (target.contains(mem) || mem.contains(target)) return true;

    return false;
  }

  void _navigateToCategory(BuildContext context, CategoryCardItem category) {
    if (widget.onCategoryTap != null) {
      widget.onCategoryTap!(category);
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (context, animation, secondaryAnimation) =>
              CategoryMemoriesScreen(
                category: category,
                onCaptureTap: widget.onCaptureTap,
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedSlide = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final curvedFade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0.0),
                end: Offset.zero,
              ).animate(curvedSlide),
              child: FadeTransition(
                opacity: Tween<double>(
                  begin: 0.0,
                  end: 1.0,
                ).animate(curvedFade),
                child: child,
              ),
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C1412) : const Color(0xFFFBFBF9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0C1412) : const Color(0xFF0F3E32),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: isDark ? const Color(0xFF0C1412) : const Color(0xFF0F3E32),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.section.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 20, bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subtle badge with section icon and category count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
                        widget.section.icon,
                        size: 15,
                        color: AppColors.violetTwilight500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.section.categories.length} Categories',
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
              ),
              const SizedBox(height: 12),

              // Vertical list of animated full-width modern cards
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.section.categories.length,
                separatorBuilder: (_, __) => const SizedBox.shrink(),
                itemBuilder: (context, index) {
                  final category = widget.section.categories[index];
                  return _buildAnimatedCategoryCard(
                    context,
                    category,
                    index,
                    isDark,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCategoryCard(
    BuildContext context,
    CategoryCardItem category,
    int index,
    bool isDark,
  ) {
    final totalItems = widget.section.categories.length;
    final totalDurationMs = 400 + (totalItems * 50);
    final startFraction = (index * 50) / totalDurationMs;
    final endFraction = ((index * 50) + 400) / totalDurationMs;

    final curvedAnimation = CurvedAnimation(
      parent: _animController,
      curve: Interval(
        startFraction.clamp(0.0, 1.0),
        endFraction.clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: curvedAnimation,
      builder: (context, child) {
        final progress = curvedAnimation.value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 20 * (1.0 - progress)),
            child: child,
          ),
        );
      },
      child: _BouncingTapCard(
        onTap: () => _navigateToCategory(context, category),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF162320) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? const Color(0x0FFFFFFF)
                  : Colors.grey.shade200,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.22)
                    : AppColors.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Leading: Category icon inside a neat rounded-rect container
                Hero(
                  tag: 'category_icon_${category.name}',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? category.iconColor.withValues(alpha: 0.16)
                          : category.iconBackgroundColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? category.iconColor.withValues(alpha: 0.3)
                            : category.borderColor,
                        width: 1.0,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        category.icon,
                        size: 24,
                        color: category.iconColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Center: Title + Subtitle / Extra actions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.name,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildSubtitle(context, category, isDark),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Trailing: Subtle right arrow
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark
                      ? AppColors.darkTextSecondary.withValues(alpha: 0.5)
                      : const Color(0xFF9E92B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle(
    BuildContext context,
    CategoryCardItem category,
    bool isDark,
  ) {
    if (category.isCardTemplate) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('detail_add_card_${category.name}'),
            onTap: () => BankCardTemplateSheet.show(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 12, color: AppColors.primary),
                  SizedBox(width: 3),
                  Text(
                    'Add Card',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildMemoryCountBadge(context, category, isDark),
        ],
      );
    } else if (category.isBillTemplate) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('detail_add_bill_${category.name}'),
            onTap: () => BillTemplateSheet.show(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 12, color: AppColors.primary),
                  SizedBox(width: 3),
                  Text(
                    'Add Bill',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildMemoryCountBadge(context, category, isDark),
        ],
      );
    }

    return _buildMemoryCountBadge(context, category, isDark);
  }

  Widget _buildMemoryCountBadge(
    BuildContext context,
    CategoryCardItem category,
    bool isDark,
  ) {
    CaptureBloc? bloc;
    try {
      bloc = context.read<CaptureBloc>();
    } catch (_) {
      bloc = null;
    }

    if (bloc == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : const Color(0xFFF1EEF9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '0 memories',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.darkTextSecondary
                : const Color(0xFF6B5E87),
            letterSpacing: -0.1,
          ),
        ),
      );
    }

    return BlocBuilder<CaptureBloc, CaptureState>(
      bloc: bloc,
      builder: (context, state) {
        int count = 0;
        if (state is CaptureLoaded) {
          count = state.memories
              .where((m) => _matchesCategory(m.category, category.name))
              .length;
        }

        final countText = count > 0
            ? '$count ${count == 1 ? 'memory' : 'memories'}'
            : '0 memories';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : const Color(0xFFF1EEF9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            countText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : const Color(0xFF6B5E87),
              letterSpacing: -0.1,
            ),
          ),
        );
      },
    );
  }
}

/// Interactive feedback widget providing subtle scale-down on tap with ripple feedback
class _BouncingTapCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _BouncingTapCard({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_BouncingTapCard> createState() => _BouncingTapCardState();
}

class _BouncingTapCardState extends State<_BouncingTapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 130),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.975,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) =>
          Transform.scale(scale: _scaleAnimation.value, child: child),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (isHighlighted) {
            if (isHighlighted) {
              _controller.forward();
            } else {
              _controller.reverse();
            }
          },
          borderRadius: widget.borderRadius,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: AppColors.primary.withValues(alpha: 0.04),
          child: widget.child,
        ),
      ),
    );
  }
}
