import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'memory_review_screen.dart';

class PhotoReviewScreen extends StatefulWidget {
  final File imageFile;

  const PhotoReviewScreen({
    super.key,
    required this.imageFile,
  });

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  late File _currentImage;
  final ImagePicker _picker = ImagePicker();
  late final IngestMemoryUseCase _ingestMemoryUseCase;

  bool _isProcessing = false;
  String _processingStatus = 'Understanding your memory...';

  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageFile;
    _ingestMemoryUseCase = IngestMemoryUseCase(
      AiRepositoryImpl(
        remoteDataSource: AiRemoteDataSourceImpl(),
      ),
    );
  }

  Future<void> _retakePhoto() async {
    try {
      final newPhoto = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1800,
      );

      if (newPhoto != null) {
        setState(() {
          _currentImage = File(newPhoto.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera access failed. Please verify camera permissions in Settings.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _usePhoto() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = 'Understanding your memory...';
    });

    String extractedOcrText = '';
    AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');

    try {
      // 1. OCR Extraction using Google ML Kit
      final inputImage = InputImage.fromFile(_currentImage);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      extractedOcrText = recognizedText.text.trim();

      if (mounted) {
        setState(() {
          _processingStatus = 'Organizing...';
        });
      }

      // 2. Prepare multimodal image representation if size is within reasonable bounds
      String? imageBase64;
      String? mimeType;
      try {
        final fileSize = await _currentImage.length();
        // Send base64 if image is under 8MB
        if (fileSize < 8 * 1024 * 1024) {
          final imageBytes = await _currentImage.readAsBytes();
          imageBase64 = base64Encode(imageBytes);
          final extension = _currentImage.path.split('.').last.toLowerCase();
          mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
        }
      } catch (_) {
        // Fallback to text-only if image reading fails
      }

      if (mounted) {
        setState(() {
          _processingStatus = 'Almost there...';
        });
      }

      // 3. Process with IngestMemoryUseCase (Supabase Edge Function + Gemini)
      // Only call AI if we have OCR text or valid image representation
      if (extractedOcrText.isNotEmpty || (imageBase64 != null && imageBase64.isNotEmpty)) {
        aiResult = await _ingestMemoryUseCase(
          ocrText: extractedOcrText,
          imageBase64: imageBase64,
          mimeType: mimeType,
        );
      } else {
        aiResult = AiIngestionResult.empty(
          rawOcrText: extractedOcrText,
          aiStatus: 'pending',
        );
      }
    } catch (_) {
      // Zero fake data on error: preserve real image and OCR text
      aiResult = AiIngestionResult.empty(
        rawOcrText: extractedOcrText,
        aiStatus: 'pending',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Navigate to Memory Review / Edit Screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemoryReviewScreen(
              imageFile: _currentImage,
              initialTitle: aiResult.title,
              initialContent: extractedOcrText,
              initialCategory: aiResult.category,
              initialTags: aiResult.tags,
              initialSummary: aiResult.summary,
              entities: aiResult.entities,
              aiStatus: aiResult.aiStatus,
              createdAt: DateTime.now(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Review Photo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 1. Photo Preview
          Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.0,
              child: Image.file(
                _currentImage,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // 2. Processing Overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.0,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _processingStatus,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'AI is scanning and organizing',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Bottom Action Bar (Retake vs Use Photo)
          if (!_isProcessing)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Retake Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retakePhoto,
                        icon: const Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
                        label: const Text(
                          'Retake',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.white54, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Use Photo Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _usePhoto,
                        icon: const Icon(Icons.check_rounded, size: 20, color: AppColors.textWhite),
                        label: const Text(
                          'Use Photo',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textWhite,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
