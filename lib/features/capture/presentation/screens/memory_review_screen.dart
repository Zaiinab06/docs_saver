import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/network/network_checker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import '../../domain/repositories/capture_repository_impl.dart';
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
  final File? imageFile;
  final File? documentFile;
  final String? linkUrl;
  final String? readableContent;
  final String? previewImageUrl;
  final String initialTitle;
  final String initialContent;
  final String? rawOcrText;
  final String initialCategory;
  final List<String> initialTags;
  final String initialSummary;
  final List<LivingEntityItem> entities;
  final String aiStatus; // 'processed' or 'pending' or 'failed'
  final DateTime createdAt;
  final bool? isOffline;
  final IngestMemoryUseCase? ingestMemoryUseCase;

  const MemoryReviewScreen({
    super.key,
    this.imageFile,
    this.documentFile,
    this.linkUrl,
    this.readableContent,
    this.previewImageUrl,
    required this.initialTitle,
    required this.initialContent,
    this.rawOcrText,
    required this.initialCategory,
    required this.initialTags,
    this.initialSummary = '',
    this.entities = const [],
    required this.aiStatus,
    required this.createdAt,
    this.isOffline,
    this.ingestMemoryUseCase,
  });

  @override
  State<MemoryReviewScreen> createState() => _MemoryReviewScreenState();
}

