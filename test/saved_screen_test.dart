import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';

class _FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  _FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => memories;

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    final idx = memories.indexWhere((m) => m.id == memory.id);
    if (idx != -1) {
      memories[idx] = memory;
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
  final now = DateTime(2026, 9, 19, 14, 0);

  MemoryEntity createMemory({
    required String id,
    required String title,
    List<String> tags = const [],
  }) {
    return MemoryEntity(
      id: id,
      userId: 'test-user',
      title: title,
      content: 'Sample content for $title',
      category: 'General',
      tags: tags,
      aiStatus: 'processed',
      clientCreatedAt: now,
      clientUpdatedAt: now,
      serverUpdatedAt: now,
    );
  }

  Widget createTestWidget(CaptureBloc bloc) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CaptureBloc>.value(value: bloc),
      ],
      child: const MaterialApp(
        home: SavedScreen(),
      ),
    );
  }

  group('SavedScreen Segmented Control & Filtering Tests', () {
    testWidgets('All shows all saved memories (pinned and unpinned)',
        (tester) async {
      final pinned = createMemory(
        id: '1',
        title: 'Important Pinned Note',
        tags: ['pinned'],
      );
      final unpinned = createMemory(
        id: '2',
        title: 'Regular Grocery List',
      );

      final repo = _FakeCaptureRepository([pinned, unpinned]);
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      )..add(LoadMemoriesEvent());

      await tester.pumpWidget(createTestWidget(bloc));
      await tester.pumpAndSettle();

      // Segmented control is visible
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);

      // Default is 'All' tab: both memories are displayed
      expect(find.text('Important Pinned Note'), findsOneWidget);
      expect(find.text('Regular Grocery List'), findsOneWidget);
    });

    testWidgets('Pinned shows only pinned memories', (tester) async {
      final pinned = createMemory(
        id: '1',
        title: 'Important Pinned Note',
        tags: ['pinned'],
      );
      final unpinned = createMemory(
        id: '2',
        title: 'Regular Grocery List',
      );

      final repo = _FakeCaptureRepository([pinned, unpinned]);
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      )..add(LoadMemoriesEvent());

      await tester.pumpWidget(createTestWidget(bloc));
      await tester.pumpAndSettle();

      // Switch to Pinned tab
      await tester.tap(find.text('Pinned'));
      await tester.pumpAndSettle();

      // Only pinned memory appears
      expect(find.text('Important Pinned Note'), findsOneWidget);
      expect(find.text('Regular Grocery List'), findsNothing);
    });

    testWidgets('Switching between All and Pinned works correctly and updates immediately',
        (tester) async {
      final pinned = createMemory(
        id: '1',
        title: 'Pinned Item',
        tags: ['pinned'],
      );
      final unpinned = createMemory(
        id: '2',
        title: 'Unpinned Item',
      );

      final repo = _FakeCaptureRepository([pinned, unpinned]);
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      )..add(LoadMemoriesEvent());

      await tester.pumpWidget(createTestWidget(bloc));
      await tester.pumpAndSettle();

      // On 'All': both exist
      expect(find.text('Pinned Item'), findsOneWidget);
      expect(find.text('Unpinned Item'), findsOneWidget);

      // Switch to 'Pinned'
      await tester.tap(find.text('Pinned'));
      await tester.pumpAndSettle();
      expect(find.text('Pinned Item'), findsOneWidget);
      expect(find.text('Unpinned Item'), findsNothing);

      // Switch back to 'All'
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Pinned Item'), findsOneWidget);
      expect(find.text('Unpinned Item'), findsOneWidget);
    });

    testWidgets('Empty state works for All section when no memories exist',
        (tester) async {
      final repo = _FakeCaptureRepository([]);
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      )..add(LoadMemoriesEvent());

      await tester.pumpWidget(createTestWidget(bloc));
      await tester.pumpAndSettle();

      // In 'All' tab with 0 memories
      expect(find.text('No saved memories yet'), findsOneWidget);
      expect(find.text('Pinned memories will appear here. Pin important notes, links, or ideas from your Home screen to access them quickly.'), findsOneWidget);
    });

    testWidgets('Empty state works for Pinned section when memories exist in All but none are pinned',
        (tester) async {
      final unpinned = createMemory(
        id: '1',
        title: 'Only Unpinned Note',
      );

      final repo = _FakeCaptureRepository([unpinned]);
      final bloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      )..add(LoadMemoriesEvent());

      await tester.pumpWidget(createTestWidget(bloc));
      await tester.pumpAndSettle();

      // 'All' tab has the unpinned item
      expect(find.text('Only Unpinned Note'), findsOneWidget);

      // Switch to 'Pinned' tab
      await tester.tap(find.text('Pinned'));
      await tester.pumpAndSettle();

      // Pinned empty state is shown dynamically
      expect(find.text('Only Unpinned Note'), findsNothing);
      expect(find.text('No pinned memories yet'), findsOneWidget);
    });
  });
}
