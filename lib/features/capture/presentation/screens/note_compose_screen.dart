import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';

class _CategoryChoice {
  final String name;
  final IconData icon;

  const _CategoryChoice({required this.name, required this.icon});
}

class NoteComposeScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialContent;
  final String? initialCategory;
  final List<String>? initialTags;

  const NoteComposeScreen({
    super.key,
    this.initialTitle,
    this.initialContent,
    this.initialCategory,
    this.initialTags,
  });

  @override
  State<NoteComposeScreen> createState() => _NoteComposeScreenState();
}

class _NoteComposeScreenState extends State<NoteComposeScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final TextEditingController _tagInputController = TextEditingController();

  String? _selectedCategory;
  late final List<String> _tags;
  bool _isSaving = false;

  static const List<_CategoryChoice> _categories = [
    _CategoryChoice(
      name: AppStrings.categoryPersonal,
      icon: Icons.favorite_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryWork,
      icon: Icons.work_outline_rounded,
    ),
    _CategoryChoice(name: AppStrings.categoryStudy, icon: Icons.school_rounded),
    _CategoryChoice(
      name: AppStrings.categoryTravel,
      icon: Icons.flight_takeoff_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFashion,
      icon: Icons.shopping_bag_outlined,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFood,
      icon: Icons.restaurant_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFinance,
      icon: Icons.account_balance_wallet_outlined,
    ),
    _CategoryChoice(
      name: AppStrings.categoryHealth,
      icon: Icons.fitness_center_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _contentController = TextEditingController(
      text: widget.initialContent ?? '',
    );
    _selectedCategory = widget.initialCategory;
    _tags = widget.initialTags != null
        ? List<String>.from(widget.initialTags!)
        : <String>[];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addCustomTag() {
    final rawTag = _tagInputController.text
        .trim()
        .replaceAll('#', '')
        .toLowerCase();
    if (rawTag.isNotEmpty && !_tags.contains(rawTag)) {
      setState(() {
        _tags.add(rawTag);
        _tagInputController.clear();
      });
    }
  }

  String _deriveDeterministicTitle(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isNotEmpty) {
      final firstLine = lines.first;
      if (firstLine.length <= 40) {
        return firstLine;
      }
      return '${firstLine.substring(0, 37)}...';
    }

    return 'Note (${DateFormat('MMM d').format(DateTime.now())})';
  }

  Future<void> _saveNote() async {
    final rawContent = _contentController.text.trim();
    if (rawContent.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter note content before saving.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final rawTitle = _titleController.text.trim();
    final finalTitle = rawTitle.isNotEmpty
        ? rawTitle
        : _deriveDeterministicTitle(rawContent);

    try {
      context.read<CaptureBloc>().add(
        AddMemoryEvent(
          title: finalTitle,
          content: rawContent,
          category: _selectedCategory ?? AppStrings.categoryGeneral,
          tags: List<String>.from(_tags),
          mediaUrl: null,
          aiStatus: 'pending',
        ),
      );

      bool isOnline = false;
      try {
        isOnline = Supabase.instance.client.auth.currentUser != null;
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOnline
                  ? 'Note saved! Organizing your memory...'
                  : 'Saved offline — will organize when online',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save note: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCategorySelector() {
    final allChoices = [
      const _CategoryChoice(
        name: 'Auto (AI)',
        icon: Icons.auto_awesome_rounded,
      ),
      ..._categories,
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: allChoices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = allChoices[index];
          final isAuto = cat.name == 'Auto (AI)';
          final isSelected = isAuto
              ? (_selectedCategory == null)
              : (_selectedCategory == cat.name);

          const selectedBgColor = Color(0xFF134E3F);
          const unselectedBgColor = Color(0xFFF1F5F3);
          const unselectedBorderColor = Color(0xFFE2E8F0);
          const unselectedTextColor = Color(0xFF2D3748);
          const unselectedIconColor = Color(0xFF134E3F);

          return InkWell(
            key: Key(
              isAuto
                  ? 'category_chip_auto'
                  : 'category_chip_${cat.name.toLowerCase()}',
            ),
            onTap: () =>
                setState(() => _selectedCategory = isAuto ? null : cat.name),
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? selectedBgColor : unselectedBgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected ? selectedBgColor : unselectedBorderColor,
                  width: 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: selectedBgColor.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 16,
                    color: isSelected ? Colors.white : unselectedIconColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isAuto
                              ? const Color(0xFF134E3F)
                              : unselectedTextColor),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.lightCyanTint,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$tag',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      key: Key('delete_tag_$tag'),
                      onTap: () => setState(() => _tags.remove(tag)),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.chipInactiveBorder,
                    width: 1.0,
                  ),
                ),
                child: TextField(
                  key: const Key('tag_input_field'),
                  controller: _tagInputController,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add custom tag...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('add_tag_button'),
              onPressed: _addCustomTag,
              icon: const Icon(
                Icons.add_circle_rounded,
                color: Color(0xFF134E3F),
                size: 28,
              ),
            ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackgroundOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          key: const Key('note_compose_back_button'),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimaryOf(context),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Add Note',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.subtleBorderOf(context), height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Title Input (Optional)
              Text(
                'Title (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.borderOf(context),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  key: const Key('note_title_field'),
                  controller: _titleController,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Project Ideas, Meeting Notes',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondaryOf(context),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 2. Note Content Input (Required)
              Text(
                'Note Content',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.borderOf(context),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  key: const Key('note_content_field'),
                  controller: _contentController,
                  minLines: 6,
                  maxLines: 12,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1E293B),
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write your thoughts, ideas, or notes here...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 3. Category Selector
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _buildCategorySelector(),

              const SizedBox(height: 20),

              // 4. Tags Section
              const Text(
                'Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _buildTagsSection(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            top: BorderSide(color: AppColors.chipInactiveBorder, width: 1.0),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const Key('save_note_button'),
              onPressed: _isSaving ? null : _saveNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textWhite,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Save Note',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
