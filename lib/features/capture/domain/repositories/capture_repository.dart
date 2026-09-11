import '../entities/memory_entity.dart';

abstract class CaptureRepository {
  Future<void> saveMemory(MemoryEntity memory);
  Future<List<MemoryEntity>> getMemories();
  Future<void> syncPendingMemories();
}
