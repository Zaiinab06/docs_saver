import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';

enum CaptureMode {
  takePhoto,
  scanDocument,
  addLink,
  addNote,
  recordVoice,
  chooseFile,
}

class _CategoryChoice {
  final String name;
  final IconData icon;

  const _CategoryChoice({
    required this.name,
    required this.icon,
  });
}

class CaptureScreen extends StatefulWidget {
  final CaptureMode? initialMode;

  const CaptureScreen({super.key, this.initialMode});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  String _selectedCategory = AppStrings.categoryPersonal;
  final List<String> _tags = [];

  File? _capturedImage;
  String? _persistedImagePath;
  bool _isProcessingOcr = false;
  bool _isSaving = false;
  String? _ocrPreviewBadge;

  static const List<_CategoryChoice> _categories = [
    _CategoryChoice(
      name: AppStrings.categoryWork,
      icon: Icons.work_outline_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryPersonal,
      icon: Icons.favorite_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryStudy,
      icon: Icons.school_rounded,
    ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleInitialMode();
    });
  }

  void _handleInitialMode() {
    switch (widget.initialMode) {
      case CaptureMode.takePhoto:
        _pickImage(ImageSource.camera, isDocumentScan: false);
        break;
      case CaptureMode.scanDocument:
        _pickImage(ImageSource.camera, isDocumentScan: true);
        break;
      case CaptureMode.chooseFile:
        _pickImage(ImageSource.gallery, isDocumentScan: false);
        break;
      case CaptureMode.addLink:
        if (!_tags.contains('link')) {
          setState(() {
            _tags.add('link');
            _selectedCategory = AppStrings.categoryStudy;
          });
        }
        break;
      case CaptureMode.addNote:
        if (!_tags.contains('note')) {
          setState(() => _tags.add('note'));
        }
        break;
      case CaptureMode.recordVoice:
        if (!_tags.contains('voice')) {
          setState(() => _tags.add('voice'));
        }
        break;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, {required bool isDocumentScan}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'memory_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final savedFile = await File(picked.path).copy('${appDir.path}/$fileName');

      setState(() {
        _capturedImage = savedFile;
        _persistedImagePath = savedFile.path;
        _isProcessingOcr = true;
        _ocrPreviewBadge = isDocumentScan ? 'Document Scanner' : 'Camera Photo';
      });

      if (isDocumentScan && !_tags.contains('document')) {
        _tags.add('document');
      }
      if (!_tags.contains('photo')) {
        _tags.add('photo');
      }

      // Execute ML Kit text recognition
      await _runOcrExtraction(savedFile, isDocumentScan);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image capture error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingOcr = false);
      }
    }
  }

  Future<void> _runOcrExtraction(File imageFile, bool isDocumentScan) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final text = recognizedText.text.trim();
      if (text.isNotEmpty) {
        if (_contentController.text.trim().isEmpty) {
          _contentController.text = text;
        }

        if (_titleController.text.trim().isEmpty) {
          _titleController.text = _extractSmartTitle(text);
        }

        final detected = _detectCategory(text);
        _selectedCategory = detected;

        if (!_tags.contains('ocr')) {
          _tags.add('ocr');
        }

        final smartTag = _detectTag(text);
        if (smartTag != null && !_tags.contains(smartTag)) {
          _tags.add(smartTag);
        }
      } else {
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = isDocumentScan
              ? 'Scanned Document (${DateFormat('MMM d').format(DateTime.now())})'
              : 'Captured Photo (${DateFormat('MMM d').format(DateTime.now())})';
        }
      }
    } catch (_) {
      // Fallback if MLKit text recognition is unavailable on device
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = isDocumentScan ? 'Scanned Document' : 'Photo Memory';
      }
    }
  }

  String _extractSmartTitle(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isNotEmpty) {
      final firstLine = lines.first.replaceAll(RegExp(r'[#*_~`|]'), '').trim();
      if (firstLine.length > 38) {
        return '${firstLine.substring(0, 35)}...';
      }
      return firstLine;
    }
    return 'Captured Memory';
  }

  String _detectCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('invoice') ||
        lower.contains('receipt') ||
        lower.contains('total') ||
        lower.contains('paid') ||
        lower.contains('\$') ||
        lower.contains('tax') ||
        lower.contains('bank') ||
        lower.contains('expense')) {
      return AppStrings.categoryFinance;
    }
    if (lower.contains('meeting') ||
        lower.contains('project') ||
        lower.contains('client') ||
        lower.contains('work') ||
        lower.contains('task') ||
        lower.contains('roadmap') ||
        lower.contains('presentation')) {
      return AppStrings.categoryWork;
    }
    if (lower.contains('exam') ||
        lower.contains('study') ||
        lower.contains('chapter') ||
        lower.contains('course') ||
        lower.contains('lecture') ||
        lower.contains('learn') ||
        lower.contains('book')) {
      return AppStrings.categoryStudy;
    }
    if (lower.contains('flight') ||
        lower.contains('hotel') ||
        lower.contains('travel') ||
        lower.contains('trip') ||
        lower.contains('ticket') ||
        lower.contains('passport') ||
        lower.contains('airport')) {
      return AppStrings.categoryTravel;
    }
    if (lower.contains('recipe') ||
        lower.contains('restaurant') ||
        lower.contains('food') ||
        lower.contains('dinner') ||
        lower.contains('lunch') ||
        lower.contains('coffee') ||
        lower.contains('menu')) {
      return AppStrings.categoryFood;
    }
    if (lower.contains('gym') ||
        lower.contains('workout') ||
        lower.contains('fitness') ||
        lower.contains('health') ||
        lower.contains('doctor') ||
        lower.contains('medicine') ||
        lower.contains('cardio')) {
      return AppStrings.categoryHealth;
    }
    if (lower.contains('clothes') ||
        lower.contains('dress') ||
        lower.contains('shoes') ||
        lower.contains('fashion') ||
        lower.contains('outfit')) {
      return AppStrings.categoryFashion;
    }
    return AppStrings.categoryPersonal;
  }

  String? _detectTag(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('receipt') || lower.contains('invoice')) return 'receipt';
    if (lower.contains('meeting')) return 'meeting';
    if (lower.contains('code') || lower.contains('dev')) return 'coding';
    if (lower.contains('workout') || lower.contains('fitness')) return 'fitness';
    return null;
  }

  void _addCustomTag() {
    final tag = _tagInputController.text.trim().replaceAll('#', '').toLowerCase();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagInputController.clear();
      });
    }
  }

  Future<void> _saveMemory() async {
    final titleInput = _titleController.text.trim();
    final contentInput = _contentController.text.trim();

    if (contentInput.isEmpty && _persistedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture an image or enter your memory content.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final title = titleInput.isNotEmpty
        ? titleInput
        : (contentInput.isNotEmpty
            ? _extractSmartTitle(contentInput)
            : 'Photo Memory (${DateFormat('MMM d').format(DateTime.now())})');

    final content = contentInput.isNotEmpty
        ? contentInput
        : (_persistedImagePath != null ? 'Captured visual memory' : '');

    // Optional cloud backup to Supabase Storage if authenticated
    String? mediaUrl = _persistedImagePath;
    if (_persistedImagePath != null) {
      try {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          final file = File(_persistedImagePath!);
          final bytes = await file.readAsBytes();
          final ext = file.path.split('.').last;
          final storageKey = '$currentUserId/${DateTime.now().millisecondsSinceEpoch}.$ext';

          await Supabase.instance.client.storage.from('memories').uploadBinary(
                storageKey,
                bytes,
                fileOptions: FileOptions(contentType: 'image/$ext'),
              );
          final publicUrl = Supabase.instance.client.storage.from('memories').getPublicUrl(storageKey);
          if (publicUrl.isNotEmpty) {
            mediaUrl = publicUrl;
          }
        }
      } catch (_) {
        // Fallback to local persistent path if offline or bucket unconfigured
        mediaUrl = _persistedImagePath;
      }
    }

    if (!mounted) return;

    // Persist through the existing repository and BLoC data layer
    context.read<CaptureBloc>().add(
          AddMemoryEvent(
            title: title,
            content: content,
            category: _selectedCategory,
            tags: List<String>.from(_tags),
            mediaUrl: mediaUrl,
          ),
        );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Memory saved to your Second Brain!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    // Return to Home dynamically
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
          'Capture Memory',
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Image Capture / Attachment Section
              if (_capturedImage != null)
                _buildCapturedImagePreview()
              else
                _buildCaptureSourceButtons(),

              const SizedBox(height: 20),

              // 2. Title Field
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
                    hintText: 'e.g. Work Meeting Notes',
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

              // 4. Content / Notes Field
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Content & Notes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_isProcessingOcr)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Extracting text...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
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
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Write down your thought, link, or review extracted text...',
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

              // 5. Tags Section
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
            ],
          ),
        ),
      ),

      // 6. Bottom Pinned "Save Memory" Button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(top: BorderSide(color: AppColors.chipInactiveBorder, width: 1.0)),
        ),
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
    );
  }

  // Captured Image Banner
  Widget _buildCapturedImagePreview() {
    return Container(
      width: double.infinity,
      height: 190,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.chipInactiveBorder, width: 1.2),
        image: DecorationImage(
          image: FileImage(_capturedImage!),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
          if (_ocrPreviewBadge != null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.document_scanner_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _ocrPreviewBadge!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.black.withValues(alpha: 0.65),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.cameraswitch_rounded, size: 18, color: Colors.white),
                    onPressed: () => _pickImage(ImageSource.camera, isDocumentScan: false),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.black.withValues(alpha: 0.65),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _capturedImage = null;
                        _persistedImagePath = null;
                        _ocrPreviewBadge = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Buttons to capture image or scan document if not attached
  Widget _buildCaptureSourceButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera, isDocumentScan: false),
            icon: const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.primary),
            label: const Text('Photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.chipInactiveBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera, isDocumentScan: true),
            icon: const Icon(Icons.document_scanner_outlined, size: 18, color: AppColors.primary),
            label: const Text('Scan Doc'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.chipInactiveBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(ImageSource.gallery, isDocumentScan: false),
            icon: const Icon(Icons.photo_library_outlined, size: 18, color: AppColors.primary),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.chipInactiveBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // Category Selector Chips
  Widget _buildCategorySelector() {
    return SizedBox(
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
                gradient: isSelected ? AppColors.primaryGradient : null,
                color: isSelected ? null : AppColors.categoryChipBackground,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.categoryChipBorder,
                  width: isSelected ? 1.6 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
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
                    color: isSelected ? AppColors.textWhite : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.textWhite : AppColors.primary,
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

  // Tags Section with dynamic adding and removal
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.lightCyanTint,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                  border: Border.all(color: AppColors.chipInactiveBorder, width: 1.0),
                ),
                child: TextField(
                  controller: _tagInputController,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Add custom tag...',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addCustomTag,
              icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 28),
            ),
          ],
        ),
      ],
    );
  }
}