class _MemoryReviewScreenState extends State<MemoryReviewScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final TextEditingController _tagInputController = TextEditingController();

  late String _selectedCategory;
  late List<String> _tags;
  late String _currentAiStatus;
  String _currentSummary = '';
  List<LivingEntityItem> _currentEntities = [];
  late String _rawOcrText;
  bool _isExtractedExpanded = false;
  bool _isSaving = false;
  bool _isReanalyzing = false;
  bool _isOffline = false;
  bool _userEditedTitle = false;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _localCheckTimer;

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
    WidgetsBinding.instance.addObserver(this);
    _currentAiStatus = widget.aiStatus;
    _currentSummary = widget.initialSummary;
    _currentEntities = List.from(widget.entities);
    _rawOcrText = (widget.readableContent != null && widget.readableContent!.trim().isNotEmpty)
        ? widget.readableContent!.trim()
        : (widget.rawOcrText ?? widget.initialContent);

    _isOffline = widget.isOffline ?? false;
    if (widget.isOffline == null) {
      _checkConnectivity();
    }

    _connectivitySubscription =
        NetworkChecker.onConnectivityChanged.listen((connected) {
      if (mounted && _isOffline != !connected) {
        setState(() {
          _isOffline = !connected;
        });
      }
    });

    NetworkChecker.startMonitoring();

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _localCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_isOffline && mounted) {
          _checkConnectivity();
        }
      });
    }

    _titleController = TextEditingController(text: widget.initialTitle);
    _titleController.addListener(() {
      if (_titleController.text.trim() != widget.initialTitle.trim()) {
        _userEditedTitle = true;
      }
    });

    final initialContentText = widget.documentFile != null
        ? widget.initialContent.trim()
        : (widget.initialSummary.trim().isNotEmpty
            ? widget.initialSummary.trim()
            : (widget.rawOcrText != null
                ? widget.initialContent.trim()
                : (widget.initialContent.trim() == _rawOcrText.trim() ? '' : widget.initialContent.trim())));
    _contentController = TextEditingController(text: initialContentText);
    _selectedCategory = widget.initialCategory.isNotEmpty
        ? widget.initialCategory
        : AppStrings.categoryPersonal;
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
    }
  }

  Future<void> _checkConnectivity() async {
    final connected = await NetworkChecker.isConnected();
    if (mounted && _isOffline != !connected) {
      setState(() {
        _isOffline = !connected;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _localCheckTimer?.cancel();
    NetworkChecker.stopMonitoring();
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
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI analysis unavailable offline. Please connect to the internet and try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final isConnected = await NetworkChecker.isConnected();
    if (!isConnected) {
      if (mounted) {
        setState(() => _isOffline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI analysis unavailable offline. Please connect to the internet and try again.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isReanalyzing = true);

    try {
      String? imageBase64;
      String? documentBase64;
      String? mimeType;
      try {
        if (widget.documentFile != null && widget.documentFile!.existsSync()) {
          final fileSize = widget.documentFile!.lengthSync();
          if (fileSize < 15 * 1024 * 1024) {
            final docBytes = widget.documentFile!.readAsBytesSync();
            documentBase64 = base64Encode(docBytes);
            final extension = widget.documentFile!.path.split('.').last.toLowerCase();
            mimeType = CaptureRepositoryImpl.resolveMimeType(extension);
          }
        } else if (widget.imageFile != null && widget.imageFile!.existsSync()) {
          final fileSize = widget.imageFile!.lengthSync();
          if (fileSize < 8 * 1024 * 1024) {
            final imageBytes = widget.imageFile!.readAsBytesSync();
            imageBase64 = base64Encode(imageBytes);
            final extension = widget.imageFile!.path.split('.').last.toLowerCase();
            mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
          }
        }
      } catch (_) {
        // Fallback to text-only if reading file fails
      }

      final useCase = widget.ingestMemoryUseCase ??
          IngestMemoryUseCase(
            AiRepositoryImpl(
              remoteDataSource: AiRemoteDataSourceImpl(),
            ),
          );

      final result = await useCase(
        ocrText: _rawOcrText.trim(),
        imageBase64: imageBase64,
        documentBase64: documentBase64,
        mimeType: mimeType,
      );

      final bool isDoc = widget.documentFile != null;
      final bool isSuccess = isDoc
          ? (result.aiStatus == 'processed' &&
              result.documentText != null &&
              result.documentText!.trim().isNotEmpty)
          : (result.aiStatus == 'processed');

      if (isSuccess && mounted) {
        setState(() {
          _currentAiStatus = 'processed';
          _selectedCategory = result.category;
          _currentSummary = result.summary;
          _currentEntities = result.entities;

          // Only set title if user has not manually edited it
          if (!_userEditedTitle && result.title.isNotEmpty) {
            _titleController.text = result.title;
          }

          // For documents, if documentText is extracted and content was empty, set it
          if (widget.documentFile != null) {
            if (_contentController.text.trim().isEmpty &&
                result.documentText != null &&
                result.documentText!.isNotEmpty) {
              _contentController.text = result.documentText!;
            }
          } else {
            // If content is empty or unedited raw OCR, prefill content with summary
            if ((_contentController.text.trim().isEmpty || _contentController.text.trim() == _rawOcrText.trim()) && result.summary.isNotEmpty) {
              _contentController.text = result.summary;
            }
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI analysis failed. Tap Retry to try again.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _currentAiStatus = 'failed');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI analysis failed. Tap Retry to try again.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
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
      // 1. Persist the actual captured image or document locally in app storage
      String? persistentMediaUrl = widget.previewImageUrl;
      if (widget.documentFile != null) {
        persistentMediaUrl = widget.documentFile!.path;
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final extension = widget.documentFile!.path.split('.').last;
          final fileName = 'doc_${DateTime.now().millisecondsSinceEpoch}.$extension';
          final docDir = Directory('${appDir.path}/documents');
          if (!docDir.existsSync()) {
            docDir.createSync(recursive: true);
          }
          final persistentFile = widget.documentFile!.copySync('${docDir.path}/$fileName');
          persistentMediaUrl = persistentFile.path;

          // Optional background upload to Supabase storage if reachable
          try {
            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
            if (currentUserId != null && currentUserId != 'local_user') {
              final bytes = persistentFile.readAsBytesSync();
              final storageKey = '$currentUserId/$fileName';
              final mime = CaptureRepositoryImpl.resolveMimeType(extension);
              await Supabase.instance.client.storage.from('memories').uploadBinary(
                    storageKey,
                    bytes,
                    fileOptions: FileOptions(contentType: mime),
                  );
              final publicUrl = Supabase.instance.client.storage.from('memories').getPublicUrl(storageKey);
              if (publicUrl.isNotEmpty) {
                persistentMediaUrl = publicUrl;
              }
            }
          } catch (_) {
            // Fallback to local persistent path on network or bucket failure
          }
        } catch (_) {
          // Fallback to widget.documentFile!.path if app directory cannot be accessed
        }
      } else if (widget.imageFile != null) {
        persistentMediaUrl = widget.imageFile!.path;
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final extension = widget.imageFile!.path.split('.').last;
          final fileName = 'memory_${DateTime.now().millisecondsSinceEpoch}.$extension';
          final persistentFile = widget.imageFile!.copySync('${appDir.path}/$fileName');
          persistentMediaUrl = persistentFile.path;

          // Optional background upload to Supabase storage if reachable
          try {
            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
            if (currentUserId != null) {
              final bytes = persistentFile.readAsBytesSync();
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
        } catch (_) {
          // Fallback to widget.imageFile!.path if app directory cannot be accessed
        }
      }

      if (!mounted) return;

      // Preserve user-entered title if present, otherwise use initial/generated title
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : (widget.initialTitle.trim().isNotEmpty
              ? widget.initialTitle.trim()
              : (widget.linkUrl != null
                  ? 'Web Link (${DateFormat('MMM d').format(DateTime.now())})'
                  : (widget.documentFile != null
                      ? widget.documentFile!.path.split('/').last.split('\\').last
                      : 'Captured Memory (${DateFormat('MMM d').format(DateTime.now())})')));

      // For links, preserve the raw URL on line 1, followed by readable content if available.
      // For documents, preserve the exact document text (never overwrite with summary).
      // For visual memories, preserve user-edited content or AI summary.
      final content = widget.linkUrl != null && widget.linkUrl!.isNotEmpty
          ? ((widget.readableContent != null && widget.readableContent!.trim().isNotEmpty)
              ? '${widget.linkUrl!.trim()}\n\n${widget.readableContent!.trim()}'
              : widget.linkUrl!)
          : (widget.documentFile != null
              ? _contentController.text.trim()
              : (_currentSummary.trim().isNotEmpty
                  ? _currentSummary.trim()
                  : (_contentController.text.trim().isNotEmpty && _contentController.text.trim() != _rawOcrText.trim()
                      ? _contentController.text.trim()
                      : 'Captured Visual Memory')));

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

  Widget _buildDocumentCard(File file) {
    final fileName = file.path.split('/').last.split('\\').last;
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'DOC';
    final isPdf = ext == 'PDF';

    String fileSizeStr = '';
    try {
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes >= 1024 * 1024) {
          fileSizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else {
          fileSizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
        }
      }
    } catch (_) {}

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.chipInactiveBorder,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPdf
                  ? const Color(0xFFFEE2E2)
                  : AppColors.lightCyanTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPdf
                  ? Icons.picture_as_pdf_rounded
                  : Icons.description_rounded,
              color: isPdf ? const Color(0xFFDC2626) : AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isPdf
                            ? const Color(0xFFFEE2E2)
                            : AppColors.lightCyanTint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ext,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: isPdf
                              ? const Color(0xFFDC2626)
                              : AppColors.primary,
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
    );
  }

  Widget _buildHeaderPreview() {
    if (widget.documentFile != null) {
      return _buildDocumentCard(widget.documentFile!);
    }

    if (widget.imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
          ),
          child: Image.file(
            widget.imageFile!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (widget.previewImageUrl != null && widget.previewImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
          ),
          child: Image.network(
            widget.previewImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildStyledLinkCard(),
          ),
        ),
      );
    }

    return _buildStyledLinkCard();
  }

  Widget _buildStyledLinkCard() {
    final domain = widget.linkUrl != null
        ? (Uri.tryParse(widget.linkUrl!)?.host.isNotEmpty == true
            ? Uri.tryParse(widget.linkUrl!)!.host
            : widget.linkUrl!)
        : 'Web Link';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightCyanTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.link_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.linkUrl != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.linkUrl!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
              // 1. Captured Photo or Link Preview
              _buildHeaderPreview(),

              const SizedBox(height: 16),

              // 2. AI Status Banner & Timestamp (Fully responsive without horizontal overflow)
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
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
                                  if (_isOffline && !isAiProcessed) ...[
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF59E0B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ] else ...[
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
                                  ],
                                  Flexible(
                                    child: Text(
                                      isAiProcessed
                                          ? 'AI Organized'
                                          : (isAiFailed
                                              ? 'AI Analysis Failed'
                                              : (_isOffline
                                                  ? "You're offline"
                                                  : 'AI Ingestion Pending')),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isAiProcessed
                                            ? AppColors.primary
                                            : (isAiFailed
                                                ? AppColors.errorText
                                                : AppColors.textSecondary),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isAiProcessed && !_isOffline) ...[
                              if (_isReanalyzing)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Analyzing...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (isAiFailed)
                                InkWell(
                                  onTap: _retryAiAnalysis,
                                  borderRadius: BorderRadius.circular(100),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorText.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: AppColors.errorText.withValues(alpha: 0.3),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.refresh_rounded,
                                          size: 13,
                                          color: AppColors.errorText,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Retry AI',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.errorText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: _retryAiAnalysis,
                                  borderRadius: BorderRadius.circular(100),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(alpha: 0.3),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 13,
                                          color: AppColors.primary,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Analyze with AI',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
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
                  );
                },
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

              // 5. Extracted Content (Compact Card / Row, hidden by default)
              if (_rawOcrText.trim().isNotEmpty) ...[
                const Text(
                  'Extracted Content',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'See what was extracted from your memory',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
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
                      child: _isExtractedExpanded
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(14),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _isExtractedExpanded = false;
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
                                            Icons.document_scanner_rounded,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Text(
                                            'Hide extracted text',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.keyboard_arrow_up_rounded,
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
                                  child: SelectableText(
                                    _rawOcrText.trim(),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: AppColors.textPrimary,
                                      height: 1.5,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() {
                                  _isExtractedExpanded = true;
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
                                        Icons.document_scanner_rounded,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'View extracted text',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.iconSecondary,
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
