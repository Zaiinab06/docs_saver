import '../entities/memory_entity.dart';
import '../repositories/capture_repository.dart';

class SubscribeToMemoriesUseCase {
  final CaptureRepository repository;

  SubscribeToMemoriesUseCase(this.repository);

  Stream<MemoryEntity> call(String userId) {
    return repository.subscribeToMemoryUpdates(userId);
  }
}
