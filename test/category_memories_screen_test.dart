import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/home/domain/models/category_section.dart';
import 'package:second_brain/features/home/presentation/screens/category_memories_screen.dart';

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
  group('CategoryMemoriesScreen Dynamic Empty States & Memory Filtering', () {
    CategoryCardItem findCategoryByName(String name) {
      for (final section in CategorySectionsData.sections) {
        for (final cat in section.categories) {
          if (cat.name == name) return cat;
        }
      }
      throw ArgumentError('Category $name not found in CategorySectionsData');
    }

    Widget createTestApp({
      required CategoryCardItem category,
      List<MemoryEntity> initialMemories = const [],
      VoidCallback? onCaptureTap,
    }) {
      final repo = FakeCaptureRepository(initialMemories);
      return MultiBlocProvider(
        providers: [
          BlocProvider<CaptureBloc>(
            create: (_) => CaptureBloc(
              saveMemoryUseCase: SaveMemoryUseCase(repo),
              getMemoriesUseCase: GetMemoriesUseCase(repo),
              repository: repo,
            )..add(LoadMemoriesEvent()),
          ),
        ],
        child: MaterialApp(
          home: CategoryMemoriesScreen(
            category: category,
            onCaptureTap: onCaptureTap,
          ),
        ),
      );
    }

    testWidgets('Empty State displays dynamic text for Food', (tester) async {
      final foodCat = findCategoryByName('Food');
      await tester.pumpWidget(createTestApp(category: foodCat));
      await tester.pumpAndSettle();

      expect(find.text('No Food memories yet!'), findsOneWidget);
      expect(find.text('Click + to add memories'), findsOneWidget);
      expect(find.text('Add Memory'), findsOneWidget);
    });

    testWidgets('Empty State displays dynamic text for Work', (tester) async {
      final workCat = findCategoryByName('Work');
      await tester.pumpWidget(createTestApp(category: workCat));
      await tester.pumpAndSettle();

      expect(find.text('No Work memories yet!'), findsOneWidget);
      expect(find.text('Click + to add memories'), findsOneWidget);
      expect(find.text('Add Memory'), findsOneWidget);
    });

    testWidgets('Empty State displays dynamic text for Electricity', (
      tester,
    ) async {
      final elecCat = findCategoryByName('Electricity');
      await tester.pumpWidget(createTestApp(category: elecCat));
      await tester.pumpAndSettle();

      expect(find.text('No Electricity memories yet!'), findsOneWidget);
      expect(find.text('Click + to add memories'), findsOneWidget);
      expect(find.text('Add Memory'), findsOneWidget);
    });

    testWidgets('Empty State displays dynamic text for Documents', (
      tester,
    ) async {
      final docCat = findCategoryByName('Documents');
      await tester.pumpWidget(createTestApp(category: docCat));
      await tester.pumpAndSettle();

      expect(find.text('No Documents memories yet!'), findsOneWidget);
      expect(find.text('Click + to add memories'), findsOneWidget);
      expect(find.text('Add Memory'), findsOneWidget);
    });

    testWidgets(
      'Real memories for specific category are displayed and isolated',
      (tester) async {
        final foodMemory = MemoryEntity(
          id: 'food-1',
          userId: 'u1',
          title: 'Homemade Pasta Recipe',
          content: 'Flour, eggs, semolina, knead for 10 minutes.',
          category: 'Food',
          clientCreatedAt: DateTime(2026, 9, 15, 12, 0),
          clientUpdatedAt: DateTime(2026, 9, 15, 12, 0),
          serverUpdatedAt: DateTime(2026, 9, 15, 12, 0),
        );

        final workMemory = MemoryEntity(
          id: 'work-1',
          userId: 'u1',
          title: 'Q4 Budget Review',
          content: 'Financial planning for Q4.',
          category: 'Work',
          clientCreatedAt: DateTime(2026, 9, 15, 13, 0),
          clientUpdatedAt: DateTime(2026, 9, 15, 13, 0),
          serverUpdatedAt: DateTime(2026, 9, 15, 13, 0),
        );

        final foodCat = findCategoryByName('Food');
        await tester.pumpWidget(
          createTestApp(
            category: foodCat,
            initialMemories: [foodMemory, workMemory],
          ),
        );
        await tester.pumpAndSettle();

        // Food memory is displayed
        expect(find.text('Homemade Pasta Recipe'), findsOneWidget);
        // Work memory is NOT displayed in Food screen
        expect(find.text('Q4 Budget Review'), findsNothing);
        // Empty state is NOT displayed
        expect(find.text('No Food memories yet!'), findsNothing);
      },
    );

    testWidgets('AppBar + button triggers capture action', (tester) async {
      bool captureTapped = false;
      final foodCat = findCategoryByName('Food');
      await tester.pumpWidget(
        createTestApp(
          category: foodCat,
          onCaptureTap: () {
            captureTapped = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap AppBar + button
      await tester.tap(find.byKey(const Key('category_memories_add_btn')));
      await tester.pumpAndSettle();

      expect(captureTapped, isTrue);
    });

    testWidgets(
      'Empty state Add Memory button triggers default capture sheet when no callback provided',
      (tester) async {
        final foodCat = findCategoryByName('Food');
        await tester.pumpWidget(createTestApp(category: foodCat));
        await tester.pumpAndSettle();

        // Tap empty state Add Memory button
        await tester.tap(find.byKey(const Key('empty_state_add_btn')));
        await tester.pumpAndSettle();

        // Existing capture sheet options appear
        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Scan Document'), findsOneWidget);
        expect(find.text('Add Link'), findsOneWidget);
        expect(find.text('Add Note'), findsOneWidget);
        expect(find.text('Record Voice'), findsOneWidget);
        expect(find.text('Choose File'), findsOneWidget);
      },
    );
  });
}
