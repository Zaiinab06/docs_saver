import 'dart:io';
import 'package:flutter/material.dart';
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

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
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

    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) {
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
        })
        .toList();

    if (lines.isEmpty) return '';
    return lines.take(2).join('\n');
  }

  Future<void> _unpinMemory(MemoryEntity memory) async {
    final newTags = List<String>.from(memory.tags)
      ..removeWhere((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin');

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
          await Supabase.instance.client.from('memories').update({
            'tags': newTags,
            'client_updated_at': DateTime.now().toIso8601String(),
          }).eq('id', memory.id);
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
        builder: (_) => MemoryDetailScreen(
          memoryId: memory.id,
          initialMemory: memory,
        ),
      ),
    );
  }

  Widget _buildSavedCard(MemoryEntity memory) {
    final cleanSnippet = _formatSnippet(memory.content);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.subtleBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppColors.primary,
                width: 4.0,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDetail(memory),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Thumbnail/Icon
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.lightCyanTint,
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
                                memory.title.isEmpty ? 'Untitled Note' : memory.title,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
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
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Unpin Button
                        IconButton(
                          icon: const Icon(
                            Icons.push_pin_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          tooltip: 'Unpin memory',
                          onPressed: () => _unpinMemory(memory),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
              child: const Icon(
                Icons.bookmark_border_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No saved memories yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Pinned memories will appear here. Pin important notes, links, or ideas from your Home screen to access them quickly.',
              style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.cardBackground,
        automaticallyImplyLeading: false,
        title: const Text(
          'Saved',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: AppColors.subtleBorder,
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<CaptureBloc, CaptureState>(
          builder: (context, state) {
            final allMemories =
                state is CaptureLoaded ? state.memories : <MemoryEntity>[];
            final savedMemories =
                allMemories.where((m) => m.isPinned).toList()
                  ..sort(MemoryEntity.compareByPinnedAndDate);

            if (state is CaptureLoading && allMemories.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              );
            }

            if (savedMemories.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.cardBackground,
              onRefresh: () async {
                context.read<CaptureBloc>().add(LoadMemoriesEvent());
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                itemCount: savedMemories.length,
                itemBuilder: (context, index) {
                  return _buildSavedCard(savedMemories[index]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
