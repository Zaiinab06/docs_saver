import '../entities/memory_entity.dart';
import '../repositories/capture_repository.dart';

class GetMemoriesUseCase {
  final CaptureRepository repository;

  GetMemoriesUseCase(this.repository);

  Future<List<MemoryEntity>> call([String? userId]) async {
    return await repository.getMemories(userId: userId);
  }
}
