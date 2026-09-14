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

    testWidgets('HomeScreen: Pinned memory appears at the top and newly added memory appears below pinned',
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

      // Verify both are present
      expect(find.text('First Memory (Will Pin)'), findsOneWidget);
      expect(find.text('Second Memory (Unpinned)'), findsOneWidget);

      // Verify that First Memory (pinned) is visually ABOVE Second Memory
      final pinnedTop = tester.getTopLeft(find.text('First Memory (Will Pin)')).dy;
      final unpinnedTop = tester.getTopLeft(find.text('Second Memory (Unpinned)')).dy;
      expect(pinnedTop, lessThan(unpinnedTop));

      // Now simulate adding a brand new memory created afterward
      captureBloc.add(
        const AddMemoryEvent(
          title: 'Brand New Memory',
          content: 'Newly captured content',
          category: 'General',
        ),
      );
      await tester.pumpAndSettle();

      // Brand New Memory must appear BELOW pinned memory
      expect(find.text('Brand New Memory'), findsOneWidget);
      final brandNewTop = tester.getTopLeft(find.text('Brand New Memory')).dy;
      final pinnedTopAfter = tester.getTopLeft(find.text('First Memory (Will Pin)')).dy;
      expect(pinnedTopAfter, lessThan(brandNewTop));
    });

    testWidgets('HomeScreen: Pinning and unpinning updates position immediately',
        (tester) async {
      final memA = createMemory(
        id: 'a',
        title: 'Alpha Note (Old)',
        createdAt: baseTime,
      );
      final memB = createMemory(
        id: 'b',
        title: 'Beta Note (New)',
        createdAt: baseTime.add(const Duration(hours: 1)),
      );

      final repo = FakeCaptureRepository([memA, memB]);
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

      // Initially Beta (newer) is above Alpha (older)
      final initialBetaTop = tester.getTopLeft(find.text('Beta Note (New)')).dy;
      final initialAlphaTop = tester.getTopLeft(find.text('Alpha Note (Old)')).dy;
      expect(initialBetaTop, lessThan(initialAlphaTop));

      // Pin Alpha Note (Old) via popup menu
      // Find the 3-dot menu for Alpha Note
      final menuButtons = find.byIcon(Icons.more_vert);
      expect(menuButtons, findsNWidgets(2));

      // Tap the second menu button (Alpha Note is currently second)
      await tester.tap(menuButtons.at(1));
      await tester.pumpAndSettle();

      // Tap "Pin memory"
      await tester.tap(find.text(AppStrings.menuPin));
      await tester.pumpAndSettle();

      // Now Alpha Note (pinned) must be ABOVE Beta Note (New)!
      final pinnedAlphaTop = tester.getTopLeft(find.text('Alpha Note (Old)')).dy;
      final unpinnedBetaTop = tester.getTopLeft(find.text('Beta Note (New)')).dy;
      expect(pinnedAlphaTop, lessThan(unpinnedBetaTop));

      // Unpin Alpha Note via popup menu
      final menuButtonsAfterPin = find.byIcon(Icons.more_vert);
      // Tap the first menu button (Alpha Note is currently first)
      await tester.tap(menuButtonsAfterPin.at(0));
      await tester.pumpAndSettle();

      // Tap "Unpin memory"
      await tester.tap(find.text(AppStrings.menuUnpin));
      await tester.pumpAndSettle();

      // Alpha Note immediately returns to its correct position below Beta Note (New)
      final unpinnedAlphaTop = tester.getTopLeft(find.text('Alpha Note (Old)')).dy;
      final betaTopRestored = tester.getTopLeft(find.text('Beta Note (New)')).dy;
      expect(betaTopRestored, lessThan(unpinnedAlphaTop));
    });

    testWidgets('HomeScreen: Multiple pinned memories remain ordered by timestamp above unpinned',
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

      // Order should be:
      // 1. Pinned Later (11:00)
      // 2. Pinned First (10:00)
      // 3. Unpinned Latest (12:00)
      final p2Top = tester.getTopLeft(find.text('Pinned Later (11:00)')).dy;
      final p1Top = tester.getTopLeft(find.text('Pinned First (10:00)')).dy;
      final u1Top = tester.getTopLeft(find.text('Unpinned Latest (12:00)')).dy;

      expect(p2Top, lessThan(p1Top));
      expect(p1Top, lessThan(u1Top));
    });
  });
}
