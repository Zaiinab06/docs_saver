import '../entities/memory_entity.dart';
import '../repositories/capture_repository.dart';

class GetMemoriesUseCase {
  final CaptureRepository repository;

  GetMemoriesUseCase(this.repository);

  Future<List<MemoryEntity>> call() async {
    return await repository.getMemories();
  }
}
