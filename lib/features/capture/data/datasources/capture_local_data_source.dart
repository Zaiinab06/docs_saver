import 'package:isar_community/isar.dart';
import '../../../../core/services/isar_service.dart';
import '../models/memory_model.dart';

abstract class CaptureLocalDataSource {
  Future<void> cacheMemory(MemoryModel memory);
  Future<List<MemoryModel>> getCachedMemories();
  Future<List<MemoryModel>> getUnsyncedMemories();
  Future<void> markAsSynced(String serverId);
}

class CaptureLocalDataSourceImpl implements CaptureLocalDataSource {
  final Isar isar = IsarService.instance;

  @override
  Future<void> cacheMemory(MemoryModel memory) async {
    await isar.writeTxn(() async {
      await isar.memoryModels.put(memory);
    });
  }

  @override
  Future<List<MemoryModel>> getCachedMemories() async {
    return await isar.memoryModels
        .where()
        .sortByClientCreatedAtDesc()
        .findAll();
  }

  @override
  Future<List<MemoryModel>> getUnsyncedMemories() async {
    return await isar.memoryModels.filter().isSyncedEqualTo(false).findAll();
  }

  @override
  Future<void> markAsSynced(String serverId) async {
    final memory = await isar.memoryModels
        .filter()
        .serverIdEqualTo(serverId)
        .findFirst();

    if (memory != null) {
      memory.isSynced = true;
      await isar.writeTxn(() async {
        await isar.memoryModels.put(memory);
      });
    }
  }
}
