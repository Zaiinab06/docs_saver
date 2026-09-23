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
    final cachedModels = await localDataSource.getCachedMemories(
      userId: effectiveUserId,
    );
    final entities = cachedModels.map((m) => m.toEntity()).toList();
    entities.sort(MemoryEntity.compareByPinnedAndDate);
    return entities;
  }

  @override
  Future<void> deleteMemory(String memoryId) async {
    String? effectiveUserId = _getCurrentUserId();
    if (effectiveUserId == null || effectiveUserId == 'local_user') {
      try {
        final cached = await localDataSource.getCachedMemories();
        for (final m in cached) {
          if (m.serverId == memoryId &&
              m.userId.isNotEmpty &&
              m.userId != 'local_user') {
            effectiveUserId = m.userId;
            break;
          }
        }
      } catch (_) {}
    }
    effectiveUserId ??= 'local_user';

    // 1. Delete from local cache instantly for zero-latency UI
    await localDataSource.deleteMemory(memoryId);

    // 2. If authenticated user, record tombstone for offline sync tracking
    if (effectiveUserId != 'local_user') {
      await localDataSource.recordTombstone(memoryId, effectiveUserId);
    }

    // 3. Attempt immediate remote deletion on Supabase
    try {
      await remoteDataSource.deleteMemory(memoryId);
      // Success: clear tombstone from local database
      await localDataSource.clearTombstone(memoryId);
    } catch (_) {
      // Offline / network failure: tombstone remains in Isar and will be synced upon reconnection
    }
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {
    final effectiveUserId = userId ?? _getCurrentUserId();

    // 1. Process pending offline deletion tombstones first
    try {
      final tombstones = await localDataSource.getPendingTombstones(
        userId: effectiveUserId,
      );
      for (final tombstone in tombstones) {
        try {
          await remoteDataSource.deleteMemory(tombstone.serverId);
          await localDataSource.clearTombstone(tombstone.serverId);
        } catch (_) {
          // Network dropped or Supabase error: halt deletions and retry next cycle
          break;
        }
      }
    } catch (_) {}

    // 2. Push unsynced memories to remote Supabase
    final pendingModels = await localDataSource.getUnsyncedMemories(
      userId: effectiveUserId,
    );
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
              final fileName =
                  'media_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final storageKey = '$effectiveUserId/$fileName';
              final mime = resolveMimeType(ext);
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
        break; // Connectivity drop: retry in next cycle
      }
    }

    // 3. Pull down remote updates for authenticated user
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      try {
        final pendingTombstones = await localDataSource.getPendingTombstones(
          userId: effectiveUserId,
        );
        final tombstoneIds = pendingTombstones.map((t) => t.serverId).toSet();

        final remoteMaps = await remoteDataSource.fetchRemoteMemories(
          userId: effectiveUserId,
        );
        final remoteIds = <String>{};
        for (final map in remoteMaps) {
          final serverId = (map['id'] ?? '').toString();
          remoteIds.add(serverId);

          // Never resurrect an item queued for deletion
          if (tombstoneIds.contains(serverId)) {
            continue;
          }

          final model = MemoryModel.fromMap(map, isSynced: true);
          await localDataSource.updateMemoryFromRemote(model);
        }

        // Clean up any local memories that were deleted remotely
        final cached = await localDataSource.getCachedMemories(
          userId: effectiveUserId,
        );
        for (final mem in cached) {
          if (mem.isSynced && !remoteIds.contains(mem.serverId)) {
            await localDataSource.deleteMemory(mem.serverId);
          }
        }
      } catch (_) {
        // Offline or network error
      }
    }
  }

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) {
    return remoteDataSource.subscribeToMemoryUpdates(userId).asyncMap((
      model,
    ) async {
      await localDataSource.updateMemoryFromRemote(model);
      return model.toEntity();
    });
  }

  static String resolveMimeType(String ext) {
    final clean = ext.toLowerCase().replaceAll('.', '').trim();
    switch (clean) {
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'md':
      case 'csv':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'm4a':
        return 'audio/m4a';
      case 'mp3':
        return 'audio/mp3';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }
}
