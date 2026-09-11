import 'package:second_brain/features/capture/data/datasources/capture_local_data_source.dart';
import 'package:second_brain/features/capture/data/datasources/capture_remote_data_source.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';

import '../../domain/entities/memory_entity.dart';
import '../../domain/repositories/capture_repository.dart';

class CaptureRepositoryImpl implements CaptureRepository {
  final CaptureLocalDataSource localDataSource;
  final CaptureRemoteDataSource remoteDataSource;

  CaptureRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
  });

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    // 1. Pehle local Isar DB me instantly save karein (Offline-first zero latency)
    final localModel = memory.toModel(isSynced: false);
    await localDataSource.cacheMemory(localModel);

    // 2. Background attempt to push to Supabase
    try {
      await remoteDataSource.upsertMemory(memory);
      await localDataSource.markAsSynced(memory.id);
    } catch (_) {
      // Offline ya network failure me local flag 'isSynced = false' hi rahega
      // Sync engine connectivity wapis aane par push karega
    }
  }

  @override
  Future<List<MemoryEntity>> getMemories() async {
    final cachedModels = await localDataSource.getCachedMemories();
    return cachedModels.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> syncPendingMemories() async {
    final pendingModels = await localDataSource.getUnsyncedMemories();
    for (final model in pendingModels) {
      try {
        final entity = model.toEntity();
        await remoteDataSource.upsertMemory(entity);
        await localDataSource.markAsSynced(model.serverId);
      } catch (_) {
        break; // Connectivity drop hui to next cycle me retry hoga
      }
    }
  }
}
