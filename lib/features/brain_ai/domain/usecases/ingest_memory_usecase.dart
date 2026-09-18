import '../entities/ai_ingestion_result.dart';
import '../repositories/ai_repository.dart';

class IngestMemoryUseCase {
  final AiRepository repository;

  IngestMemoryUseCase(this.repository);

  Future<AiIngestionResult> call({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
  }) {
    return repository.processPhotoIngestion(
      ocrText: ocrText,
      imageBase64: imageBase64,
      mimeType: mimeType,
      documentBase64: documentBase64,
    );
  }
}
