import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';
import 'package:second_brain/features/search/presentation/screens/search_screen.dart';

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
  group('HomeScreen UI & State Verification Tests', () {
    late MemoryEntity workMemory;
    late MemoryEntity studyMemory;
    late MemoryEntity personalMemory;
    late MemoryEntity travelMemory;

    setUp(() {
      workMemory = MemoryEntity(
        id: 'mem-work-1',
        userId: 'user-1',
        title: 'Project Roadmap Q4',
        content: 'Sprint planning and quarterly roadmap objectives.',
        category: 'Work',
        tags: const ['roadmap', 'sprint'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 10, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 10, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 10, 0),
      );

      studyMemory = MemoryEntity(
        id: 'mem-study-1',
        userId: 'user-1',
        title: 'Quantum Physics Notes',
        content: 'Wave particle duality and Schrodinger equations.',
        category: 'Study',
        tags: const ['physics', 'science'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 11, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 11, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 11, 0),
      );

      personalMemory = MemoryEntity(
        id: 'mem-personal-1',
        userId: 'user-1',
        title: 'Weekend Hiking Idea',
        content: 'Trail route and packing list for mountain ridge.',
        category: 'Personal',
        tags: const ['hiking'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 9, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 9, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 9, 0),
      );

      travelMemory = MemoryEntity(
        id: 'mem-travel-1',
        userId: 'user-1',
        title: 'Kyoto Trip Itinerary',
        content: 'Temples, bamboo forest, and traditional ryokan stay.',
        category: 'Travel',
        tags: const ['japan', 'trip'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 13, 8, 0),
        clientUpdatedAt: DateTime(2026, 9, 13, 8, 0),
        serverUpdatedAt: DateTime(2026, 9, 13, 8, 0),
      );
    });

    Widget createTestApp(List<MemoryEntity> initialMemories, {String? userName}) {
      final repo = FakeCaptureRepository(initialMemories);
      return MultiBlocProvider(
        providers: [
          BlocProvider<CaptureBloc>(
            create: (_) => CaptureBloc(
              saveMemoryUseCase: SaveMemoryUseCase(repo),
              getMemoriesUseCase: GetMemoriesUseCase(repo),
              repository: repo,
            ),
          ),
        ],
        child: MaterialApp(
          home: HomeScreen(userName: userName),
        ),
      );
    }

    testWidgets('State A: No memories -> All selected -> correct empty state -> Recent Memories hidden',
        (tester) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Header is visible with dynamic fallback greeting, waving hand emoji, and ready subtitle
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('👋'), findsOneWidget);
      expect(find.text('Your second brain is ready'), findsOneWidget);

      // Search bar hint is visible
      expect(find.text(AppStrings.homeSearchHint), findsOneWidget);

      // Category chips are visible with All selected
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);

      // Empty state illustration and exact copy
      expect(find.text("Your brain is empty — let's fill it."), findsOneWidget);
      expect(
        find.text('Save your first thought, link, image, or note using the + button.'),
        findsOneWidget,
      );

      // "Recent Memories" and "See all >" must be hidden
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);
      expect(find.text(AppStrings.homeSeeAll), findsNothing);
    });

    testWidgets('State B: Memories exist -> All selected by default -> all actual memories visible -> Recent Memories visible',
        (tester) async {
      await tester.pumpWidget(createTestApp([workMemory, studyMemory, personalMemory, travelMemory]));
      await tester.pumpAndSettle();

      // Recent Memories header and See all > are visible
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsOneWidget);
      expect(find.text(AppStrings.homeSeeAll), findsOneWidget);

      // Top sorted memories (newest first) are visible
      expect(find.text('Quantum Physics Notes'), findsOneWidget);
      expect(find.text('Project Roadmap Q4'), findsOneWidget);

      // Scroll down to reveal remaining memories
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('Weekend Hiking Idea'), findsOneWidget);
      expect(find.text('Kyoto Trip Itinerary'), findsOneWidget);

      // Empty state is NOT visible
      expect(find.text("Your brain is empty — let's fill it."), findsNothing);
    });

    testWidgets('State C: Tap Work -> Only Work memories visible',
        (tester) async {
      await tester.pumpWidget(createTestApp([workMemory, studyMemory]));
      await tester.pumpAndSettle();

      // Tap Work category chip
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      // Only Work memory is displayed
      expect(find.text('Project Roadmap Q4'), findsOneWidget);
      expect(find.text('Quantum Physics Notes'), findsNothing);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsOneWidget);
    });

    testWidgets('State D: Tap Personal -> Only Personal memories or category empty state',
        (tester) async {
      await tester.pumpWidget(createTestApp([workMemory, personalMemory]));
      await tester.pumpAndSettle();

      // Tap Personal
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();

      // Only Personal memory is displayed
      expect(find.text('Weekend Hiking Idea'), findsOneWidget);
      expect(find.text('Project Roadmap Q4'), findsNothing);
    });

    testWidgets('State E & F: Tap Study & Travel -> Only respective category memories',
        (tester) async {
      await tester.pumpWidget(createTestApp([studyMemory, travelMemory]));
      await tester.pumpAndSettle();

      // Tap Study
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('Quantum Physics Notes'), findsOneWidget);
      expect(find.text('Kyoto Trip Itinerary'), findsNothing);

      // Tap Travel
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();
      expect(find.text('Kyoto Trip Itinerary'), findsOneWidget);
      expect(find.text('Quantum Physics Notes'), findsNothing);
    });

    testWidgets('Category empty state shows dynamic category text',
        (tester) async {
      await tester.pumpWidget(createTestApp([workMemory]));
      await tester.pumpAndSettle();

      // Tap Travel (which has 0 memories)
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();

      // Category empty state title and subtitle
      expect(find.text('No Travel memories yet'), findsOneWidget);
      expect(find.text('Save your first Travel memory using the + button.'), findsOneWidget);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);
    });

    testWidgets('State G: Search bar opens SearchScreen',
        (tester) async {
      await tester.pumpWidget(createTestApp([workMemory]));
      await tester.pumpAndSettle();

      // Tap the search bar
      await tester.tap(find.text(AppStrings.homeSearchHint));
      await tester.pumpAndSettle();

      // SearchScreen should be pushed
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('State H1: Bell button works and provides feedback',
        (tester) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Tap Bell
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pump();
      expect(find.text('No new notifications'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('State H2: Profile avatar button works with fallback user',
        (tester) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Tap Profile avatar
      await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
      await tester.pump();
      expect(find.text("Your Second Brain"), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Dynamic User Name: Noor displays Hello Noor and initial N',
        (tester) async {
      await tester.pumpWidget(createTestApp([], userName: 'Noor'));
      await tester.pumpAndSettle();

      expect(find.text('Hello Noor'), findsOneWidget);
      expect(find.text('N'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
      await tester.pump();
      expect(find.text("Noor's Second Brain"), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Dynamic User Name: Zainab displays Hello Zainab and initial Z',
        (tester) async {
      await tester.pumpWidget(createTestApp([], userName: 'Zainab'));
      await tester.pumpAndSettle();

      expect(find.text('Hello Zainab'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
      await tester.pump();
      expect(find.text("Zainab's Second Brain"), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('State I: + capture button opens the bottom sheet with Take Photo',
        (tester) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Verify bottom sheet appears with Take Photo
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Scan Document'), findsOneWidget);
    });
  });
}
