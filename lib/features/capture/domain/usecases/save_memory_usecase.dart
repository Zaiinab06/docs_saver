import '../entities/memory_entity.dart';
import '../repositories/capture_repository.dart';

class SaveMemoryUseCase {
  final CaptureRepository repository;

  SaveMemoryUseCase(this.repository);

  Future<void> call(MemoryEntity memory) async {
    return await repository.saveMemory(memory);
  }
}
