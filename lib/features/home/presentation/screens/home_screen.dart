import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/isar_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../capture/data/models/memory_model.dart';
import '../../../capture/domain/entities/memory_entity.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/presentation/screens/memory_detail_screen.dart';
import '../../../capture/presentation/screens/photo_review_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import 'package:image_picker/image_picker.dart';

class _CategoryItem {
  final String name;
  final IconData icon;

  const _CategoryItem({
    required this.name,
    required this.icon,
  });
}

class HomeScreen extends StatefulWidget {
  final String? userName;

  const HomeScreen({super.key, this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategory = 'All';
  final Set<String> _locallyPinnedIds = {};
  final Set<String> _locallyUnpinnedIds = {};

  bool _isMemoryPinned(MemoryEntity memory) {
    if (_locallyUnpinnedIds.contains(memory.id)) return false;
    if (_locallyPinnedIds.contains(memory.id)) return true;
    return memory.isPinned;
  }

  Future<void> _togglePinMemory(MemoryEntity memory) async {
    final currentlyPinned = _isMemoryPinned(memory);
    setState(() {
      if (currentlyPinned) {
        _locallyPinnedIds.remove(memory.id);
        _locallyUnpinnedIds.add(memory.id);
      } else {
        _locallyUnpinnedIds.remove(memory.id);
        _locallyPinnedIds.add(memory.id);
      }
    });

    try {
      final isar = IsarService.instance;
      final model = await isar.memoryModels
          .filter()
          .serverIdEqualTo(memory.id)
          .findFirst();
      if (model != null) {
        final tags = List<String>.from(model.tags);
        if (currentlyPinned) {
          tags.removeWhere((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin');
        } else {
          if (!tags.contains('pinned')) {
            tags.add('pinned');
          }
        }
        model.tags = tags;
        await isar.writeTxn(() async {
          await isar.memoryModels.put(model);
        });
      }
    } catch (_) {}
  }

  void _shareMemory(MemoryEntity memory) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing "${memory.title.isEmpty ? "Memory" : memory.title}"...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteMemory(BuildContext context, MemoryEntity memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            AppStrings.dialogDeleteTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          content: const Text(
            AppStrings.dialogDeleteMessage,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                AppStrings.dialogCancel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.errorText,
              ),
              child: const Text(
                AppStrings.dialogDeleteConfirm,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.errorText,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _deleteMemory(memory);
    }
  }

  Future<void> _deleteMemory(MemoryEntity memory) async {
    try {
      final isar = IsarService.instance;
      await isar.writeTxn(() async {
        await isar.memoryModels
            .filter()
            .serverIdEqualTo(memory.id)
            .deleteAll();
      });
      try {
        await Supabase.instance.client
            .from('memories')
            .delete()
            .eq('id', memory.id);
      } catch (_) {}
      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (_) {}
  }

  Future<void> _openMemoryDetail(MemoryEntity memory) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryDetailScreen(
          memoryId: memory.id,
          initialMemory: memory,
        ),
      ),
    );
    if (mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  static const List<_CategoryItem> _categories = [
    _CategoryItem(
      name: 'All',
      icon: Icons.grid_view_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryWork,
      icon: Icons.work_outline_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryPersonal,
      icon: Icons.favorite_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryStudy,
      icon: Icons.school_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryTravel,
      icon: Icons.flight_takeoff_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryFashion,
      icon: Icons.shopping_bag_outlined,
    ),
    _CategoryItem(
      name: AppStrings.categoryFood,
      icon: Icons.restaurant_rounded,
    ),
    _CategoryItem(
      name: AppStrings.categoryFinance,
      icon: Icons.account_balance_wallet_outlined,
    ),
    _CategoryItem(
      name: AppStrings.categoryHealth,
      icon: Icons.fitness_center_rounded,
    ),
  ];

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    context.read<CaptureBloc>().add(LoadMemoriesEvent());
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (mounted) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
          setState(() {});
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  String _getUserName() {
    if (widget.userName != null && widget.userName!.trim().isNotEmpty) {
      return widget.userName!.trim();
    }
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final metadataName = user?.userMetadata?['full_name'] as String?;
      if (metadataName != null && metadataName.trim().isNotEmpty) {
        return metadataName.trim();
      }
      if (user?.email != null && user!.email!.isNotEmpty) {
        final emailPrefix = user.email!.split('@').first;
        if (emailPrefix.isNotEmpty) {
          return emailPrefix[0].toUpperCase() + emailPrefix.substring(1);
        }
      }
    } catch (_) {}
    return AppStrings.homeDefaultUser;
  }

  String _getUserInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'there') {
      return 'U';
    }
    return trimmed[0].toUpperCase();
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

  IconData _getMemoryIcon(MemoryEntity memory) {
    final cat = memory.category.toLowerCase();
    final tags = memory.tags.map((t) => t.toLowerCase()).toList();
    final content = memory.content.toLowerCase();

    if (memory.mediaUrl != null && memory.mediaUrl!.isNotEmpty) {
      return Icons.image_outlined;
    }
    if (content.startsWith('http://') || content.startsWith('https://') || tags.contains('link')) {
      return Icons.link_rounded;
    }
    if (cat.contains('video') || tags.any((t) => t.contains('video') || t.contains('youtube'))) {
      return Icons.play_circle_outline_rounded;
    }
    if (cat.contains('book') || tags.any((t) => t.contains('book') || t.contains('read'))) {
      return Icons.menu_book_rounded;
    }
    if (cat.contains('work') || tags.any((t) => t.contains('project') || t.contains('meeting'))) {
      return Icons.work_outline_rounded;
    }
    if (cat.contains('travel') || tags.any((t) => t.contains('travel') || t.contains('trip') || t.contains('flight'))) {
      return Icons.flight_takeoff_rounded;
    }
    if (cat.contains('fashion') || tags.any((t) => t.contains('fashion') || t.contains('shopping') || t.contains('clothes') || t.contains('outfit'))) {
      return Icons.shopping_bag_outlined;
    }
    if (cat.contains('food') || tags.any((t) => t.contains('food') || t.contains('restaurant') || t.contains('recipe') || t.contains('cooking') || t.contains('meal'))) {
      return Icons.restaurant_rounded;
    }
    if (cat.contains('finance') || tags.any((t) => t.contains('finance') || t.contains('money') || t.contains('budget') || t.contains('wallet') || t.contains('expense'))) {
      return Icons.account_balance_wallet_outlined;
    }
    if (cat.contains('health') || cat.contains('fitness') || tags.any((t) => t.contains('health') || t.contains('fitness') || t.contains('gym') || t.contains('workout'))) {
      return Icons.fitness_center_rounded;
    }
    return Icons.article_outlined;
  }

  Widget _buildMemoryThumbnail(MemoryEntity memory) {
    final media = memory.mediaUrl;
    if (media == null || media.isEmpty) {
      return Icon(
        _getMemoryIcon(memory),
        color: AppColors.primary,
        size: 22,
      );
    }
    if (media.startsWith('http://') || media.startsWith('https://')) {
      return Image.network(
        media,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          _getMemoryIcon(memory),
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
          _getMemoryIcon(memory),
          color: AppColors.primary,
          size: 22,
        ),
      );
    }
    return Icon(
      _getMemoryIcon(memory),
      color: AppColors.primary,
      size: 22,
    );
  }

  List<MemoryEntity> _filterMemories(List<MemoryEntity> memories) {
    if (_selectedCategory == 'All') return memories;

    final filter = _selectedCategory.toLowerCase();
    return memories.where((m) {
      final cat = m.category.toLowerCase();
      final tags = m.tags.map((t) => t.toLowerCase()).toList();

      if (_selectedCategory == AppStrings.categoryWork) {
        return cat == 'work' ||
            tags.any((t) => t.contains('work') || t.contains('project') || t.contains('meeting'));
      }
      if (_selectedCategory == AppStrings.categoryPersonal) {
        return cat == 'personal' ||
            tags.any((t) => t.contains('personal') || t.contains('idea') || t.contains('life'));
      }
      if (_selectedCategory == AppStrings.categoryStudy) {
        return cat == 'study' ||
            cat == 'learning' ||
            cat == 'book' ||
            tags.any((t) => t.contains('study') || t.contains('learn') || t.contains('book'));
      }
      if (_selectedCategory == AppStrings.categoryTravel) {
        return cat == 'travel' ||
            tags.any((t) => t.contains('travel') || t.contains('trip') || t.contains('flight'));
      }
      if (_selectedCategory == AppStrings.categoryFashion) {
        return cat == 'fashion' ||
            tags.any((t) => t.contains('fashion') || t.contains('shopping') || t.contains('clothes') || t.contains('outfit'));
      }
      if (_selectedCategory == AppStrings.categoryFood) {
        return cat == 'food' ||
            tags.any((t) => t.contains('food') || t.contains('restaurant') || t.contains('recipe') || t.contains('cooking') || t.contains('meal'));
      }
      if (_selectedCategory == AppStrings.categoryFinance) {
        return cat == 'finance' ||
            tags.any((t) => t.contains('finance') || t.contains('money') || t.contains('budget') || t.contains('wallet') || t.contains('expense'));
      }
      if (_selectedCategory == AppStrings.categoryHealth) {
        return cat == 'health' ||
            cat == 'fitness' ||
            tags.any((t) => t.contains('health') || t.contains('fitness') || t.contains('gym') || t.contains('workout'));
      }
      return cat == filter || tags.contains(filter);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userName = _getUserName();
    final userInitial = _getUserInitial(userName);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          bottom: true,
          child: BlocBuilder<CaptureBloc, CaptureState>(
          builder: (context, state) {
            final allMemories = state is CaptureLoaded ? state.memories : <MemoryEntity>[];
            final filteredMemories = _filterMemories(allMemories);
            final sortedMemories = List<MemoryEntity>.from(filteredMemories)
              ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));
            final isLoading = state is CaptureLoading && allMemories.isEmpty;

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.cardBackground,
              onRefresh: () async {
                context.read<CaptureBloc>().add(LoadMemoriesEvent());
                context.read<CaptureBloc>().add(SyncPendingMemoriesEvent());
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. Compact Cyan Rounded Header with Overlapping Search Bar (Reference Image 2 Style)
                  SliverToBoxAdapter(
                    child: _buildHeaderWithSearch(context, userName, userInitial),
                  ),

                  // 2. Categories Horizontal Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                      child: _buildCategoriesHeader(),
                    ),
                  ),

                  // 3. Categories Horizontal Scrollable List
                  SliverToBoxAdapter(
                    child: _buildCategoriesList(),
                  ),

                  // 4. Recent Memories Section Header (Visible ONLY when at least one memory exists for current filter)
                  if (!isLoading && sortedMemories.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                        child: _buildRecentMemoriesHeader(
                          showSeeAll: true,
                        ),
                      ),
                    ),

                  // 5. Dynamic Memory List or Clean Empty State
                  if (isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    )
                  else if (sortedMemories.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final memory = sortedMemories[index];
                            return _buildMemoryCard(memory);
                          },
                          childCount: sortedMemories.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),

      // Floating Action Button
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.38),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _showCaptureBottomSheet(context),
          backgroundColor: AppColors.primary,
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.add_rounded,
            color: AppColors.textWhite,
            size: 30,
          ),
        ),
      ),
    ),
  );
}

  // Capture Bottom Sheet Modal
  void _showCaptureBottomSheet(BuildContext context) {
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
                      isTakePhoto: true,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.document_scanner_outlined,
                      title: 'Scan Document',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.link_rounded,
                      title: 'Add Link',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.edit_note_rounded,
                      title: 'Add Note',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.mic_none_rounded,
                      title: 'Record Voice',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.attach_file_rounded,
                      title: 'Choose File',
                      isTakePhoto: false,
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

  Future<void> _handleTakePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1800,
      );

      if (photo == null) return; // User cancelled camera safely
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoReviewScreen(
            imageFile: File(photo.path),
          ),
        ),
      );

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message = errorMsg.contains('permission') || errorMsg.contains('denied')
            ? 'Camera permission denied. Please enable camera access in Settings.'
            : 'Unable to open camera: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCaptureOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool isTakePhoto,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          if (isTakePhoto) {
            await _handleTakePhoto();
          } else {
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text('$title capture flow will be available soon.'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.chipInactiveBorder,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.lightCyanTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
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

  // Compact Cyan/Blue Rounded Header with Subtle Network Pattern and Overlapping Search Bar
  Widget _buildHeaderWithSearch(BuildContext context, String userName, String userInitial) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Full width cyan/blue background container with large rounded bottom corners
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(30),
            ),
            child: Stack(
              children: [
                // Subtle connected-node/network pattern in background
                Positioned.fill(
                  child: CustomPaint(
                    painter: _NetworkPatternPainter(),
                  ),
                ),

                // Header Content: Greeting, Subtitle, Right actions
                Padding(
                  padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 70),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left: Prominent "Hello {userName} 👋" & Subtitle "Your second brain is ready"
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Hello $userName',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textWhite,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    '👋',
                                    style: TextStyle(
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              AppStrings.homeReadySubtitle,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textWhite.withValues(alpha: 0.88),
                                letterSpacing: -0.1,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Right: Bell notification & Profile avatar
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Bell button with notification dot
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('home_bell_btn'),
                              onTap: () {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No new notifications'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                      color: AppColors.textWhite,
                                      size: 20,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: AppColors.notificationBadge,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Profile Avatar [Dynamic Initial]
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('home_profile_avatar_btn'),
                              onTap: () {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                final isFallback =
                                    userName.toLowerCase() == 'there';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isFallback
                                          ? 'Your Second Brain'
                                          : '$userName\'s Second Brain',
                                    ),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.textWhite,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    userInitial,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Search Bar: Floating Input Pill overlapping the bottom edge of the cyan container
        Positioned(
          left: 20,
          right: 20,
          bottom: 0,
          child: _buildSearchBar(context),
        ),
      ],
    );
  }

  // Modern Floating Search Bar Pill
  Widget _buildSearchBar(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.homeSearchHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.lightCyanTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Section Header: Categories
  Widget _buildCategoriesHeader() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        AppStrings.homeCategoriesHeader,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  // Categories Horizontal List of Pill Cards
  Widget _buildCategoriesList() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _categories[index];
          final isSelected = _selectedCategory == item.name;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (_selectedCategory == item.name) {
                    _selectedCategory = 'All';
                  } else {
                    _selectedCategory = item.name;
                  }
                });
              },
              borderRadius: BorderRadius.circular(100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
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
                    width: isSelected ? 1.4 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
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
                      item.icon,
                      color: isSelected ? AppColors.textWhite : const Color(0xFF0096C7),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? AppColors.textWhite : const Color(0xFF0096C7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Section Header: Recent Memories
  Widget _buildRecentMemoriesHeader({required bool showSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          AppStrings.homeRecentMemoriesHeader,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        if (showSeeAll)
          InkWell(
            onTap: () {
              if (_selectedCategory != 'All') {
                setState(() {
                  _selectedCategory = 'All';
                });
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                AppStrings.homeSeeAll,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatSnippet(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  // Recent Memory Card
  Widget _buildMemoryCard(MemoryEntity memory) {
    final isPinned = _isMemoryPinned(memory);
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
          decoration: BoxDecoration(
            border: isPinned
                ? const Border(
                    left: BorderSide(
                      color: AppColors.primary,
                      width: 4.0,
                    ),
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openMemoryDetail(memory),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Container: Dynamic Icon or Image Thumbnail
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.lightCyanTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildMemoryThumbnail(memory),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Title & Category • Relative Time
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
                          Row(
                            children: [
                              Text(
                                '${memory.category} • ${_formatTimeAgo(memory.clientCreatedAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              // AI Status Indicator Dot
                              _buildAiStatusIndicator(memory.aiStatus),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Right Side: 3-Dots Popup Menu Button
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.iconSecondary,
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: AppColors.cardBackground,
                      onSelected: (value) {
                        if (value == 'pin') {
                          _togglePinMemory(memory);
                        } else if (value == 'share') {
                          _shareMemory(memory);
                        } else if (value == 'delete') {
                          _confirmDeleteMemory(context, memory);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isPinned ? AppStrings.menuUnpin : AppStrings.menuPin,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(
                                Icons.share_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 10),
                              Text(
                                AppStrings.menuShare,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.errorText,
                              ),
                              SizedBox(width: 10),
                              Text(
                                AppStrings.menuDelete,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.errorText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // 2-Line Snippet Preview (Clean, never large raw OCR block)
                if (cleanSnippet.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    cleanSnippet,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Dynamic Tag Chips with Light Cyan Background
                if (memory.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: memory.tags.take(4).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.lightCyanTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
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
    ),
  ),
);
  }

  // AI Status Indicator Dot / Icon
  Widget _buildAiStatusIndicator(String aiStatus) {
    if (aiStatus == 'pending') {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: 'AI Ingestion Pending',
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.statusPending,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    } else if (aiStatus == 'failed') {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: 'AI Ingestion Failed',
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.statusFailed,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    } else if (aiStatus == 'processed') {
      return const Padding(
        padding: EdgeInsets.only(left: 6),
        child: Tooltip(
          message: 'AI Processed',
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: AppColors.primary,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Clean Category-Aware Empty State
  Widget _buildEmptyState() {
    final String title;
    final String subtitle;

    if (_selectedCategory == 'All') {
      title = AppStrings.emptyBrainTitle;
      subtitle = AppStrings.emptyBrainSubtitle;
    } else {
      title = 'No $_selectedCategory memories yet';
      subtitle = 'Save your first $_selectedCategory memory using the + button.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 60.0),
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/homeempty.png',
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
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
      ),
    );
  }
}

/// Subtle connected-node / network pattern custom painter for header background
class _NetworkPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    // Node coordinates scattered across header background
    final nodes = [
      Offset(size.width * 0.10, size.height * 0.28),
      Offset(size.width * 0.26, size.height * 0.65),
      Offset(size.width * 0.45, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.58),
      Offset(size.width * 0.80, size.height * 0.26),
      Offset(size.width * 0.94, size.height * 0.60),
      Offset(size.width * 0.74, size.height * 0.82),
    ];

    final edges = [
      [0, 1],
      [1, 2],
      [0, 2],
      [2, 3],
      [3, 4],
      [3, 6],
      [4, 5],
      [6, 5],
    ];

    for (final edge in edges) {
      canvas.drawLine(nodes[edge[0]], nodes[edge[1]], linePaint);
    }

    for (final node in nodes) {
      canvas.drawCircle(node, 6, glowPaint);
      canvas.drawCircle(node, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

