import '../entities/ai_ingestion_result.dart';

abstract class AiRepository {
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
  });
}
