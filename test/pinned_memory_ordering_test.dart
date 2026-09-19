import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async {
    final list = List<MemoryEntity>.from(memories);
    list.sort(MemoryEntity.compareByPinnedAndDate);
    return list;
  }

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index != -1) {
      memories[index] = memory;
    } else {
      memories.add(memory);
    }
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  group('Pinned Memory Ordering Unit & Widget Tests', () {
    final baseTime = DateTime(2026, 9, 14, 10, 0);

    MemoryEntity createMemory({
      required String id,
      required String title,
      required DateTime createdAt,
      List<String> tags = const [],
    }) {
      return MemoryEntity(
        id: id,
        userId: 'user-test',
        title: title,
        content: 'Content for $title',
        tags: tags,
        clientCreatedAt: createdAt,
        clientUpdatedAt: createdAt,
        serverUpdatedAt: createdAt,
      );
    }

    test('Unit: compareByPinnedAndDate places pinned memories above unpinned memories', () {
      final unpinnedNew = createMemory(
        id: '1',
        title: 'Unpinned Newer',
        createdAt: baseTime.add(const Duration(hours: 2)),
      );
      final pinnedOld = createMemory(
        id: '2',
        title: 'Pinned Older',
        createdAt: baseTime,
        tags: ['pinned'],
      );

      final list = [unpinnedNew, pinnedOld]..sort(MemoryEntity.compareByPinnedAndDate);

      expect(list.first.id, '2');
      expect(list.first.title, 'Pinned Older');
      expect(list.last.id, '1');
      expect(list.last.title, 'Unpinned Newer');
    });

    test('Unit: compareByPinnedAndDate sorts multiple pinned memories by latest date', () {
      final pinnedOld = createMemory(
        id: 'p1',
        title: 'Pinned 10:00',
        createdAt: baseTime,
        tags: ['pinned'],
      );
      final pinnedNew = createMemory(
        id: 'p2',
        title: 'Pinned 11:00',
        createdAt: baseTime.add(const Duration(hours: 1)),
        tags: ['pinned'],
      );
      final unpinned = createMemory(
        id: 'u1',
        title: 'Unpinned 12:00',
        createdAt: baseTime.add(const Duration(hours: 2)),
      );

      final list = [pinnedOld, unpinned, pinnedNew]
        ..sort(MemoryEntity.compareByPinnedAndDate);

      // Pinned memories first, newest timestamp first
      expect(list[0].id, 'p2');
      expect(list[1].id, 'p1');
      // Followed by unpinned
      expect(list[2].id, 'u1');
    });

    testWidgets('HomeScreen does not display memory cards when memories exist (Recent Memories removed from Home UI)',
        (tester) async {
      final memoryOld = createMemory(
        id: 'mem-1',
        title: 'First Memory (Will Pin)',
        createdAt: baseTime,
        tags: ['pinned'], // Pinned
      );
      final memoryNewer = createMemory(
        id: 'mem-2',
        title: 'Second Memory (Unpinned)',
        createdAt: baseTime.add(const Duration(hours: 1)),
      );

      final repo = FakeCaptureRepository([memoryOld, memoryNewer]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: const MaterialApp(
            home: HomeScreen(userName: 'Tester'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Recent Memories header and memory cards are removed from HomeScreen UI
      expect(find.text('First Memory (Will Pin)'), findsNothing);
      expect(find.text('Second Memory (Unpinned)'), findsNothing);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);

      // Category Section cards are displayed
      expect(find.text('Documents & Records'), findsOneWidget);
      expect(find.text('Work & Learning'), findsOneWidget);
      expect(find.text('Home & Utilities'), findsOneWidget);
    });

    testWidgets('SavedScreen: Unpinning a memory removes it from SavedScreen',
        (tester) async {
      final memA = createMemory(
        id: 'a',
        title: 'Alpha Note (Pinned)',
        createdAt: baseTime,
        tags: ['pinned'],
      );

      final repo = FakeCaptureRepository([memA]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );
      captureBloc.add(LoadMemoriesEvent());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: const MaterialApp(
            home: SavedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha Note (Pinned)'), findsOneWidget);

      // Find unpin button
      final unpinBtn = find.byIcon(Icons.push_pin_rounded);
      expect(unpinBtn, findsOneWidget);

      // Tap unpin button
      await tester.tap(unpinBtn);
      await tester.pumpAndSettle();

      // Memory is unpinned, empty state is now displayed
      expect(find.text('Alpha Note (Pinned)'), findsNothing);
      expect(find.text('No saved memories yet'), findsOneWidget);
    });

    testWidgets('SavedScreen: Multiple pinned memories remain ordered by timestamp',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final p1 = createMemory(
        id: 'p1',
        title: 'Pinned First (10:00)',
        createdAt: baseTime,
        tags: ['pinned'],
      );
      final p2 = createMemory(
        id: 'p2',
        title: 'Pinned Later (11:00)',
        createdAt: baseTime.add(const Duration(hours: 1)),
        tags: ['pinned'],
      );
      final u1 = createMemory(
        id: 'u1',
        title: 'Unpinned Latest (12:00)',
        createdAt: baseTime.add(const Duration(hours: 2)),
      );

      final repo = FakeCaptureRepository([p1, p2, u1]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );
      captureBloc.add(LoadMemoriesEvent());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: const MaterialApp(
            home: SavedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pinned memories are displayed on SavedScreen
      expect(find.text('Pinned Later (11:00)'), findsOneWidget);
      expect(find.text('Pinned First (10:00)'), findsOneWidget);
      // Unpinned is not on SavedScreen
      expect(find.text('Unpinned Latest (12:00)'), findsNothing);

      // Order on SavedScreen:
      // 1. Pinned Later (11:00)
      // 2. Pinned First (10:00)
      final p2Top = tester.getTopLeft(find.text('Pinned Later (11:00)')).dy;
      final p1Top = tester.getTopLeft(find.text('Pinned First (10:00)')).dy;

      expect(p2Top, lessThan(p1Top));
    });
  });
}
