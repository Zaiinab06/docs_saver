import '../../../../core/constants/app_strings.dart';
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
  }) async {
    // If there is no text and no image provided, do NOT fabricate data
    if (ocrText.trim().isEmpty && (imageBase64 == null || imageBase64.isEmpty)) {
      return AiIngestionResult.empty(
        rawOcrText: ocrText,
        aiStatus: 'pending',
      );
    }

    try {
      final data = await remoteDataSource.invokeIngestion(
        content: ocrText,
        imageBase64: imageBase64,
        mimeType: mimeType,
      );

      final rawTitle = (data['title'] ?? '').toString().trim();
      final rawCategory = (data['category'] ?? '').toString().trim();
      final rawSummary = (data['summary'] ?? '').toString().trim();

      // Normalize Category to the 8 official AppStrings categories
      final normalizedCategory = _normalizeCategory(rawCategory);

      // Extract and sanitize tags
      List<String> tags = [];
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

      // Extract Living Memory entities
      List<LivingEntityItem> entities = [];
      if (data['entities'] is List) {
        for (final item in data['entities'] as List) {
          if (item is Map) {
            entities.add(LivingEntityItem.fromMap(Map<String, dynamic>.from(item)));
          }
        }
      }

      final aiStatus = (data['ai_status'] ?? 'processed').toString();

      return AiIngestionResult(
        title: rawTitle,
        category: normalizedCategory,
        tags: tags,
        summary: rawSummary,
        entities: entities,
        aiStatus: aiStatus.isEmpty ? 'processed' : aiStatus,
        rawOcrText: ocrText,
      );
    } catch (_) {
      // ZERO FABRICATED DATA: Return empty/pending if remote AI call fails
      return AiIngestionResult.empty(
        rawOcrText: ocrText,
        aiStatus: 'pending',
      );
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
}
