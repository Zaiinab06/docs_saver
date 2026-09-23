import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/data/datasources/capture_local_data_source.dart';
import 'package:second_brain/features/capture/data/datasources/capture_remote_data_source.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository_impl.dart';

class MockLocalDataSource implements CaptureLocalDataSource {
  final List<MemoryModel> store = [];

  @override
  Future<void> cacheMemory(MemoryModel memory) async {
    store.removeWhere((m) => m.serverId == memory.serverId);
    store.add(memory);
  }

  @override
  Future<List<MemoryModel>> getCachedMemories({String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      return store.where((m) => m.userId == userId).toList()
        ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));
    }
    return List.from(store)
      ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));
  }

  @override
  Future<List<MemoryModel>> getUnsyncedMemories({String? userId}) async {
    return store.where((m) {
      final matchesUser =
          (userId == null || userId.isEmpty || m.userId == userId);
      return matchesUser && !m.isSynced;
    }).toList();
  }

  @override
  Future<void> markAsSynced(String serverId) async {
    final idx = store.indexWhere((m) => m.serverId == serverId);
    if (idx != -1) {
      store[idx].isSynced = true;
    }
  }

  @override
  Future<void> updateMemoryFromRemote(MemoryModel memory) async {
    final idx = store.indexWhere((m) => m.serverId == memory.serverId);
    if (idx != -1) {
      store[idx] = memory;
    } else {
      store.add(memory);
    }
  }
}

class MockRemoteDataSource implements CaptureRemoteDataSource {
  final List<Map<String, dynamic>> remoteStore = [];
  final List<String> fetchedUserIds = [];

  @override
  Future<void> upsertMemory(MemoryEntity memory) async {
    remoteStore.removeWhere((m) => m['id'] == memory.id);
    remoteStore.add({
      'id': memory.id,
      'user_id': memory.userId,
      'title': memory.title,
      'content': memory.content,
      'category': memory.category,
      'tags': memory.tags,
      'client_created_at': memory.clientCreatedAt.toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRemoteMemories({
    String? userId,
  }) async {
    if (userId != null) fetchedUserIds.add(userId);
    if (userId != null && userId.isNotEmpty) {
      return remoteStore.where((m) => m['user_id'] == userId).toList();
    }
    return List.from(remoteStore);
  }

  @override
  Stream<MemoryModel> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  group('User Data Isolation Tests', () {
    late MockLocalDataSource localDataSource;
    late MockRemoteDataSource remoteDataSource;
    late CaptureRepositoryImpl repository;

    final now = DateTime.now();

    setUp(() {
      localDataSource = MockLocalDataSource();
      remoteDataSource = MockRemoteDataSource();
      repository = CaptureRepositoryImpl(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );

      // Populate local DB with memories belonging to different users
      localDataSource.store.addAll([
        MemoryModel()
          ..serverId = 'noor-mem-1'
          ..userId = 'user_noor'
          ..title = 'Noor Study Notes'
          ..content = 'Biochemistry chapter 3'
          ..category = 'Study'
          ..tags = ['bio']
          ..clientCreatedAt = now.subtract(const Duration(hours: 2))
          ..clientUpdatedAt = now
          ..serverUpdatedAt = now
          ..isSynced = true,
        MemoryModel()
          ..serverId = 'noor-mem-2'
          ..userId = 'user_noor'
          ..title = 'Noor Travel Idea'
          ..content = 'Trip to Kyoto'
          ..category = 'Travel'
          ..tags = ['japan']
          ..clientCreatedAt = now.subtract(const Duration(hours: 1))
          ..clientUpdatedAt = now
          ..serverUpdatedAt = now
          ..isSynced = true,
        MemoryModel()
          ..serverId = 'zainab-mem-1'
          ..userId = 'user_zainab'
          ..title = 'Zainab Work Project'
          ..content = 'Mobile app architecture'
          ..category = 'Work'
          ..tags = ['architecture']
          ..clientCreatedAt = now.subtract(const Duration(minutes: 30))
          ..clientUpdatedAt = now
          ..serverUpdatedAt = now
          ..isSynced = true,
      ]);
    });

    test('User Noor only receives Noor memories', () async {
      final noorMemories = await repository.getMemories(userId: 'user_noor');

      expect(noorMemories.length, 2);
      expect(noorMemories.every((m) => m.userId == 'user_noor'), isTrue);
      expect(noorMemories.any((m) => m.id == 'zainab-mem-1'), isFalse);
      expect(
        noorMemories.map((m) => m.title),
        containsAll(['Noor Study Notes', 'Noor Travel Idea']),
      );
    });

    test('User Zainab only receives Zainab memories', () async {
      final zainabMemories = await repository.getMemories(
        userId: 'user_zainab',
      );

      expect(zainabMemories.length, 1);
      expect(zainabMemories.first.userId, 'user_zainab');
      expect(zainabMemories.first.title, 'Zainab Work Project');
      expect(zainabMemories.any((m) => m.userId == 'user_noor'), isFalse);
    });

    test('New user with no memories receives empty list', () async {
      final newMemories = await repository.getMemories(
        userId: 'user_brand_new',
      );

      expect(newMemories, isEmpty);
    });

    test('syncPendingMemories isolates remote fetch by user ID', () async {
      await repository.syncPendingMemories(userId: 'user_noor');

      expect(remoteDataSource.fetchedUserIds, contains('user_noor'));
      expect(remoteDataSource.fetchedUserIds, isNot(contains('user_zainab')));
    });
  });
}
