import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';

class _CategoryOption {
  final String name;
  final IconData icon;

  const _CategoryOption({
    required this.name,
    required this.icon,
  });
}

class MemoryReviewScreen extends StatefulWidget {
  final File imageFile;
  final String initialTitle;
  final String initialContent;
  final String initialCategory;
  final List<String> initialTags;
  final String initialSummary;
  final List<LivingEntityItem> entities;
  final String aiStatus; // 'processed' or 'pending' or 'failed'
  final DateTime createdAt;

  const MemoryReviewScreen({
    super.key,
    required this.imageFile,
    required this.initialTitle,
    required this.initialContent,
    required this.initialCategory,
    required this.initialTags,
    this.initialSummary = '',
    this.entities = const [],
    required this.aiStatus,
    required this.createdAt,
  });

  @override
  State<MemoryReviewScreen> createState() => _MemoryReviewScreenState();
}

class _MemoryReviewScreenState extends State<MemoryReviewScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final TextEditingController _tagInputController = TextEditingController();

  late String _selectedCategory;
  late List<String> _tags;
  late String _currentAiStatus;
  String _currentSummary = '';
  List<LivingEntityItem> _currentEntities = [];
  bool _isSaving = false;
  bool _isReanalyzing = false;

  static const List<_CategoryOption> _categories = [
    _CategoryOption(
      name: AppStrings.categoryWork,
      icon: Icons.work_outline_rounded,
    ),
    _CategoryOption(
      name: AppStrings.categoryPersonal,
      icon: Icons.favorite_rounded,
    ),
    _CategoryOption(
      name: AppStrings.categoryStudy,
      icon: Icons.school_rounded,
    ),
    _CategoryOption(
      name: AppStrings.categoryTravel,
      icon: Icons.flight_takeoff_rounded,
    ),
    _CategoryOption(
      name: AppStrings.categoryFashion,
      icon: Icons.shopping_bag_outlined,
    ),
    _CategoryOption(
      name: AppStrings.categoryFood,
      icon: Icons.restaurant_rounded,
    ),
    _CategoryOption(
      name: AppStrings.categoryFinance,
      icon: Icons.account_balance_wallet_outlined,
    ),
    _CategoryOption(
      name: AppStrings.categoryHealth,
      icon: Icons.fitness_center_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentAiStatus = widget.aiStatus;
    _currentSummary = widget.initialSummary;
    _currentEntities = List.from(widget.entities);

    _titleController = TextEditingController(text: widget.initialTitle);
    final initialContentText = widget.initialContent.trim().isNotEmpty
        ? widget.initialContent.trim()
        : widget.initialSummary.trim();
    _contentController = TextEditingController(text: initialContentText);
    _selectedCategory = widget.initialCategory.isNotEmpty
        ? widget.initialCategory
        : AppStrings.categoryPersonal;
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tagInputController.text.trim().replaceAll('#', '').toLowerCase();
    if (raw.isNotEmpty && !_tags.contains(raw)) {
      setState(() {
        _tags.add(raw);
        _tagInputController.clear();
      });
    }
  }

  Future<void> _retryAiAnalysis() async {
    setState(() => _isReanalyzing = true);

    try {
      String? imageBase64;
      String? mimeType;
      try {
        final fileSize = await widget.imageFile.length();
        if (fileSize < 8 * 1024 * 1024) {
          final imageBytes = await widget.imageFile.readAsBytes();
          imageBase64 = base64Encode(imageBytes);
          final extension = widget.imageFile.path.split('.').last.toLowerCase();
          mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
        }
      } catch (_) {}

      final useCase = IngestMemoryUseCase(
        AiRepositoryImpl(
          remoteDataSource: AiRemoteDataSourceImpl(),
        ),
      );

      final result = await useCase(
        ocrText: _contentController.text.trim(),
        imageBase64: imageBase64,
        mimeType: mimeType,
      );

      if (result.aiStatus == 'processed' && mounted) {
        setState(() {
          _currentAiStatus = 'processed';
          _selectedCategory = result.category;
          _currentSummary = result.summary;
          _currentEntities = result.entities;

          // Only set title if current title is empty
          if (_titleController.text.trim().isEmpty && result.title.isNotEmpty) {
            _titleController.text = result.title;
          }

          // If content is empty and summary exists, prefill content with summary
          if (_contentController.text.trim().isEmpty && result.summary.isNotEmpty) {
            _contentController.text = result.summary;
          }

          // Add meaningful tags
          for (final tag in result.tags) {
            if (!_tags.contains(tag)) {
              _tags.add(tag);
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI analysis completed!'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        if (mounted) {
          setState(() => _currentAiStatus = 'failed');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _currentAiStatus = 'failed');
      }
    } finally {
      if (mounted) {
        setState(() => _isReanalyzing = false);
      }
    }
  }

  Future<void> _saveMemory() async {
    setState(() => _isSaving = true);

    try {
      // 1. Persist the actual captured image locally in app storage
      final appDir = await getApplicationDocumentsDirectory();
      final extension = widget.imageFile.path.split('.').last;
      final fileName = 'memory_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final persistentFile = await widget.imageFile.copy('${appDir.path}/$fileName');
      String persistentMediaUrl = persistentFile.path;

      // Optional background upload to Supabase storage if reachable
      try {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          final bytes = await persistentFile.readAsBytes();
          final storageKey = '$currentUserId/$fileName';
          await Supabase.instance.client.storage.from('memories').uploadBinary(
                storageKey,
                bytes,
                fileOptions: FileOptions(contentType: 'image/$extension'),
              );
          final publicUrl = Supabase.instance.client.storage.from('memories').getPublicUrl(storageKey);
          if (publicUrl.isNotEmpty) {
            persistentMediaUrl = publicUrl;
          }
        }
      } catch (_) {
        // Fallback to local persistent path on network or bucket failure
      }

      if (!mounted) return;

      // Preserve user-entered title if present, otherwise use initial/generated title
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : (widget.initialTitle.trim().isNotEmpty
              ? widget.initialTitle.trim()
              : 'Captured Memory (${DateFormat('MMM d').format(DateTime.now())})');

      // Preserve user-edited content, otherwise use AI summary, otherwise OCR text
      final content = _contentController.text.trim().isNotEmpty
          ? _contentController.text.trim()
          : (_currentSummary.trim().isNotEmpty
              ? _currentSummary.trim()
              : (widget.initialContent.trim().isNotEmpty
                  ? widget.initialContent.trim()
                  : 'Captured Visual Memory'));

      // 2. Persist metadata through the existing repository and data layer
      context.read<CaptureBloc>().add(
            AddMemoryEvent(
              title: title,
              content: content,
              category: _selectedCategory,
              tags: _tags,
              mediaUrl: persistentMediaUrl,
              aiStatus: _currentAiStatus,
            ),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Memory saved to your Second Brain!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      // 3. Return to Home dynamically
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save memory: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(widget.createdAt);
    final isAiProcessed = _currentAiStatus == 'processed';
    final isAiFailed = _currentAiStatus == 'failed';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Review & Save',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Captured Photo Preview
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
                  ),
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. AI Status Banner & Timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isAiProcessed
                              ? AppColors.lightCyanTint
                              : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isAiProcessed
                                ? AppColors.primary
                                : (isAiFailed
                                    ? AppColors.errorText.withValues(alpha: 0.6)
                                    : AppColors.chipInactiveBorder),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAiProcessed
                                  ? Icons.auto_awesome_rounded
                                  : (isAiFailed
                                      ? Icons.info_outline_rounded
                                      : Icons.schedule_rounded),
                              size: 14,
                              color: isAiProcessed
                                  ? AppColors.primary
                                  : (isAiFailed
                                      ? AppColors.errorText
                                      : AppColors.textSecondary),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isAiProcessed
                                  ? 'AI Organized'
                                  : (isAiFailed
                                      ? 'AI Analysis Failed'
                                      : 'AI Ingestion Pending'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isAiProcessed
                                    ? AppColors.primary
                                    : (isAiFailed
                                        ? AppColors.errorText
                                        : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isAiProcessed) ...[
                        const SizedBox(width: 8),
                        if (_isReanalyzing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          )
                        else
                          InkWell(
                            onTap: _retryAiAnalysis,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Text(
                                'Analyze with AI',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // AI Summary Card (if available)
              if (_currentSummary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightCyanTint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'AI Summary',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentSummary,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // 3. Title Section
              const Text(
                'Title',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
                ),
                child: TextField(
                  controller: _titleController,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter title...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 4. Category Selector
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory == cat.name;

                    return InkWell(
                      onTap: () => setState(() => _selectedCategory = cat.name),
                      borderRadius: BorderRadius.circular(100),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFF00B4D8), Color(0xFF0096C7)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : const Color(0xFFEAFAFD),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF0096C7) : const Color(0xFFCCEBF5),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00B4D8).withValues(alpha: 0.25),
                                    blurRadius: 8,
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
                              color: isSelected ? AppColors.textWhite : const Color(0xFF0096C7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cat.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? AppColors.textWhite : const Color(0xFF0096C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // 5. Content / OCR Text
              const Text(
                'Content / Extracted Text',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
                ),
                child: TextField(
                  controller: _contentController,
                  minLines: 3,
                  maxLines: 7,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add notes or details about this photo...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 6. Tags
              const Text(
                'Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (_tags.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.lightCyanTint,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
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
                            onTap: () => setState(() => _tags.remove(tag)),
                            child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
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
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.chipInactiveBorder, width: 1.0),
                      ),
                      child: TextField(
                        controller: _tagInputController,
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Add tag...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addTag,
                    icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 28),
                  ),
                ],
              ),

              // Living Memory Knowledge Graph section (if entities detected)
              if (_currentEntities.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Living Memory Knowledge Graph',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _currentEntities.map((entity) {
                        return Container(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.chipInactiveBorder,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  entity.type.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: entity.name,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (entity.attributes.isNotEmpty)
                                        TextSpan(
                                          text: ' (${entity.attributes})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                            fontStyle: FontStyle.italic,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),

      // 7. Bottom Pinned "Save Memory" Action
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(top: BorderSide(color: AppColors.chipInactiveBorder, width: 1.0)),
        ),
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveMemory,
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
                            'Save Memory',
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
      ),
    );
  }
}
