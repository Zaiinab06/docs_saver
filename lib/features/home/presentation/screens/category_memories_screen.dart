import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../capture/domain/entities/memory_entity.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/presentation/screens/memory_detail_screen.dart';
import '../../../capture/presentation/screens/note_compose_screen.dart';
import '../../../capture/presentation/screens/voice_record_screen.dart';
import '../../../capture/presentation/widgets/add_link_dialog.dart';
import '../../../capture/presentation/widgets/bank_card_template_sheet.dart';
import '../../../capture/presentation/widgets/bill_template_sheet.dart';
import '../../domain/models/category_section.dart';

/// Dedicated Category Memories screen for displaying real memories
/// belonging to a specific child category, with dynamic empty state and capture integration.
class CategoryMemoriesScreen extends StatefulWidget {
  final CategoryCardItem category;
  final VoidCallback? onCaptureTap;

  const CategoryMemoriesScreen({
    super.key,
    required this.category,
    this.onCaptureTap,
  });

  @override
  State<CategoryMemoriesScreen> createState() => _CategoryMemoriesScreenState();
}

class _CategoryMemoriesScreenState extends State<CategoryMemoriesScreen> {
  CategoryCardItem get category => widget.category;

  @override
  void initState() {
    super.initState();
    final captureBloc = context.read<CaptureBloc>();
    if (captureBloc.state is! CaptureLoaded) {
      captureBloc.add(LoadMemoriesEvent());
    }
  }

  /// Dynamically matches a memory's category string with this category.
  bool _matchesCategory(String memoryCategory, String targetCategoryName) {
    final mem = memoryCategory.trim().toLowerCase();
    final target = targetCategoryName.trim().toLowerCase();
    if (mem == target) return true;

    // Compound targets: e.g. "Study & Education" matches "Study", "Education"
    if (target.contains('&')) {
      final parts = target
          .split('&')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty);
      for (final part in parts) {
        if (mem == part || mem.contains(part)) return true;
      }
    }

    // Direct containment: "Personal" in "Personal Life", etc.
    if (target.contains(mem) || mem.contains(target)) return true;

