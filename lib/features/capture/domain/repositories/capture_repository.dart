import '../entities/memory_entity.dart';

abstract class CaptureRepository {
  Future<void> saveMemory(MemoryEntity memory);
  Future<List<MemoryEntity>> getMemories({String? userId});
  Future<void> syncPendingMemories({String? userId});
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId);
}
