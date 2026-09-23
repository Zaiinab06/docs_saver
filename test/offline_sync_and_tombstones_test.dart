import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/network/network_checker.dart';
import 'package:second_brain/features/capture/data/datasources/capture_local_data_source.dart';
import 'package:second_brain/features/capture/data/datasources/capture_remote_data_source.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import 'package:second_brain/features/capture/data/models/tombstone_model.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository_impl.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';

class InMemoryLocalDataSource implements CaptureLocalDataSource {
  final Map<String, MemoryModel> memories = {};
  final Map<String, TombstoneModel> tombstones = {};

  @override
  Future<void> cacheMemory(MemoryModel memory) async {
    memories[memory.serverId] = memory;
  }

  @override
  Future<List<MemoryModel>> getCachedMemories({String? userId}) async {
    final list = memories.values.where((m) {
      if (userId != null && userId.isNotEmpty) return m.userId == userId;
      return true;
    }).toList();
    list.sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));
    return list;
  }

  @override
  Future<List<MemoryModel>> getUnsyncedMemories({String? userId}) async {
    return memories.values.where((m) {
      final matchesUser = userId == null || userId.isEmpty || m.userId == userId;
      return matchesUser && !m.isSynced;
    }).toList();
  }

  @override
  Future<void> markAsSynced(String serverId) async {
    if (memories.containsKey(serverId)) {
      memories[serverId]!.isSynced = true;
    }
  }

  @override
  Future<void> updateMemoryFromRemote(MemoryModel memory) async {
    memories[memory.serverId] = memory;
  }

  @override
  Future<void> deleteMemory(String serverId) async {
    memories.remove(serverId);
  }

  @override
  Future<void> recordTombstone(String serverId, String userId) async {
    tombstones[serverId] = TombstoneModel()
      ..serverId = serverId
      ..userId = userId
      ..deletedAt = DateTime.now();
  }

  @override
  Future<List<TombstoneModel>> getPendingTombstones({String? userId}) async {
    return tombstones.values.where((t) {
      if (userId != null && userId.isNotEmpty) return t.userId == userId;
      return true;
    }).toList();
  }

  @override
  Future<void> clearTombstone(String serverId) async {
    tombstones.remove(serverId);
  }
}

class InMemoryRemoteDataSource implements CaptureRemoteDataSource {
  final Map<String, Map<String, dynamic>> remoteStore = {};
  final List<String> deletedIds = [];
  bool isOnline = true;

  @override
  Future<void> upsertMemory(MemoryEntity memory) async {
    if (!isOnline) throw Exception('Network offline');
    remoteStore[memory.id] = {
      'id': memory.id,
      'user_id': memory.userId,
      'title': memory.title,
      'content': memory.content,
      'category': memory.category,
      'tags': memory.tags,
      'media_url': memory.mediaUrl,
      'ai_status': memory.aiStatus,
      'client_created_at': memory.clientCreatedAt.toIso8601String(),
      'client_updated_at': memory.clientUpdatedAt.toIso8601String(),
    };
  }

