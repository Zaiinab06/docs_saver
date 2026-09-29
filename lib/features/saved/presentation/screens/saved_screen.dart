import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/isar_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../capture/data/models/memory_model.dart';
import '../../../capture/domain/entities/memory_entity.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/presentation/screens/memory_detail_screen.dart';

enum SavedTab { all, pinned }

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  SavedTab _selectedTab = SavedTab.all;

  // ─── Multi-select state ────────────────────────────────────────────────────

  final Set<String> _selectedMemoryIds = {};

  bool get _isSelectionMode => _selectedMemoryIds.isNotEmpty;

  void _enterSelection(String id) {
    setState(() => _selectedMemoryIds.add(id));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedMemoryIds.contains(id)) {
        _selectedMemoryIds.remove(id);
      } else {
        _selectedMemoryIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedMemoryIds.clear());
  }

  void _selectAll(List<MemoryEntity> visible) {
    setState(() {
      final allIds = visible.map((m) => m.id).toSet();
      if (_selectedMemoryIds.containsAll(allIds)) {
        // All already selected → deselect all
        _selectedMemoryIds.removeAll(allIds);
      } else {
        _selectedMemoryIds.addAll(allIds);
      }
    });
  }

  Future<void> _confirmBatchDelete(List<MemoryEntity> visible) async {
    final count = _selectedMemoryIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'Memory' : 'Memories'}?'),
        content: Text(
          'This will permanently delete $count selected '
          '${count == 1 ? 'memory' : 'memories'}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final idsToDelete = Set<String>.from(_selectedMemoryIds);
      _clearSelection();
      for (final id in idsToDelete) {
        context.read<CaptureBloc>().add(DeleteMemoryEvent(id));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count ${count == 1 ? 'memory' : 'memories'} deleted.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

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

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('work')) return Icons.work_rounded;
    if (cat.contains('personal')) return Icons.favorite_rounded;
    if (cat.contains('study')) return Icons.school_rounded;
    if (cat.contains('travel')) return Icons.flight_takeoff_rounded;
    if (cat.contains('fashion')) return Icons.shopping_bag_rounded;
    if (cat.contains('food')) return Icons.restaurant_rounded;
    if (cat.contains('finance')) return Icons.account_balance_wallet_rounded;
    if (cat.contains('health')) return Icons.fitness_center_rounded;
    return Icons.article_rounded;
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
        color: AppColors.lightCyanTint,
        child: const Center(
          child: Icon(Icons.mic_rounded, color: AppColors.primary, size: 22),
        ),
      );
    }
    if (media == null || media.isEmpty) {
      return Icon(
        _getCategoryIcon(memory.category),
        color: AppColors.primary,
        size: 22,
      );
    }
    if (media.startsWith('http://') || media.startsWith('https://')) {
      return Image.network(
        media,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          _getCategoryIcon(memory.category),
          color: AppColors.primary,
          size: 22,
        ),
      );
    }
    final file = File(media);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          _getCategoryIcon(memory.category),
          color: AppColors.primary,
          size: 22,
        ),
      );
    }
    return Icon(
      _getCategoryIcon(memory.category),
      color: AppColors.primary,
      size: 22,
    );
  }

  String _formatSnippet(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    if ((trimmed.startsWith('http://') || trimmed.startsWith('https://')) &&
        !trimmed.contains('\n') &&
        !trimmed.contains(' ')) {
      return trimmed;
    }

    final lines = trimmed.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((
      l,
    ) {
      if (l.isEmpty) return false;
      if (l.startsWith('http://') ||
          l.startsWith('https://') ||
          l.startsWith('www.')) {
        return false;
      }
      if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(l) && l.length < 20) {
        return false;
      }
      if (RegExp(r'^\d{1,3}%\s*$').hasMatch(l)) {
        return false;
      }
      return true;
    }).toList();

    if (lines.isEmpty) return '';
    return lines.take(2).join('\n');
  }

  Future<void> _togglePinMemory(MemoryEntity memory) async {
    final currentlyPinned = memory.isPinned;
    final newTags = List<String>.from(memory.tags);
    if (currentlyPinned) {
      newTags.removeWhere(
        (t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin',
      );
    } else {
      if (!newTags.contains('pinned')) {
        newTags.add('pinned');
      }
    }

    try {
      final isar = IsarService.instance;
      final model = await isar.memoryModels
          .filter()
          .serverIdEqualTo(memory.id)
          .findFirst();
      if (model != null) {
        model.tags = newTags;
        model.isSynced = false;
        model.clientUpdatedAt = DateTime.now();
        await isar.writeTxn(() async {
          await isar.memoryModels.put(model);
        });

        try {
          await Supabase.instance.client
              .from('memories')
              .update({
                'tags': newTags,
                'client_updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', memory.id);
          model.isSynced = true;
          await isar.writeTxn(() async {
            await isar.memoryModels.put(model);
          });
        } catch (_) {}
      }
    } catch (_) {}

    final updatedMemory = MemoryEntity(
      id: memory.id,
      userId: memory.userId,
      title: memory.title,
      content: memory.content,
      mediaUrl: memory.mediaUrl,
      tags: newTags,
      category: memory.category == 'pinned' ? 'General' : memory.category,
      embedding: memory.embedding,
      aiStatus: memory.aiStatus,
      isConflictCopy: memory.isConflictCopy,
      clientCreatedAt: memory.clientCreatedAt,
      clientUpdatedAt: DateTime.now(),
      serverUpdatedAt: memory.serverUpdatedAt,
    );

    if (mounted) {
      try {
        await context.read<CaptureBloc>().saveMemoryUseCase(updatedMemory);
      } catch (_) {}
      if (mounted) {
        context.read<CaptureBloc>().add(MemoryUpdatedEvent(updatedMemory));
      }
    }
  }

  void _openDetail(MemoryEntity memory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MemoryDetailScreen(memoryId: memory.id, initialMemory: memory),
      ),
    );
  }

  // ─── Card ──────────────────────────────────────────────────────────────────

  Widget _buildSavedCard(MemoryEntity memory) {
    final cleanSnippet = _formatSnippet(memory.content);
    final isSelected = _selectedMemoryIds.contains(memory.id);

    return GestureDetector(
      onLongPress: () {
        if (!_isSelectionMode) {
          _enterSelection(memory.id);
        }
      },
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(memory.id);
        } else {
          _openDetail(memory);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          // Selected tint over card background
          color: isSelected
              ? const Color(0xFF0F3E32).withValues(alpha: 0.08)
              : AppColors.cardBackgroundOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.subtleBorderOf(context),
            width: isSelected ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Card content
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primary,
                      width: 4.0,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left Thumbnail/Icon — unchanged in selection mode
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceTintOf(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildThumbnail(memory),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Title & Category • Time
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  memory.title.isEmpty
                                      ? 'Untitled Note'
                                      : memory.title,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${memory.category} • ${_formatTimeAgo(memory.clientCreatedAt)}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // In selection mode: show checkbox-style indicator
                          // In normal mode: show pin button
                          if (_isSelectionMode)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                // RED when selected, transparent when not
                                color: isSelected
                                    ? const Color(0xFFEF4444)
                                    : Colors.transparent,
                                border: Border.all(
                                  // Red border when selected, muted grey when not
                                  color: isSelected
                                      ? const Color(0xFFEF4444)
                                      : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 12,
                                    )
                                  : null,
                            )
                          else
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: IconButton(
                                icon: Icon(
                                  memory.isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  color: memory.isPinned
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 18,
                                ),
                                tooltip: memory.isPinned
                                    ? 'Unpin memory'
                                    : 'Pin memory',
                                padding: EdgeInsets.zero,
                                onPressed: () => _togglePinMemory(memory),
                              ),
                            ),
                        ],
                      ),

                      if (cleanSnippet.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          cleanSnippet,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(List<MemoryEntity> displayedMemories) {
    final topPad = MediaQuery.of(context).viewPadding.top + 16;
    const color = Color(0xFF0F3E32);

    if (_isSelectionMode) {
      final allVisible = displayedMemories.map((m) => m.id).toSet();
      final allSelected = allVisible.isNotEmpty &&
          _selectedMemoryIds.containsAll(allVisible);

      return Container(
        width: double.infinity,
        color: color,
        padding: EdgeInsets.only(
          top: topPad,
          bottom: 12,
          left: 4,
          right: 4,
        ),
        child: Row(
          children: [
            // Cancel selection
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 22),
              onPressed: _clearSelection,
              tooltip: 'Cancel selection',
            ),
            // Count
            Expanded(
              child: Text(
                '${_selectedMemoryIds.length} Selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Select All / Deselect All
            TextButton.icon(
              onPressed: () => _selectAll(displayedMemories),
              icon: Icon(
                allSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                allSelected ? 'Deselect' : 'All',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
            // Delete
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 22,
              ),
              tooltip: 'Delete selected',
              onPressed: () => _confirmBatchDelete(displayedMemories),
            ),
          ],
        ),
      );
    }

    // Normal header
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.only(
        top: topPad,
        bottom: 20,
        left: 20,
        right: 20,
      ),
      child: const Text(
        'Saved Memories',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ─── Tab Switcher ──────────────────────────────────────────────────────────

  Widget _buildSegmentedControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.toggleBackgroundOf(context),
              borderRadius: BorderRadius.circular(100),
              border:
                  Border.all(color: AppColors.borderOf(context), width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabItem(
                    key: const Key('saved_tab_all'),
                    title: 'All',
                    isSelected: _selectedTab == SavedTab.all,
                    onTap: () {
                      if (_selectedTab != SavedTab.all) {
                        setState(() => _selectedTab = SavedTab.all);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabItem(
                    key: const Key('saved_tab_pinned'),
                    title: 'Pinned',
                    isSelected: _selectedTab == SavedTab.pinned,
                    onTap: () {
                      if (_selectedTab != SavedTab.pinned) {
                        setState(() => _selectedTab = SavedTab.pinned);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    Key? key,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? AppColors.textWhite
                  : AppColors.textSecondaryOf(context),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final isPinnedTab = _selectedTab == SavedTab.pinned;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.lightCyanTint,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.categoryChipBorder,
                  width: 1.5,
                ),
              ),
              child: Icon(
                isPinnedTab
                    ? Icons.push_pin_outlined
                    : Icons.bookmark_border_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isPinnedTab ? 'No pinned memories yet' : 'No saved memories yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isPinnedTab
                  ? 'Pin important notes, links, or ideas from your Home screen to access them quickly.'
                  : 'Pinned memories will appear here. Pin important notes, links, or ideas from your Home screen to access them quickly.',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0F3E32),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        // Back button in selection mode exits selection instead of navigating
        canPop: !_isSelectionMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isSelectionMode) {
            _clearSelection();
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: BlocBuilder<CaptureBloc, CaptureState>(
            builder: (context, state) {
              final allMemories = state is CaptureLoaded
                  ? state.memories
                  : <MemoryEntity>[];
              final pinnedMemories =
                  allMemories.where((m) => m.isPinned).toList()
                    ..sort(MemoryEntity.compareByPinnedAndDate);
              final sortedAllMemories =
                  List<MemoryEntity>.from(allMemories)
                    ..sort(MemoryEntity.compareByPinnedAndDate);

              final displayedMemories = _selectedTab == SavedTab.all
                  ? sortedAllMemories
                  : pinnedMemories;

              return Column(
                children: [
                  // ── Dynamic header (normal / selection mode) ────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey<bool>(_isSelectionMode),
                      child: _buildHeader(displayedMemories),
                    ),
                  ),

                  // ── Tab switcher + animated list ────────────────────────
                  Expanded(
                    child: () {
                      if (state is CaptureLoading && allMemories.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          _buildSegmentedControl(),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (
                                Widget child,
                                Animation<double> animation,
                              ) {
                                final isForward =
                                    _selectedTab == SavedTab.pinned;
                                final slideIn = Tween<Offset>(
                                  begin: Offset(
                                    isForward ? 0.15 : -0.15,
                                    0.0,
                                  ),
                                  end: Offset.zero,
                                ).animate(animation);
                                return SlideTransition(
                                  position: slideIn,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: displayedMemories.isEmpty
                                  ? KeyedSubtree(
                                      key: ValueKey<int>(
                                        _selectedTab.index * 10,
                                      ),
                                      child: _buildEmptyState(),
                                    )
                                  : KeyedSubtree(
                                      key: ValueKey<int>(_selectedTab.index),
                                      child: RefreshIndicator(
                                        color: AppColors.primary,
                                        backgroundColor:
                                            AppColors.cardBackgroundOf(context),
                                        onRefresh: () async {
                                          context.read<CaptureBloc>().add(
                                            LoadMemoriesEvent(),
                                          );
                                        },
                                        child: ListView.builder(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                            bottom: 80,
                                          ),
                                          physics:
                                              const AlwaysScrollableScrollPhysics(
                                            parent: BouncingScrollPhysics(),
                                          ),
                                          itemCount: displayedMemories.length,
                                          itemBuilder: (context, index) {
                                            return _buildSavedCard(
                                              displayedMemories[index],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      );
                    }(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