    return false;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }

  String _formatSnippet(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    return lines.take(3).join('\n');
  }

  void _handleCapture(BuildContext context) {
    if (widget.onCaptureTap != null) {
      widget.onCaptureTap!();
      return;
    }
    _showDefaultCaptureSheet(context);
  }

  void _showDefaultCaptureSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.chipInactiveBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'What do you want to save?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.camera_alt_outlined,
                        title: 'Take Photo',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.document_scanner_outlined,
                        title: 'Scan Document',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.link_rounded,
                        title: 'Add Link',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.edit_note_rounded,
                        title: 'Add Note',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.mic_none_rounded,
                        title: 'Record Voice',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.attach_file_rounded,
                        title: 'Choose File',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.cloud_download_outlined,
                        title: 'Google Drive',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.videocam_outlined,
                        title: 'Add Video',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCaptureOption({
    required BuildContext context,
    required IconData icon,
    required String title,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          if (title == 'Add Note') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NoteComposeScreen()),
            );
          } else if (title == 'Record Voice') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceRecordScreen()),
            );
          } else if (title == 'Add Link') {
            AddLinkBottomSheet.show(context);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.chipInactiveBorder, width: 1.0),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(MemoryEntity memory) {
    final media = memory.mediaUrl;
    final isVoice =
        memory.tags.any((t) => t.toLowerCase() == 'voice') ||
        (media != null &&
            (media.endsWith('.m4a') ||
                media.endsWith('.aac') ||
                media.endsWith('.mp3') ||
                media.endsWith('.wav')));

    if (isVoice) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.violetTwilight50,
        child: const Center(
          child: Icon(
            Icons.mic_rounded,
            color: AppColors.violetTwilight500,
            size: 22,
          ),
        ),
      );
    }
    if (media == null || media.isEmpty) {
      return Center(
        child: Icon(category.icon, color: category.iconColor, size: 22),
      );
    }
    if (media.startsWith('http://') || media.startsWith('https://')) {
      return Image.network(
        media,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(category.icon, color: category.iconColor, size: 22),
        ),
      );
    }
    final file = File(media);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(category.icon, color: category.iconColor, size: 22),
        ),
      );
    }
    return Center(
      child: Icon(category.icon, color: category.iconColor, size: 22),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Polished category icon in styled Violet Twilight circle
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: category.backgroundColor,
                shape: BoxShape.circle,
                border: Border.all(color: category.borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.violetTwilight500.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(category.icon, size: 40, color: category.iconColor),
              ),
            ),
            const SizedBox(height: 22),

            // Dynamic Empty State Title
            Text(
              'No ${category.name} yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.violetTwilight800,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Styled Action Button
            InkWell(
              key: const Key('empty_state_add_btn'),
              onTap: () {
                if (category.isCardTemplate) {
                  BankCardTemplateSheet.show(context);
                } else if (category.isBillTemplate) {
                  BillTemplateSheet.show(context);
                } else {
                  _handleCapture(context);
                }
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.violetTwilight500,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violetTwilight500.withValues(
                        alpha: 0.28,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category.isCardTemplate
                          ? Icons.credit_card_rounded
                          : category.isBillTemplate
                              ? Icons.receipt_long_rounded
                              : Icons.add_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      category.isCardTemplate
                          ? 'Add Card'
                          : category.isBillTemplate
                              ? 'Add Bill'
                              : 'Add Memory',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Helper text below button
            GestureDetector(
              key: const Key('empty_state_other_methods_btn'),
              onTap: () => _handleCapture(context),
              child: const Text(
                'or click + for other capture methods',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(BuildContext context, MemoryEntity memory) {
    final cleanSnippet = _formatSnippet(memory.content);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.violetTwilight500.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MemoryDetailScreen(
                  memoryId: memory.id,
                  initialMemory: memory,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Thumbnail
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: category.backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildThumbnail(memory),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Category • Time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memory.title.isEmpty
                                ? 'Untitled Note'
                                : memory.title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.violetTwilight900,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${memory.category} • ${_formatTimeAgo(memory.clientCreatedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.violetTwilight600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Chevron icon
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.violetTwilight400,
                      size: 22,
                    ),
                  ],
                ),

                if (cleanSnippet.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    cleanSnippet,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                if (memory.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: memory.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.violetTwilight50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.violetTwilight100,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.violetTwilight600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkCardBackground : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.violetTwilight800,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkBackground
                    : category.iconBackgroundColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? category.iconColor.withValues(alpha: 0.3)
                      : category.borderColor,
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(category.icon, size: 16, color: category.iconColor),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                category.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.violetTwilight800,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: isDark
                ? AppColors.darkSubtleBorder
                : AppColors.violetTwilight100.withValues(alpha: 0.5),
            height: 1.0,
          ),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<CaptureBloc, CaptureState>(
          builder: (context, state) {
            final allMemories = state is CaptureLoaded
                ? state.memories
                : <MemoryEntity>[];
            final categoryMemories = allMemories
                .where((m) => _matchesCategory(m.category, category.name))
                .toList();

            if (state is CaptureLoading && allMemories.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.violetTwilight500,
                  ),
                ),
              );
            }

            if (categoryMemories.isEmpty) {
              return RefreshIndicator(
                color: AppColors.violetTwilight500,
                backgroundColor: AppColors.cardBackgroundOf(context),
                onRefresh: () async {
                  context.read<CaptureBloc>().add(LoadMemoriesEvent());
                },
                child: _buildEmptyState(context),
              );
            }

            return RefreshIndicator(
              color: AppColors.violetTwilight500,
              backgroundColor: AppColors.cardBackgroundOf(context),
              onRefresh: () async {
                context.read<CaptureBloc>().add(LoadMemoriesEvent());
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                itemCount: categoryMemories.length,
                itemBuilder: (context, index) {
                  return _buildMemoryCard(context, categoryMemories[index]);
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('category_memories_add_btn'),
        heroTag: 'category_memories_fab',
        onPressed: () => _handleCapture(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 28,
        ),
      ),
    );
  }
}
