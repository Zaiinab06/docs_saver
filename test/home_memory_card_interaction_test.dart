import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => memories;

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    memories.add(memory);
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  group('HomeScreen Memory Card Interaction Tests', () {
    late FakeCaptureRepository repository;
    late SaveMemoryUseCase saveUseCase;
    late GetMemoriesUseCase getUseCase;
    late MemoryEntity testMemory;

    setUp(() {
      testMemory = MemoryEntity(
        id: 'memory-uuid-999',
        userId: 'user-1',
        title: 'Deep Learning Notes',
        content: 'Transformers and attention mechanism equations.',
        category: 'Study',
        tags: const ['ai', 'math'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 12, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 12, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 12, 0),
      );

      repository = FakeCaptureRepository([testMemory]);
      saveUseCase = SaveMemoryUseCase(repository);
      getUseCase = GetMemoriesUseCase(repository);
    });

    Widget createTestApp() {
      return MultiBlocProvider(
        providers: [
          BlocProvider<CaptureBloc>(
            create: (_) => CaptureBloc(
              saveMemoryUseCase: saveUseCase,
              getMemoriesUseCase: getUseCase,
              repository: repository,
            ),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      );
    }

    testWidgets('tapping memory card navigates to MemoryDetailScreen with correct data',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Confirm card is visible in Recent Memories
      expect(find.text('Deep Learning Notes'), findsOneWidget);

      // Tap the card (on title or body)
      await tester.tap(find.text('Deep Learning Notes'));
      await tester.pumpAndSettle();

      // Verify that MemoryDetailScreen is now pushed and displayed
      expect(find.byType(MemoryDetailScreen), findsOneWidget);
      expect(find.text('Extracted Content'), findsOneWidget);
      expect(find.text('View extracted text'), findsOneWidget);

      // Expand to view extracted content
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();

      expect(find.text('Transformers and attention mechanism equations.'), findsOneWidget);
      expect(find.text('#ai'), findsOneWidget);
      expect(find.text('#math'), findsOneWidget);
    });

    testWidgets('tapping 3-dot menu opens popup without navigating to MemoryDetailScreen',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Find the 3-dots icon
      final moreIcon = find.byIcon(Icons.more_vert);
      expect(moreIcon, findsOneWidget);

      // Tap 3-dots
      await tester.tap(moreIcon);
      await tester.pumpAndSettle();

      // Verify popup menu items appear
      expect(find.text(AppStrings.menuPin), findsOneWidget);
      expect(find.text(AppStrings.menuShare), findsOneWidget);
      expect(find.text(AppStrings.menuDelete), findsOneWidget);

      // Verify MemoryDetailScreen is NOT opened
      expect(find.byType(MemoryDetailScreen), findsNothing);
    });
  });
}
