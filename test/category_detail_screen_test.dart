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
import 'package:second_brain/features/home/presentation/screens/category_detail_screen.dart';
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

  @override
  Future<void> deleteMemory(String memoryId) async {}
}

Widget createTestApp(CategorySectionItem section, [List<MemoryEntity> memories = const []]) {
  final repo = FakeCaptureRepository(memories);
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
      home: CategoryDetailScreen(section: section),
    ),
  );
}

void main() {
  final testSection = CategorySectionsData.sections.first; // Documents & Records

  group('CategoryDetailScreen Vertical Cards & Animations Redesign', () {
    testWidgets('Renders vertical list instead of 2-column GridView', (tester) async {
      await tester.pumpWidget(createTestApp(testSection));
      await tester.pumpAndSettle();

      // Ensure NO GridView is present
      expect(find.byType(GridView), findsNothing);

      // Ensure ListView is present
      expect(find.byType(ListView), findsOneWidget);

      // Verify all 4 category cards are present vertically
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Certificates & IDs'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('Cards display leading icon, bold title, subtitle badge, and trailing arrow', (tester) async {
      await tester.pumpWidget(createTestApp(testSection));
      await tester.pumpAndSettle();

      // Trailing subtle arrows for each category
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNWidgets(4));

      // Cards category contains "+ Add Card" chip
      expect(find.byKey(const Key('detail_add_card_Cards')), findsOneWidget);

      // Memory count badges are visible
      expect(find.text('0 memories'), findsWidgets);
    });

    testWidgets('Cards have smooth staggered entrance animation', (tester) async {
      await tester.pumpWidget(createTestApp(testSection));

      // Initially at frame 0, cards are animating in
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CategoryDetailScreen), findsOneWidget);

      // Advance through animation
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // All cards fully settled
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Certificates & IDs'), findsOneWidget);
    });

    testWidgets('Tapping category card navigates smoothly to CategoryMemoriesScreen', (tester) async {
      await tester.pumpWidget(createTestApp(testSection));
      await tester.pumpAndSettle();

      // Tap "Documents" card
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      // Pushed CategoryMemoriesScreen
      expect(find.byType(CategoryMemoriesScreen), findsOneWidget);
      expect(find.text('Documents'), findsWidgets);

      // Pop back
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryDetailScreen), findsOneWidget);
      expect(find.byType(CategoryMemoriesScreen), findsNothing);
    });

    testWidgets('Shows dynamic memory counts matching category', (tester) async {
      final docMemory = MemoryEntity(
        id: 'doc-1',
        userId: 'u1',
        title: 'Passport Scan',
        content: 'US Passport',
        category: 'Documents',
        clientCreatedAt: DateTime(2026, 9, 15, 12, 0),
        clientUpdatedAt: DateTime(2026, 9, 15, 12, 0),
        serverUpdatedAt: DateTime(2026, 9, 15, 12, 0),
      );

      await tester.pumpWidget(createTestApp(testSection, [docMemory]));
      await tester.pumpAndSettle();

      expect(find.text('1 memory'), findsOneWidget);
    });
  });
}
