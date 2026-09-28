import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import '../../../../core/network/network_checker.dart';
import '../../../../core/services/ocr_text_normalizer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/image_utils.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'memory_review_screen.dart';

class PhotoReviewScreen extends StatefulWidget {
  final File imageFile;
  final IngestMemoryUseCase? ingestMemoryUseCase;
  final bool? isOffline;
  final bool isDocumentScan;

  const PhotoReviewScreen({
    super.key,
    required this.imageFile,
    this.ingestMemoryUseCase,
    this.isOffline,
    this.isDocumentScan = false,
  });

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  late File _currentImage;
  final ImagePicker _picker = ImagePicker();
  late final IngestMemoryUseCase _ingestMemoryUseCase;

  bool _isProcessing = false;
  bool _isRotating = false;
  String _processingStatus = 'Understanding your memory...';

  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageFile;
    _ingestMemoryUseCase = widget.ingestMemoryUseCase ??
        IngestMemoryUseCase(
          AiRepositoryImpl(
            remoteDataSource: AiRemoteDataSourceImpl(),
          ),
        );
  }

  Future<void> _retakePhoto() async {
    if (widget.isDocumentScan) {
      try {
        final pictures = await CunningDocumentScanner.getPictures(
          noOfPages: 1,
          scannerSource: ScannerSource.camera,
          androidScannerMode: AndroidScannerMode.full,
        );

        if (pictures != null && pictures.isNotEmpty) {
          setState(() {
            _currentImage = File(pictures.first);
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Document scanner failed. Please verify camera permissions in Settings.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    try {
      final newPhoto = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (newPhoto != null) {
        final localFile = await ImageUtils.processAndPersistImageXFile(
          newPhoto,
          maxDimension: 1280,
          quality: 80,
        );
        setState(() {
          _currentImage = localFile;
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

  Future<void> _rotateImage() async {
    if (_isRotating || _isProcessing) return;

    setState(() {
      _isRotating = true;
    });

    try {
      final bytes = _currentImage.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        // Rotate 90 degrees clockwise
        final rotated = img.copyRotate(decoded, angle: 90);
        final isPng = _currentImage.path.toLowerCase().endsWith('.png');
        final encoded = isPng ? img.encodePng(rotated) : img.encodeJpg(rotated, quality: 92);

        final dir = _currentImage.parent.path;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = isPng ? 'png' : 'jpg';
        final rotatedFile = File('$dir/rot_${timestamp}_${_currentImage.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '')}.$ext');
        rotatedFile.writeAsBytesSync(encoded, flush: true);

        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        if (mounted) {
          setState(() {
            _currentImage = rotatedFile;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rotate image: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRotating = false;
        });
      }
    }
  }

  Future<void> _usePhoto() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = widget.isDocumentScan
          ? 'Understanding your document...'
          : 'Understanding your memory...';
    });

    String extractedOcrText = '';
    AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');

    try {
      // 1. OCR Extraction using Google ML Kit (isolated so platform errors do not block Gemini Vision)
      debugPrint('[PhotoReview OCR] Starting text extraction on ${_currentImage.path}...');
      try {
        final inputImage = InputImage.fromFile(_currentImage);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();

        extractedOcrText = OcrTextNormalizer.normalizeRecognizedText(recognizedText);
        debugPrint('[PhotoReview OCR] ML Kit extraction successful. Length: ${extractedOcrText.length}');
        if (extractedOcrText.isNotEmpty) {
          final sample = extractedOcrText.length > 80
              ? '${extractedOcrText.substring(0, 80).replaceAll('\n', ' ')}...'
              : extractedOcrText.replaceAll('\n', ' ');
          debugPrint('[PhotoReview OCR] Sample text: "$sample"');
        }
      } catch (ocrErr, ocrStack) {
        debugPrint(
          '[PhotoReview OCR Warning] ML Kit recognition failed or unsupported on this platform: $ocrErr\n$ocrStack. Proceeding to Gemini Vision...',
        );
      }

      // Check network connectivity before attempting remote Gemini AI call
      final isOnline = widget.isOffline != null
          ? !widget.isOffline!
          : await NetworkChecker.isConnected();
      debugPrint('[PhotoReview AI] Network check: isOnline=$isOnline');

      if (isOnline) {
        if (mounted) {
          setState(() {
            _processingStatus = 'Organizing...';
          });
        }

        // 2. Prepare multimodal image representation with optimized compression
        String? imageBase64;
        String? mimeType;
        try {
          final prep = await ImageUtils.prepareImageForAi(
            _currentImage,
            maxDimension: 1280,
            quality: 80,
          );
          if (prep != null) {
            imageBase64 = prep.base64;
            mimeType = prep.mimeType;
            debugPrint(
              '[PhotoReview AI] Prepared optimized image payload: ${prep.byteLength} bytes, mime: $mimeType',
            );
          }
        } catch (readErr) {
          debugPrint('[PhotoReview AI Warning] Could not prepare image file: $readErr');
        }

        if (mounted) {
          setState(() {
            _processingStatus = 'Almost there...';
          });
        }

        // 3. Process with IngestMemoryUseCase (Supabase Edge Function + Gemini Vision)
        // Only call AI if we have OCR text or valid image representation
        if (extractedOcrText.isNotEmpty || (imageBase64 != null && imageBase64.isNotEmpty)) {
          debugPrint(
            '[PhotoReview AI] Invoking IngestMemoryUseCase (ocrLen=${extractedOcrText.length}, hasImageBase64=${imageBase64 != null})...',
          );
          try {
            aiResult = await _ingestMemoryUseCase(
              ocrText: extractedOcrText,
              imageBase64: imageBase64,
              mimeType: mimeType,
            );
            debugPrint(
              '[PhotoReview AI] AI processing succeeded: title="${aiResult.title}", category="${aiResult.category}", tags=${aiResult.tags}, status="${aiResult.aiStatus}", docTextLen=${aiResult.documentText?.length ?? 0}',
            );
          } catch (aiErr, aiStack) {
            debugPrint('❌ AI ANALYSIS ERROR: $aiErr');
            debugPrint('❌ STACK TRACE: $aiStack');
            debugPrint('[PhotoReview AI Error] IngestMemoryUseCase invocation failed: $aiErr\n$aiStack');
            aiResult = AiIngestionResult.empty(
              rawOcrText: extractedOcrText,
              aiStatus: 'failed',
            );
          }
        } else {
          debugPrint('[PhotoReview AI Warning] Neither OCR text nor image base64 available for AI processing.');
          aiResult = AiIngestionResult.empty(
            rawOcrText: extractedOcrText,
            aiStatus: 'pending',
          );
        }
      } else {
        // Device is offline: do NOT attempt Gemini / Edge Function call
        debugPrint('[PhotoReview AI] Device offline. Skipping Gemini Vision call.');
        aiResult = AiIngestionResult.empty(
          rawOcrText: extractedOcrText,
          aiStatus: 'pending',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ AI ANALYSIS ERROR: $e');
      debugPrint('❌ STACK TRACE: $stackTrace');
      debugPrint('[PhotoReview Error] Unexpected error in _usePhoto: $e\n$stackTrace');
      // Zero fake data on error: preserve real image and OCR text
      aiResult = AiIngestionResult.empty(
        rawOcrText: extractedOcrText,
        aiStatus: 'failed',
      );
    } finally {
      final isOffline = widget.isOffline ?? !(await NetworkChecker.isConnected());
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        final initialTags = List<String>.from(aiResult.tags);
        if (widget.isDocumentScan && !initialTags.contains('document')) {
          initialTags.add('document');
        }

        final initialContent = aiResult.summary.isNotEmpty
            ? aiResult.summary
            : (aiResult.documentText != null && aiResult.documentText!.isNotEmpty
                ? aiResult.documentText!
                : extractedOcrText);

        final initialTitle = aiResult.title.isNotEmpty
            ? aiResult.title
            : (widget.isDocumentScan
                ? 'Scanned Document (${DateFormat('MMM d').format(DateTime.now())})'
                : 'Captured Memory (${DateFormat('MMM d').format(DateTime.now())})');

        debugPrint(
          '[PhotoReview] Navigating to MemoryReviewScreen: title="$initialTitle", category="${aiResult.category}", tags=$initialTags, contentLen=${initialContent.length}, ocrLen=${extractedOcrText.length}, status="${aiResult.aiStatus}"',
        );

        // Navigate to Memory Review / Edit Screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemoryReviewScreen(
              imageFile: _currentImage,
              initialTitle: initialTitle,
              initialContent: initialContent,
              rawOcrText: extractedOcrText.isNotEmpty
                  ? extractedOcrText
                  : (aiResult.documentText ?? ''),
              initialCategory: aiResult.category,
              initialTags: initialTags,
              initialSummary: aiResult.summary,
              entities: aiResult.entities,
              aiStatus: aiResult.aiStatus,
              createdAt: DateTime.now(),
              isOffline: isOffline,
              ingestMemoryUseCase: widget.ingestMemoryUseCase ?? _ingestMemoryUseCase,
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
        title: Text(
          widget.isDocumentScan ? 'Review Document' : 'Review Photo',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Rotate',
            icon: const Icon(Icons.rotate_right_rounded, color: Colors.white, size: 26),
            onPressed: (_isProcessing || _isRotating) ? null : _rotateImage,
          ),
          const SizedBox(width: 4),
        ],
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
                key: ValueKey(_currentImage.path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                      Text(
                        widget.isDocumentScan
                            ? 'AI is scanning and organizing document'
                            : 'AI is scanning and organizing',
                        style: const TextStyle(
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

          // 3. Bottom Action Bar (Retake vs Rotate vs Use Photo)
          if (!_isProcessing)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
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
                child: SafeArea(
                  top: false,
                  maintainBottomViewPadding: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Row(
                      children: [
                        // Retake Button
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            onPressed: (_isProcessing || _isRotating) ? null : _retakePhoto,
                            icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                            label: const Text(
                              'Retake',
                              style: TextStyle(
                                fontSize: 14,
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

                        const SizedBox(width: 8),

                        // Rotate Button
                        OutlinedButton.icon(
                          onPressed: (_isProcessing || _isRotating) ? null : _rotateImage,
                          icon: _isRotating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.rotate_right_rounded, size: 18, color: Colors.white),
                          label: const Text(
                            'Rotate',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            side: const BorderSide(color: Colors.white54, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Use Photo / Use Document Button
                        Expanded(
                          flex: 4,
                          child: ElevatedButton.icon(
                            onPressed: (_isProcessing || _isRotating) ? null : _usePhoto,
                            icon: const Icon(Icons.check_rounded, size: 18, color: AppColors.textWhite),
                            label: Text(
                              widget.isDocumentScan ? 'Use Document' : 'Use Photo',
                              style: const TextStyle(
                                fontSize: 14,
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
              ),
            ),
        ],
      ),
    );
  }
}