  @override
  Future<void> deleteMemory(String id) async {
    if (!isOnline) throw Exception('Network offline');
    remoteStore.remove(id);
    deletedIds.add(id);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRemoteMemories({String? userId}) async {
    if (!isOnline) throw Exception('Network offline');
    return remoteStore.values.where((m) {
      if (userId != null && userId.isNotEmpty) return m['user_id'] == userId;
      return true;
    }).toList();
  }

  @override
  Stream<MemoryModel> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

class RecordingCaptureRepository extends CaptureRepositoryImpl {
  int syncCallCount = 0;

  RecordingCaptureRepository({
    required super.localDataSource,
    required super.remoteDataSource,
  });

  @override
  Future<void> syncPendingMemories({String? userId}) async {
    syncCallCount++;
    await super.syncPendingMemories(userId: userId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Automated Offline Sync & Tombstone Tests', () {
    late InMemoryLocalDataSource localDs;
    late InMemoryRemoteDataSource remoteDs;
    late RecordingCaptureRepository repo;

    setUp(() {
      localDs = InMemoryLocalDataSource();
      remoteDs = InMemoryRemoteDataSource();
      repo = RecordingCaptureRepository(
        localDataSource: localDs,
        remoteDataSource: remoteDs,
      );
    });

    tearDown(() {
      NetworkChecker.testOverride = null;
    });

    test('Network transition listener debounces rapid online events', () async {
      final connectivityController = StreamController<bool>.broadcast();
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
        syncDebounceDuration: const Duration(milliseconds: 50),
        connectivityStream: connectivityController.stream,
      );

      // Simulate rapid toggles: offline, online, online, online within 20ms
      connectivityController.add(false);
      await Future.delayed(const Duration(milliseconds: 10));
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 10));
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 10));
      connectivityController.add(true);

      // Wait for debounce period (50ms) to complete
      await Future.delayed(const Duration(milliseconds: 150));

      // Should have triggered exactly 1 sync call despite 3 online events
      expect(repo.syncCallCount, 1);

      await bloc.close();
      await connectivityController.close();
    });

    test('Offline deletion records tombstone and keeps it until sync', () async {
      const memoryId = 'mem-offline-1';
      const userId = 'user-123';

      // Seed local and remote memory
      final model = MemoryModel()
        ..serverId = memoryId
        ..userId = userId
        ..title = 'Tax Receipts'
        ..content = 'Important tax document'
        ..clientCreatedAt = DateTime.now()
        ..clientUpdatedAt = DateTime.now()
        ..serverUpdatedAt = DateTime.now()
        ..isSynced = true;

      await localDs.cacheMemory(model);
      await remoteDs.upsertMemory(model.toEntity());

      expect(localDs.memories.containsKey(memoryId), isTrue);
      expect(remoteDs.remoteStore.containsKey(memoryId), isTrue);

      // Go offline
      remoteDs.isOnline = false;

      // Delete memory via repository
      await repo.deleteMemory(memoryId);

      // Local memory is removed immediately
      expect(localDs.memories.containsKey(memoryId), isFalse);

      // Remote still has it because we were offline
      expect(remoteDs.remoteStore.containsKey(memoryId), isTrue);

      // Tombstone is recorded in local data source
      final tombstones = await localDs.getPendingTombstones(userId: userId);
      expect(tombstones.length, 1);
      expect(tombstones.first.serverId, memoryId);

      // Reconnect online and sync
      remoteDs.isOnline = true;
      await repo.syncPendingMemories(userId: userId);

      // Remote deletion has occurred
      expect(remoteDs.remoteStore.containsKey(memoryId), isFalse);
      expect(remoteDs.deletedIds.contains(memoryId), isTrue);

      // Tombstone has been cleared
      final remainingTombstones = await localDs.getPendingTombstones(userId: userId);
      expect(remainingTombstones.isEmpty, isTrue);

      // Local cache still does NOT contain the deleted memory
      expect(localDs.memories.containsKey(memoryId), isFalse);
    });

    test('Pending tombstones prevent resurrection during remote pull', () async {
      const memoryId = 'mem-deleted-offline';
      const userId = 'user-456';

      // Seed a tombstone locally (as if deleted offline)
      await localDs.recordTombstone(memoryId, userId);

      // Remote store still has the memory row (e.g. Supabase hadn't processed it yet)
      remoteDs.remoteStore[memoryId] = {
        'id': memoryId,
        'user_id': userId,
        'title': 'Zombie Note',
        'content': 'Should not resurrect',
        'category': 'General',
        'tags': [],
        'client_created_at': DateTime.now().toIso8601String(),
        'client_updated_at': DateTime.now().toIso8601String(),
      };

      // Run sync while remoteDs is online:
      // Step 1 deletes from remoteDs, Step 3 pulls and ignores tombstone IDs
      await repo.syncPendingMemories(userId: userId);

      // Should NOT resurrect into local cache
      final cached = await localDs.getCachedMemories(userId: userId);
      expect(cached.any((m) => m.serverId == memoryId), isFalse);
    });

    test('Two-way sync cleans up local synced memories deleted on server', () async {
      const serverDeletedId = 'mem-server-deleted';
      const localUnsyncedId = 'mem-local-unsynced';
      const userId = 'user-789';

      // A synced memory that was deleted on server (not in remoteStore)
      final syncedModel = MemoryModel()
        ..serverId = serverDeletedId
        ..userId = userId
        ..title = 'Deleted on Web'
        ..content = 'No longer exists in cloud'
        ..clientCreatedAt = DateTime.now()
        ..clientUpdatedAt = DateTime.now()
        ..serverUpdatedAt = DateTime.now()
        ..isSynced = true;

      // An unsynced locally-created memory (not yet in remoteStore)
      final unsyncedModel = MemoryModel()
        ..serverId = localUnsyncedId
        ..userId = userId
        ..title = 'Draft Note'
        ..content = 'Created offline, never pushed'
        ..clientCreatedAt = DateTime.now()
        ..clientUpdatedAt = DateTime.now()
        ..serverUpdatedAt = DateTime.now()
        ..isSynced = false;

      await localDs.cacheMemory(syncedModel);
      await localDs.cacheMemory(unsyncedModel);

      // Run sync
      await repo.syncPendingMemories(userId: userId);

      // The server-deleted memory was removed locally
      expect(localDs.memories.containsKey(serverDeletedId), isFalse);

      // The unsynced local draft was pushed to remote and marked synced!
      expect(remoteDs.remoteStore.containsKey(localUnsyncedId), isTrue);
      expect(localDs.memories[localUnsyncedId]?.isSynced, isTrue);
    });

    test('CaptureBloc dispatches DeleteMemoryEvent cleanly', () async {
      const memoryId = 'mem-bloc-del-1';
      const userId = 'user-bloc';

      final model = MemoryModel()
        ..serverId = memoryId
        ..userId = userId
        ..title = 'Temp Note'
        ..content = 'Will be deleted via bloc'
        ..clientCreatedAt = DateTime.now()
        ..clientUpdatedAt = DateTime.now()
        ..serverUpdatedAt = DateTime.now()
        ..isSynced = true;

      await localDs.cacheMemory(model);
      await remoteDs.upsertMemory(model.toEntity());

      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      bloc.add(const DeleteMemoryEvent(memoryId));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(localDs.memories.containsKey(memoryId), isFalse);
      expect(remoteDs.remoteStore.containsKey(memoryId), isFalse);

      await bloc.close();
    });
  });
}
