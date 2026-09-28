import 'package:flutter/foundation.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/gemini_direct_service.dart';
import '../../domain/entities/ai_ingestion_result.dart';
import '../../domain/repositories/ai_repository.dart';
import '../datasources/ai_remote_data_source.dart';

class AiRepositoryImpl implements AiRepository {
  final AiRemoteDataSource remoteDataSource;

  AiRepositoryImpl({required this.remoteDataSource});

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
  }) async {
    // If there is no text, no image, no document, and no video provided, do NOT fabricate data
    if (ocrText.trim().isEmpty &&
        (imageBase64 == null || imageBase64.isEmpty) &&
        (documentBase64 == null || documentBase64.isEmpty) &&
        (videoBase64 == null || videoBase64.isEmpty)) {
      debugPrint('[AiRepository] Ingestion skipped: No OCR text, image, document, or video provided.');
      return AiIngestionResult.empty(rawOcrText: ocrText, aiStatus: 'pending');
    }

    Map<String, dynamic> data = {};
    try {
      debugPrint(
        '[AiRepository] Invoking remoteDataSource.invokeIngestion (ocrText len=${ocrText.length}, hasImage=${imageBase64 != null}, hasDoc=${documentBase64 != null}, hasVideo=${videoBase64 != null})...',
      );
      data = await remoteDataSource.invokeIngestion(
        content: ocrText,
        imageBase64: imageBase64,
        mimeType: mimeType,
        documentBase64: documentBase64,
        videoBase64: videoBase64,
      );
      debugPrint('[AiRepository] Remote ingestion succeeded. Keys: ${data.keys.toList()}');
    } catch (edgeError, edgeStack) {
      debugPrint('❌ SUPABASE EDGE FUNCTION ERROR: $edgeError');
      debugPrint('❌ EDGE STACK TRACE: $edgeStack');

      // Requirement 2: Fallback to Direct Gemini SDK / Service when Edge Function Fails
      debugPrint('🔄 Attempting Client-Side Gemini Fallback (gemini-1.5-flash)...');
      try {
        data = await GeminiDirectService.analyzeDirect(
          ocrText: ocrText,
          imageBase64: imageBase64,
          mimeType: mimeType,
        );
        debugPrint('[AiRepository] Client-side Gemini fallback succeeded! Keys: ${data.keys.toList()}');
      } catch (geminiError, geminiStack) {
        debugPrint('❌ CLIENT-SIDE GEMINI ERROR: $geminiError');
        debugPrint('❌ GEMINI STACK TRACE: $geminiStack');
      }
    }

    if (data.isEmpty) {
      debugPrint('❌ [AiRepository] Remote Edge and local Gemini both failed. Returning honest failure.');
      return AiIngestionResult.empty(rawOcrText: ocrText, aiStatus: 'failed');
    }

    try {

      // Wrap field parsing in safe fallbacks so missing/empty fields don't mark analysis as failed
      String rawTitle = '';
      String rawCategory = '';
      String rawSummary = '';
      String sanitizedSummary = '';
      String rawDocumentText = '';
      List<String> tags = [];
      List<LivingEntityItem> entities = [];

      try {
        rawTitle = (data['title'] ?? '').toString().trim();
      } catch (_) {}

      try {
        rawCategory = (data['category'] ?? '').toString().trim();
      } catch (_) {}

      try {
        rawSummary = (data['summary'] ?? '').toString().trim();
        sanitizedSummary = _sanitizeSemanticSummary(rawSummary);
      } catch (_) {}

      try {
        rawDocumentText = (data['document_text'] ?? '').toString().trim();
      } catch (_) {}

      // Normalize Category to the 8 official AppStrings categories
      final normalizedCategory = _normalizeCategory(rawCategory);

      // Extract and sanitize tags
      const bannedTags = {
        'photo',
        'image',
        'empty',
        'untitled',
        'general',
        'memory',
        'note',
        'picture',
      };
      try {
        if (data['tags'] is List) {
          final extractedTags = (data['tags'] as List)
              .map((t) => t.toString().trim().toLowerCase().replaceAll('#', ''))
              .where((t) => t.length > 1 && !bannedTags.contains(t))
              .toList();
          for (final tag in extractedTags) {
            if (!tags.contains(tag)) {
              tags.add(tag);
            }
          }
        }
      } catch (_) {}

      if (((videoBase64 != null && videoBase64.isNotEmpty) ||
              ocrText.toLowerCase().contains('video')) &&
          !tags.contains('video')) {
        tags.add('video');
      }

      // Extract Living Memory entities
      try {
        if (data['entities'] is List) {
          for (final item in data['entities'] as List) {
            if (item is Map) {
              entities.add(
                LivingEntityItem.fromMap(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } catch (_) {}

      // Fallback title if AI returned an empty string
      String resolvedTitle = rawTitle;
      if (resolvedTitle.isEmpty) {
        if (rawDocumentText.isNotEmpty) {
          resolvedTitle = 'Document Note';
        } else if (videoBase64 != null && videoBase64.isNotEmpty) {
          resolvedTitle = 'Video Memory';
        } else if (imageBase64 != null && imageBase64.isNotEmpty) {
          resolvedTitle = 'Visual Memory';
        } else if (ocrText.isNotEmpty) {
          resolvedTitle = 'Captured Note';
        } else {
          resolvedTitle = 'Captured Memory';
        }
      }

      // Fallback summary if AI returned empty string
      String resolvedSummary = sanitizedSummary;
      if (resolvedSummary.isEmpty && ocrText.isNotEmpty) {
        resolvedSummary = ocrText;
      }

      String aiStatus = (data['ai_status'] ?? 'processed').toString();
      if (aiStatus.isEmpty || aiStatus == 'pending') {
        if (resolvedTitle.isNotEmpty || tags.isNotEmpty || resolvedSummary.isNotEmpty) {
          aiStatus = 'processed';
        }
      }

      return AiIngestionResult(
        title: resolvedTitle,
        category: normalizedCategory,
        tags: tags,
        summary: resolvedSummary,
        entities: entities,
        aiStatus: aiStatus.isEmpty ? 'processed' : aiStatus,
        rawOcrText: ocrText,
        documentText: rawDocumentText.isNotEmpty ? rawDocumentText : null,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ AI ANALYSIS ERROR: $e');
      debugPrint('❌ STACK TRACE: $stackTrace');
      return AiIngestionResult.empty(rawOcrText: ocrText, aiStatus: 'failed');
    }
  }

  String _normalizeCategory(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('work') ||
        lower.contains('job') ||
        lower.contains('office') ||
        lower.contains('business') ||
        lower.contains('meeting') ||
        lower.contains('task')) {
      return AppStrings.categoryWork;
    }
    if (lower.contains('study') ||
        lower.contains('learn') ||
        lower.contains('education') ||
        lower.contains('school') ||
        lower.contains('tech') ||
        lower.contains('code') ||
        lower.contains('research')) {
      return AppStrings.categoryStudy;
    }
    if (lower.contains('travel') ||
        lower.contains('trip') ||
        lower.contains('flight') ||
        lower.contains('hotel') ||
        lower.contains('vacation') ||
        lower.contains('destination')) {
      return AppStrings.categoryTravel;
    }
    if (lower.contains('fashion') ||
        lower.contains('cloth') ||
        lower.contains('beauty') ||
        lower.contains('style') ||
        lower.contains('wear') ||
        lower.contains('outfit')) {
      return AppStrings.categoryFashion;
    }
    if (lower.contains('food') ||
        lower.contains('cook') ||
        lower.contains('recipe') ||
        lower.contains('restaurant') ||
        lower.contains('eat') ||
        lower.contains('dining') ||
        lower.contains('drink')) {
      return AppStrings.categoryFood;
    }
    if (lower.contains('finance') ||
        lower.contains('money') ||
        lower.contains('tax') ||
        lower.contains('bill') ||
        lower.contains('budget') ||
        lower.contains('bank') ||
        lower.contains('receipt') ||
        lower.contains('expense')) {
      return AppStrings.categoryFinance;
    }
    if (lower.contains('health') ||
        lower.contains('fitness') ||
        lower.contains('workout') ||
        lower.contains('gym') ||
        lower.contains('diet') ||
        lower.contains('medical')) {
      return AppStrings.categoryHealth;
    }
    // Default to Personal
    return AppStrings.categoryPersonal;
  }

  String _sanitizeSemanticSummary(String raw) {
    if (raw.trim().isEmpty) return '';
    final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) {
      if (l.isEmpty) return false;
      // Filter out raw URLs
      if (l.startsWith('http://') ||
          l.startsWith('https://') ||
          l.startsWith('www.')) {
        return false;
      }
      // Filter out status bar patterns (e.g. 7:45 PM, 100%, 5G)
      if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(l) && l.length < 20) {
        return false;
      }
      if (RegExp(r'^\d{1,3}%\s*$').hasMatch(l)) {
        return false;
      }
      // Filter out common UI noise buttons / labels
      final clean = l
          .replaceAll(RegExp(r'^[•\-\*]\s*'), '')
          .trim()
          .toLowerCase();
      const noise = {
        'back',
        'next',
        'done',
        'cancel',
        'close',
        'search',
        'home',
        'share',
        'menu',
        'more',
        'less ai',
        'settings',
        'profile',
      };
      if (noise.contains(clean)) return false;
      return true;
    }).toList();

    if (lines.isEmpty) return '';
    final maxLines = lines.take(2).toList();
    final formatted = maxLines.map((line) {
      if (line.startsWith('•') ||
          line.startsWith('-') ||
          line.startsWith('*')) {
        return '• ${line.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim()}';
      }
      return '• ${line.trim()}';
    });

    return formatted.join('\n');
  }
}
