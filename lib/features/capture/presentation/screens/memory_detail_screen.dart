import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/isar_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../data/models/memory_model.dart';
import '../../domain/entities/memory_entity.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';
import '../bloc/capture_state.dart';
import '../widgets/voice_audio_player_card.dart';

class _CategoryTheme {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;

  const _CategoryTheme({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
  });
}

class MemoryDetailScreen extends StatefulWidget {
  final String memoryId;
  final MemoryEntity? initialMemory;
  final List<LivingEntityItem>? initialEntities;
  final String? initialSummary;

  const MemoryDetailScreen({
    super.key,
    required this.memoryId,
    this.initialMemory,
    this.initialEntities,
    this.initialSummary,
  });

  @override
  State<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen> {
  MemoryEntity? _memory;
  bool _isLoading = true;
  bool _notFound = false;
  bool _isPinned = false;
  bool _isExtractedContentExpanded = false;
  bool _isKnowledgeGraphExpanded = false;
  String? _summary;
  List<LivingEntityItem> _entities = [];
  StreamSubscription? _blocSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null && widget.initialSummary!.trim().isNotEmpty) {
      _summary = widget.initialSummary!.trim();
    }
    if (widget.initialMemory != null) {
      _memory = widget.initialMemory;
      _isPinned = widget.initialMemory!.isPinned;
      _isLoading = false;
      if (_entities.isEmpty) {
        _entities = _buildEntitiesFromMemory(widget.initialMemory!);
      }
    }
    _loadMemoryFromLocalDb();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToBloc();
  }

  void _subscribeToBloc() {
    try {
      final bloc = context.read<CaptureBloc>();
      if (bloc.state is CaptureLoaded) {
        final found = (bloc.state as CaptureLoaded)
            .memories
            .where((m) => m.id == widget.memoryId);
        if (found.isNotEmpty) {
          final current = found.first;
          if (_memory == null ||
              _memory!.aiStatus != current.aiStatus ||
              _memory!.category != current.category ||
              _memory!.tags.length != current.tags.length) {
            _memory = current;
            _isPinned = current.isPinned;
            _isLoading = false;
            _notFound = false;
            _entities = _buildEntitiesFromMemory(current);
          }
        }
      }
      _blocSubscription?.cancel();
      _blocSubscription = bloc.stream.listen((state) {
        if (state is CaptureLoaded && mounted) {
          final found = state.memories.where((m) => m.id == widget.memoryId);
          if (found.isNotEmpty) {
            final updatedMemory = found.first;
            setState(() {
              _memory = updatedMemory;
              _isPinned = updatedMemory.isPinned;
              _isLoading = false;
              _notFound = false;
              _entities = _buildEntitiesFromMemory(updatedMemory);
            });
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMemoryFromLocalDb() async {
    try {
      final isar = IsarService.instance;
      final model = await isar.memoryModels
          .filter()
          .serverIdEqualTo(widget.memoryId)
          .findFirst();

      if (mounted) {
        if (model != null) {
          final entity = model.toEntity();
          setState(() {
            _memory = entity;
            _isPinned = entity.isPinned;
            _isLoading = false;
            _notFound = false;
            _entities = _buildEntitiesFromMemory(entity);
          });
        } else if (_memory == null) {
          setState(() {
            _isLoading = false;
            _notFound = true;
          });
        }
      }
    } catch (_) {
      if (mounted && _memory == null) {
        setState(() {
          _isLoading = false;
          _notFound = true;
        });
      }
    }
  }

  List<LivingEntityItem> _buildEntitiesFromMemory(MemoryEntity memory) {
    final List<LivingEntityItem> list = [];
    if (memory.category.isNotEmpty && memory.category != 'General') {
      list.add(
        LivingEntityItem(
          name: memory.category,
          type: 'CATEGORY',
          attributes: 'Primary categorization',
        ),
      );
    }
    final isManualNote = (memory.mediaUrl == null || memory.mediaUrl!.isEmpty) &&
        !memory.content.startsWith('http://') &&
        !memory.content.startsWith('https://');

    for (final tag in memory.tags) {
      final lower = tag.toLowerCase();
      if (lower == 'photo' || lower == 'document' || lower == 'pinned' || lower == 'pin') {
        continue;
      }
      list.add(
        LivingEntityItem(
          name: tag,
          type: 'TOPIC',
          attributes: isManualNote ? 'Note tag' : 'Extracted memory entity',
        ),
      );
    }
    return list;
  }

  String _formatOcrTextForPresentation(String text) {
    if (text.trim().isEmpty) return '(No additional text content recorded)';

    // 1. Normalize line endings and strip soft-hyphen artifacts
    String cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00AD', '');

    // 2. Re-stitch words split by hyphens at line breaks (e.g. "effec-\ntive" -> "effective", "import-\nant" -> "important", "result-\nant" -> "resultant")
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\b[a-zA-Z]+)\s*-\s*\n+\s*([a-zA-Z]+\b)'),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // 3. Process paragraph blocks separated by double-newlines
    final rawBlocks = cleaned.split(RegExp(r'\n\s*\n+'));
    final List<String> formattedBlocks = [];

    for (final block in rawBlocks) {
      final rawLines = block
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (rawLines.isEmpty) continue;

      final List<String> paragraphUnits = [];
      final StringBuffer currentParagraph = StringBuffer();

      for (int i = 0; i < rawLines.length; i++) {
        final line = rawLines[i];
        final isBulletOrList =
            RegExp(r'^([•\-\*–—]|(\d+[\.\)]|\([0-9a-zA-Z]+\)))\s+').hasMatch(line);
        final isHeaderOrLabel = line.endsWith(':') && line.length < 60;
        final isFormula = RegExp(
          r'^[A-Za-z0-9\s\(\)\^/_\+\-\*]+=[A-Za-z0-9\s\(\)\^/_\+\-\*]+$',
        ).hasMatch(line) && line.length < 50;

        if (isBulletOrList || isHeaderOrLabel || isFormula) {
          if (currentParagraph.isNotEmpty) {
            paragraphUnits.add(currentParagraph.toString().trim());
            currentParagraph.clear();
          }

          if (isHeaderOrLabel || isFormula) {
            paragraphUnits.add(line);
          } else {
            // Bullet or list item starts a unit so continuation lines can join it
            currentParagraph.write(line);
          }
        } else {
          if (currentParagraph.isEmpty) {
            currentParagraph.write(line);
          } else {
            currentParagraph.write(' ');
            currentParagraph.write(line);
          }
        }
      }

      if (currentParagraph.isNotEmpty) {
        paragraphUnits.add(currentParagraph.toString().trim());
      }

      if (paragraphUnits.isNotEmpty) {
        formattedBlocks.add(paragraphUnits.join('\n'));
      }
    }

    return formattedBlocks.join('\n\n');
  }

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('work')) {
      return Icons.work_outline_rounded;
    } else if (cat.contains('personal')) {
      return Icons.favorite_rounded;
    } else if (cat.contains('study') || cat.contains('learning')) {
      return Icons.school_rounded;
    } else if (cat.contains('travel')) {
      return Icons.flight_takeoff_rounded;
    } else if (cat.contains('fashion')) {
      return Icons.shopping_bag_outlined;
    } else if (cat.contains('food')) {
      return Icons.restaurant_rounded;
    } else if (cat.contains('finance')) {
      return Icons.account_balance_wallet_outlined;
    } else if (cat.contains('health') || cat.contains('fitness')) {
      return Icons.fitness_center_rounded;
    }
    return Icons.article_outlined;
  }

  _CategoryTheme _getCategoryTheme(String category) {
    return _CategoryTheme(
      icon: _getCategoryIcon(category),
      iconColor: AppColors.categoryChipDarkCyan,
      bgColor: AppColors.categoryChipBackground,
      borderColor: AppColors.categoryChipBorder,
    );
  }

  Future<void> _togglePin() async {
    if (_memory == null) return;
    final currentlyPinned = _isPinned;
    setState(() => _isPinned = !currentlyPinned);

    final newTags = List<String>.from(_memory!.tags);
    if (currentlyPinned) {
      newTags.removeWhere((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin');
    } else {
      if (!newTags.contains('pinned')) {
        newTags.add('pinned');
      }
    }

    _memory = MemoryEntity(
      id: _memory!.id,
      userId: _memory!.userId,
      title: _memory!.title,
      content: _memory!.content,
      mediaUrl: _memory!.mediaUrl,
      tags: newTags,
      category: _memory!.category,
      embedding: _memory!.embedding,
      aiStatus: _memory!.aiStatus,
      isConflictCopy: _memory!.isConflictCopy,
      clientCreatedAt: _memory!.clientCreatedAt,
      clientUpdatedAt: DateTime.now(),
      serverUpdatedAt: _memory!.serverUpdatedAt,
    );

    try {
      final isar = IsarService.instance;
      final model = await isar.memoryModels
          .filter()
          .serverIdEqualTo(_memory!.id)
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
          }).eq('id', _memory!.id);
          model.isSynced = true;
          await isar.writeTxn(() async {
            await isar.memoryModels.put(model);
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _shareMemory() {
    if (_memory == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing "${_memory!.title.isEmpty ? "Memory" : _memory!.title}"...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    if (_memory == null) return;
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
      await _deleteMemory();
    }
  }

  Future<void> _deleteMemory() async {
    if (_memory == null) return;
    try {
      final memoryId = _memory!.id;
      final isar = IsarService.instance;
      await isar.writeTxn(() async {
        await isar.memoryModels
            .filter()
            .serverIdEqualTo(memoryId)
            .deleteAll();
      });

      try {
        await Supabase.instance.client
            .from('memories')
            .delete()
            .eq('id', memoryId);
      } catch (_) {}

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
        Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  Widget _buildNotFoundView() {
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
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.lightCyanTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 36,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Memory Not Found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This thought or note may have been removed or deleted from your Second Brain.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview(String mediaUrl) {
    Widget imageWidget;
    if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
      imageWidget = Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildMediaFallback(),
      );
    } else {
      final file = File(mediaUrl);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildMediaFallback(),
        );
      } else {
        imageWidget = _buildMediaFallback();
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
        ),
        child: imageWidget,
      ),
    );
  }

  Widget _buildMediaFallback() {
    return Container(
      height: 160,
      color: AppColors.lightCyanTint,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 40,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildDocumentDetailCard(String mediaUrl) {
    final fileName = mediaUrl.split('/').last.split('\\').last.split('?').first;
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'DOC';
    final isPdf = ext == 'PDF';

    String fileSizeStr = '';
    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      try {
        final file = File(mediaUrl);
        if (file.existsSync()) {
          final bytes = file.lengthSync();
          if (bytes >= 1024 * 1024) {
            fileSizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          } else {
            fileSizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
          }
        }
      } catch (_) {}
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPdf ? const Color(0xFFFEE2E2) : AppColors.lightCyanTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                  color: isPdf ? const Color(0xFFDC2626) : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.isNotEmpty ? fileName : 'Document Attachment',
                      style: const TextStyle(
                        fontSize: 14.5,
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPdf ? const Color(0xFFFEE2E2) : AppColors.lightCyanTint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ext,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: isPdf ? const Color(0xFFDC2626) : AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (fileSizeStr.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            fileSizeStr,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  final Uri uri;
                  if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
                    uri = Uri.parse(mediaUrl);
                  } else {
                    uri = Uri.file(mediaUrl);
                  }
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open document: $fileName'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open document: $fileName'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiStatusBadge(MemoryEntity memory) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    final isVoice = memory.tags.any((t) => t.toLowerCase() == 'voice' || t.toLowerCase() == 'audio') ||
        (memory.mediaUrl != null &&
            (memory.mediaUrl!.endsWith('.m4a') ||
             memory.mediaUrl!.endsWith('.aac') ||
             memory.mediaUrl!.endsWith('.mp3') ||
             memory.mediaUrl!.endsWith('.wav') ||
             memory.mediaUrl!.endsWith('.ogg')));

    final isDocument = memory.tags.any((t) => t.toLowerCase() == 'document' || t.toLowerCase() == 'pdf') ||
        (memory.mediaUrl != null &&
            (memory.mediaUrl!.toLowerCase().endsWith('.pdf') ||
             memory.mediaUrl!.toLowerCase().endsWith('.txt') ||
             memory.mediaUrl!.toLowerCase().endsWith('.md') ||
             memory.mediaUrl!.toLowerCase().endsWith('.csv') ||
             memory.mediaUrl!.toLowerCase().endsWith('.json')));

    final isVoiceWithoutTranscript = isVoice && memory.content.trim().isEmpty;
    final isDocumentWithoutText = isDocument && memory.content.trim().isEmpty;

    if (memory.aiStatus == 'processed') {
      if (isVoiceWithoutTranscript) {
        bg = AppColors.categoryPersonalBackground;
        fg = AppColors.errorText;
        icon = Icons.error_outline_rounded;
        label = 'Transcription failed — audio preserved';
      } else if (isDocumentWithoutText) {
        bg = AppColors.categoryPersonalBackground;
        fg = AppColors.errorText;
        icon = Icons.error_outline_rounded;
        label = 'Extraction failed — file preserved';
      } else {
        bg = AppColors.lightCyanTint;
        fg = AppColors.primary;
        icon = Icons.auto_awesome_rounded;
        label = 'AI Organized';
      }
    } else if (memory.aiStatus == 'failed') {
      bg = AppColors.categoryPersonalBackground;
      fg = AppColors.errorText;
      icon = Icons.error_outline_rounded;
      label = isVoice
          ? 'Transcription failed — audio preserved'
          : (isDocument ? 'Extraction failed — file preserved' : 'AI Analysis Failed');
    } else if (memory.aiStatus == 'saved') {
      bg = AppColors.lightCyanTint;
      fg = AppColors.primary;
      icon = Icons.check_circle_outline_rounded;
      label = 'Saved';
    } else if (!memory.isSynced) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
      icon = Icons.cloud_off_rounded;
      label = 'Saved offline — will organize when online';
    } else {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
      icon = Icons.sync_rounded;
      label = 'Organizing your memory...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _memory == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

          if (_notFound || _memory == null) {
            return _buildNotFoundView();
          }

          final memory = _memory!;
          final categoryTheme = _getCategoryTheme(memory.category);
          final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(memory.clientCreatedAt);
          final hasMedia = memory.mediaUrl != null && memory.mediaUrl!.isNotEmpty;
          final trimmedContent = memory.content.trim();
          final isLink = trimmedContent.startsWith('http://') ||
              trimmedContent.startsWith('https://') ||
              memory.tags.any((t) => t.toLowerCase() == 'link');
          final linkUrl = isLink
              ? (trimmedContent.contains('\n')
                  ? trimmedContent.split('\n').first.trim()
                  : trimmedContent)
              : null;
          final isPureUrl = (trimmedContent.startsWith('http://') ||
                  trimmedContent.startsWith('https://')) &&
              !trimmedContent.contains(' ') &&
              !trimmedContent.contains('\n');
          final String extractedBody;
          if ((trimmedContent.startsWith('http://') || trimmedContent.startsWith('https://')) &&
              trimmedContent.contains('\n')) {
            extractedBody = trimmedContent.substring(trimmedContent.indexOf('\n')).trim();
          } else {
            extractedBody = trimmedContent;
          }
          final isVoiceMemory = memory.tags.any((t) => t.toLowerCase() == 'voice' || t.toLowerCase() == 'audio') ||
              (memory.mediaUrl != null &&
                  (memory.mediaUrl!.endsWith('.m4a') ||
                   memory.mediaUrl!.endsWith('.aac') ||
                   memory.mediaUrl!.endsWith('.mp3') ||
                   memory.mediaUrl!.endsWith('.wav') ||
                   memory.mediaUrl!.endsWith('.ogg')));
          final isDocumentMemory = memory.tags.any((t) => t.toLowerCase() == 'document' || t.toLowerCase() == 'pdf') ||
              (memory.mediaUrl != null &&
                  (memory.mediaUrl!.toLowerCase().endsWith('.pdf') ||
                   memory.mediaUrl!.toLowerCase().endsWith('.txt') ||
                   memory.mediaUrl!.toLowerCase().endsWith('.md') ||
                   memory.mediaUrl!.toLowerCase().endsWith('.csv') ||
                   memory.mediaUrl!.toLowerCase().endsWith('.json')));

          // Voice Transcript or Document text only appears when real content exists and is not an AI summary
          final hasExtractedContent = extractedBody.isNotEmpty &&
              extractedBody != '(No additional text content recorded)' &&
              !isPureUrl &&
              (!isVoiceMemory ||
                  (extractedBody.trim().isNotEmpty &&
                      (_summary == null || extractedBody.trim() != _summary!.trim()))) &&
              (!isDocumentMemory ||
                  (extractedBody.trim().isNotEmpty &&
                      (_summary == null || extractedBody.trim() != _summary!.trim())));

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
              title: Text(
                memory.category,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: _isPinned ? 'Unpin memory' : 'Pin memory',
                  icon: Icon(
                    _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: _isPinned ? AppColors.primary : AppColors.iconSecondary,
                  ),
                  onPressed: _togglePin,
                ),
                IconButton(
                  tooltip: 'Share memory',
                  icon: const Icon(Icons.share_outlined, color: AppColors.iconSecondary),
                  onPressed: _shareMemory,
                ),
                IconButton(
                  tooltip: 'Delete memory',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorText),
                  onPressed: _confirmDelete,
                ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Attached Media (Audio Player for voice, Document Card for documents, Image Preview for photos)
                    if (hasMedia) ...[
                      if (isVoiceMemory)
                        VoiceAudioPlayerCard(
                          audioSource: memory.mediaUrl!,
                        )
                      else if (isDocumentMemory)
                        _buildDocumentDetailCard(memory.mediaUrl!)
                      else
                        _buildMediaPreview(memory.mediaUrl!),
                      const SizedBox(height: 16),
                    ],

                    // 2. Title
                    Text(
                      memory.title.isEmpty ? 'Untitled Memory' : memory.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 3. Category & AI Status & Timestamp Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Category Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: categoryTheme.bgColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: categoryTheme.borderColor, width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(categoryTheme.icon, size: 14, color: categoryTheme.iconColor),
                              const SizedBox(width: 5),
                              Text(
                                memory.category,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: categoryTheme.iconColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // AI Status Badge
                        _buildAiStatusBadge(memory),

                        // Timestamp
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
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
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 4. Link Action Banner (if link detected)
                    if (isLink && linkUrl != null && linkUrl.isNotEmpty) ...[
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            final uri = Uri.tryParse(linkUrl);
                            if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                              try {
                                final launched = await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                                if (!launched && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not open link in browser.'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not open link in browser.'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.lightCyanTint,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.link_rounded, color: AppColors.primary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    linkUrl,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  color: AppColors.primary,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // AI Summary Card (when available and meaningful)
                    if (_summary != null &&
                        _summary!.isNotEmpty &&
                        (!isVoiceMemory || trimmedContent.isNotEmpty)) ...[
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
                              _summary!,
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
                      const SizedBox(height: 20),
                    ],

                    // Status banner for voice notes or documents when content is empty
                    if ((isVoiceMemory || isDocumentMemory) && trimmedContent.isEmpty) ...[
                      if (memory.aiStatus == 'failed' || memory.aiStatus == 'processed') ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.categoryPersonalBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.errorBorder,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.errorText,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isVoiceMemory
                                      ? 'Transcription failed — audio preserved'
                                      : 'Extraction failed — file preserved',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.errorText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.lightCyanTint.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  memory.isSynced
                                      ? (isVoiceMemory
                                          ? 'Transcribing and organizing audio...'
                                          : 'Extracting and organizing document...')
                                      : (isVoiceMemory
                                          ? 'Audio saved offline. Transcription will begin when online.'
                                          : 'Document saved offline. Text extraction will begin when online.'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    // 5. Extracted Content (Collapsible / Compact Card)
                    if (hasExtractedContent) ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.chipInactiveBorder,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: _isExtractedContentExpanded
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _isExtractedContentExpanded = false;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.lightCyanTint,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  isVoiceMemory
                                                      ? Icons.record_voice_over_rounded
                                                      : (isDocumentMemory
                                                          ? Icons.description_outlined
                                                          : Icons.document_scanner_rounded),
                                                  color: AppColors.primary,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      isVoiceMemory
                                                          ? 'Voice Transcript'
                                                          : (isDocumentMemory
                                                              ? 'Document Content'
                                                              : 'Extracted Content'),
                                                      style: const TextStyle(
                                                        fontSize: 14.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.textPrimary,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      isVoiceMemory
                                                          ? 'Spoken words transcribed from audio'
                                                          : (isDocumentMemory
                                                              ? 'Text extracted from document'
                                                              : 'See what was extracted from your memory'),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          'Hide extracted text',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: AppColors.primary,
                                                          ),
                                                        ),
                                                        SizedBox(width: 2),
                                                        Icon(
                                                          Icons.keyboard_arrow_up_rounded,
                                                          color: AppColors.primary,
                                                          size: 18,
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
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: AppColors.chipInactiveBorder,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                                        child: SelectableText(
                                          _formatOcrTextForPresentation(extractedBody),
                                          style: const TextStyle(
                                            fontSize: 15.5,
                                            color: AppColors.textPrimary,
                                            height: 1.55,
                                            letterSpacing: -0.1,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      setState(() {
                                        _isExtractedContentExpanded = true;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: AppColors.lightCyanTint,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              isVoiceMemory
                                                  ? Icons.record_voice_over_rounded
                                                  : (isDocumentMemory
                                                      ? Icons.description_outlined
                                                      : Icons.document_scanner_rounded),
                                              color: AppColors.primary,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isVoiceMemory
                                                      ? 'Voice Transcript'
                                                      : (isDocumentMemory
                                                          ? 'Document Content'
                                                          : 'Extracted Content'),
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.textPrimary,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  isVoiceMemory
                                                      ? 'Spoken words transcribed from audio'
                                                      : (isDocumentMemory
                                                          ? 'Text extracted from document'
                                                          : 'See what was extracted from your memory'),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                    color: AppColors.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'View extracted text',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppColors.primary,
                                                      ),
                                                    ),
                                                    SizedBox(width: 2),
                                                    Icon(
                                                      Icons.chevron_right_rounded,
                                                      color: AppColors.primary,
                                                      size: 18,
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
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 6. Living Memory Knowledge Graph Card (Immediately below Extracted Content, collapsed by default)
                    if (_entities.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.chipInactiveBorder,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: _isKnowledgeGraphExpanded
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _isKnowledgeGraphExpanded = false;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.lightCyanTint,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.hub_outlined,
                                                  color: AppColors.primary,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Living Memory Knowledge Graph',
                                                      style: TextStyle(
                                                        fontSize: 14.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.textPrimary,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Category & Topic relationships',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                color: AppColors.primary,
                                                size: 22,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: AppColors.chipInactiveBorder,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            return Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _entities.map((entity) {
                                                return Container(
                                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.background,
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
                                      ),
                                    ],
                                  )
                                : InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      setState(() {
                                        _isKnowledgeGraphExpanded = true;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: AppColors.lightCyanTint,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.hub_outlined,
                                              color: AppColors.primary,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Living Memory Knowledge Graph',
                                                  style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.textPrimary,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Category & Topic relationships',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                    color: AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.primary,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 7. Tags Card (VERY LAST section, always expanded)
                    if (memory.tags.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.chipInactiveBorder,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.lightCyanTint,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.tag_rounded,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tags',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Associated memory tags',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.chipInactiveBorder,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: memory.tags.map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.lightCyanTint,
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
  }
}
