import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  String? _getCurrentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

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
  Future<List<MemoryEntity>> getMemories({String? userId}) async {
    final effectiveUserId = userId ?? _getCurrentUserId();
    final cachedModels =
        await localDataSource.getCachedMemories(userId: effectiveUserId);
    final entities = cachedModels.map((m) => m.toEntity()).toList();
    entities.sort(MemoryEntity.compareByPinnedAndDate);
    return entities;
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {
    final effectiveUserId = userId ?? _getCurrentUserId();
    final pendingModels =
        await localDataSource.getUnsyncedMemories(userId: effectiveUserId);
    for (final model in pendingModels) {
      try {
        var entity = model.toEntity();
        if (entity.mediaUrl != null &&
            !entity.mediaUrl!.startsWith('http://') &&
            !entity.mediaUrl!.startsWith('https://') &&
            effectiveUserId != null &&
            effectiveUserId != 'local_user') {
          try {
            final file = File(entity.mediaUrl!);
            if (file.existsSync()) {
              final bytes = await file.readAsBytes();
              final ext = entity.mediaUrl!.split('.').last;
              final fileName = 'media_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final storageKey = '$effectiveUserId/$fileName';
              final mime = ext == 'm4a' ? 'audio/m4a' : 'image/$ext';
              await Supabase.instance.client.storage
                  .from('memories')
                  .uploadBinary(
                    storageKey,
                    bytes,
                    fileOptions: FileOptions(contentType: mime),
                  );
              final publicUrl = Supabase.instance.client.storage
                  .from('memories')
                  .getPublicUrl(storageKey);
              if (publicUrl.isNotEmpty) {
                model.mediaUrl = publicUrl;
                entity = model.toEntity();
              }
            }
          } catch (_) {}
        }
        await remoteDataSource.upsertMemory(entity);
        await localDataSource.markAsSynced(model.serverId);
      } catch (_) {
        break; // Connectivity drop hui to next cycle me retry hoga
      }
    }

    // Pull down remote updates for authenticated user
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      try {
        final remoteMaps = await remoteDataSource.fetchRemoteMemories(
          userId: effectiveUserId,
        );
        for (final map in remoteMaps) {
          final model = MemoryModel.fromMap(map, isSynced: true);
          await localDataSource.updateMemoryFromRemote(model);
        }
      } catch (_) {
        // Offline or network error
      }
    }
  }

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) {
    return remoteDataSource
        .subscribeToMemoryUpdates(userId)
        .asyncMap((model) async {
      await localDataSource.updateMemoryFromRemote(model);
      return model.toEntity();
    });
  }
}
