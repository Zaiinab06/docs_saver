import 'package:isar_community/isar.dart';
import '../../../../core/services/isar_service.dart';
import '../models/memory_model.dart';

abstract class CaptureLocalDataSource {
  Future<void> cacheMemory(MemoryModel memory);
  Future<List<MemoryModel>> getCachedMemories({String? userId});
  Future<List<MemoryModel>> getUnsyncedMemories({String? userId});
  Future<void> markAsSynced(String serverId);
  Future<void> updateMemoryFromRemote(MemoryModel memory);
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
  Future<List<MemoryModel>> getCachedMemories({String? userId}) async {
    List<MemoryModel> models;
    if (userId != null && userId.isNotEmpty) {
      models = await isar.memoryModels
          .filter()
          .userIdEqualTo(userId)
          .sortByClientCreatedAtDesc()
          .findAll();
    } else {
      models = await isar.memoryModels
          .where()
          .sortByClientCreatedAtDesc()
          .findAll();
    }
    models.sort((a, b) {
      final aPinned = a.tags.any((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin') ||
          a.category.toLowerCase() == 'pinned';
      final bPinned = b.tags.any((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin') ||
          b.category.toLowerCase() == 'pinned';
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      final dateComp = b.clientCreatedAt.compareTo(a.clientCreatedAt);
      if (dateComp != 0) return dateComp;
      return b.serverId.compareTo(a.serverId);
    });
    return models;
  }

  @override
  Future<List<MemoryModel>> getUnsyncedMemories({String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      return await isar.memoryModels
          .filter()
          .userIdEqualTo(userId)
          .and()
          .isSyncedEqualTo(false)
          .findAll();
    }
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

  @override
  Future<void> updateMemoryFromRemote(MemoryModel updatedMemory) async {
    final existing = await isar.memoryModels
        .filter()
        .serverIdEqualTo(updatedMemory.serverId)
        .findFirst();

    if (existing != null) {
      existing.title = updatedMemory.title;
      existing.category = updatedMemory.category;
      existing.tags = updatedMemory.tags;
      existing.aiStatus = updatedMemory.aiStatus;
      if (updatedMemory.embedding != null) {
        existing.embedding = updatedMemory.embedding;
      }
      existing.serverUpdatedAt = updatedMemory.serverUpdatedAt;
      existing.isSynced = true;

      await isar.writeTxn(() async {
        await isar.memoryModels.put(existing);
      });
    } else {
      await isar.writeTxn(() async {
        await isar.memoryModels.put(updatedMemory);
      });
    }
  }
}
