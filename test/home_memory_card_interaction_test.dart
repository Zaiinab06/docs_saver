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
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

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
  group('HomeScreen & SavedScreen Memory Card Verification Tests', () {
    late FakeCaptureRepository repository;
    late SaveMemoryUseCase saveUseCase;
    late GetMemoriesUseCase getUseCase;
    late MemoryEntity pinnedMemory;

    setUp(() {
      pinnedMemory = MemoryEntity(
        id: 'memory-uuid-999',
        userId: 'user-1',
        title: 'Deep Learning Notes',
        content: 'Transformers and attention mechanism equations.',
        category: 'Study',
        tags: const ['ai', 'math', 'pinned'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 12, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 12, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 12, 0),
      );

      repository = FakeCaptureRepository([pinnedMemory]);
      saveUseCase = SaveMemoryUseCase(repository);
      getUseCase = GetMemoriesUseCase(repository);
    });

    Widget createHomeScreenApp(CaptureBloc bloc) {
      return MultiBlocProvider(
        providers: [BlocProvider<CaptureBloc>.value(value: bloc)],
        child: const MaterialApp(home: HomeScreen()),
      );
    }

    Widget createSavedScreenApp(CaptureBloc bloc) {
      return MultiBlocProvider(
        providers: [BlocProvider<CaptureBloc>.value(value: bloc)],
        child: const MaterialApp(home: SavedScreen()),
      );
    }

    testWidgets(
      'HomeScreen does not display memory cards since Recent Memories was removed from Home UI',
      (tester) async {
        final bloc = CaptureBloc(
          saveMemoryUseCase: saveUseCase,
          getMemoriesUseCase: getUseCase,
          repository: repository,
        );

        await tester.pumpWidget(createHomeScreenApp(bloc));
        await tester.pumpAndSettle();

        // Recent Memories header and memory card title must NOT appear on Home Screen
        expect(find.text('Deep Learning Notes'), findsNothing);
        expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);

        // Premium Category Section cards are displayed instead
        expect(find.text('Documents & Records'), findsOneWidget);
        expect(find.text('Work & Learning'), findsOneWidget);
        expect(find.text('Home & Utilities'), findsOneWidget);
      },
    );

    testWidgets(
      'SavedScreen displays pinned memory card and navigates to MemoryDetailScreen on tap',
      (tester) async {
        final bloc = CaptureBloc(
          saveMemoryUseCase: saveUseCase,
          getMemoriesUseCase: getUseCase,
          repository: repository,
        );
        bloc.add(LoadMemoriesEvent());

        await tester.pumpWidget(createSavedScreenApp(bloc));
        await tester.pumpAndSettle();

        // Card is visible on SavedScreen
        expect(find.text('Deep Learning Notes'), findsOneWidget);

        // Tap card
        await tester.tap(find.text('Deep Learning Notes'));
        await tester.pumpAndSettle();

        // MemoryDetailScreen is pushed
        expect(find.byType(MemoryDetailScreen), findsOneWidget);
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(find.text('View extracted text'), findsOneWidget);

        // Expand extracted content
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(
          find.text('Transformers and attention mechanism equations.'),
          findsOneWidget,
        );
        expect(find.text('#ai'), findsOneWidget);
        expect(find.text('#math'), findsOneWidget);
      },
    );

    testWidgets(
      'SavedScreen displays push pin unpin button for pinned memories',
      (tester) async {
        final bloc = CaptureBloc(
          saveMemoryUseCase: saveUseCase,
          getMemoriesUseCase: getUseCase,
          repository: repository,
        );
        bloc.add(LoadMemoriesEvent());

        await tester.pumpWidget(createSavedScreenApp(bloc));
        await tester.pumpAndSettle();

        // Find the unpin button
        final unpinIcon = find.byIcon(Icons.push_pin_rounded);
        expect(unpinIcon, findsOneWidget);

        // MemoryDetailScreen is not opened
        expect(find.byType(MemoryDetailScreen), findsNothing);
      },
    );
  });
}
