import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/home/presentation/screens/category_detail_screen.dart';
import 'package:second_brain/features/home/presentation/screens/category_memories_screen.dart';
import 'package:second_brain/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';
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

  @override
  Future<void> deleteMemory(String memoryId) async {}
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
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize =
          const Size(800, 1400);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    Widget createTestApp(
      List<MemoryEntity> initialMemories, {
      String? userName,
    }) {
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
        child: MaterialApp(home: MainNavigationShell(userName: userName)),
      );
    }

    testWidgets(
      'State A: No memories -> Top Header, Categories, Pro Banner, Quick Actions, and Empty Recent Memories',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Header is visible with dynamic fallback greeting, waving hand emoji, and subtitle
        expect(find.text('Hey there'), findsOneWidget);
        expect(find.text('👋'), findsOneWidget);
        expect(find.text("Let's capture more ideas today"), findsOneWidget);

        // Header action buttons are visible
        expect(find.byKey(const Key('home_search_btn')), findsOneWidget);
        expect(find.byKey(const Key('home_bell_btn')), findsOneWidget);

        // Category section cards visible
        expect(find.text('Docs & Records'), findsOneWidget);
        expect(find.text('Work & Learning'), findsWidgets);
        expect(find.text('Home & Utilities'), findsWidgets);
        expect(find.text('Personal'), findsWidgets);

        // Upgrade banner is visible
        expect(find.textContaining('Upgrade to DocsSaver'), findsOneWidget);
        expect(find.text('Go Pro →'), findsOneWidget);

        // Quick Actions are visible
        expect(find.text('Take Photo'), findsWidgets);
        expect(find.text('Smart Scan'), findsWidgets);

        // Recent Memories section is visible with empty fallback card
        expect(find.text('Recent memories'), findsOneWidget);
        expect(find.text('No recent memories yet'), findsOneWidget);
      },
    );

    testWidgets(
      'State B: Memories exist -> 4 category section cards visible -> Recent Memories list displayed',
      (tester) async {
        await tester.pumpWidget(
          createTestApp([
            workMemory,
            studyMemory,
            personalMemory,
            travelMemory,
          ]),
        );
        await tester.pumpAndSettle();

        // Four category section cards are visible
        expect(find.text('Docs & Records'), findsOneWidget);
        expect(find.text('Work & Learning'), findsWidgets);
        expect(find.text('Home & Utilities'), findsWidgets);
        expect(find.text('Personal'), findsWidgets);

        // Recent Memories header is visible without total count badge
        expect(find.text('Recent memories'), findsOneWidget);
        expect(find.text('4 total'), findsNothing);
        expect(find.text('See all'), findsOneWidget);

        // Recent memories are displayed
        expect(find.text('Project Roadmap Q4'), findsOneWidget);
        expect(find.text('Quantum Physics Notes'), findsOneWidget);
      },
    );

    testWidgets(
      'Category Section Navigation: Tap Documents & Records opens CategoryDetailScreen with 4 subcategories',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Tap "Docs & Records" section card
        await tester.tap(find.text('Docs & Records'));
        await tester.pumpAndSettle();

        // CategoryDetailScreen is displayed with section title and badge
        expect(find.byType(CategoryDetailScreen), findsOneWidget);
        expect(find.text('Documents & Records'), findsWidgets);
        expect(find.text('4 Categories'), findsOneWidget);

        // Subcategories are visible
        expect(find.text('Documents'), findsOneWidget);
        expect(find.text('Certificates & IDs'), findsOneWidget);
        expect(find.text('Cards'), findsOneWidget);
        expect(find.text('Contacts'), findsOneWidget);

        // Back button pops back to HomeScreen
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(CategoryDetailScreen), findsNothing);
        expect(find.text('Docs & Records'), findsOneWidget);
      },
    );

    testWidgets(
      'Category Section Navigation: Tap Work & Learning opens CategoryDetailScreen with 2 subcategories',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Tap "Work & Learning" section card
        await tester.tap(find.text('Work & Learning').first);
        await tester.pumpAndSettle();

        // CategoryDetailScreen is displayed
        expect(find.byType(CategoryDetailScreen), findsOneWidget);
        expect(find.text('Work & Learning'), findsWidgets);
        expect(find.text('2 Categories'), findsOneWidget);

        // Subcategories
        expect(find.text('Work'), findsOneWidget);
        expect(find.text('Study & Education'), findsOneWidget);

        // Pop back
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailScreen), findsNothing);
        expect(find.text('Work & Learning'), findsWidgets);
      },
    );

    testWidgets(
      'Category Section Navigation: Tap Home & Utilities opens CategoryDetailScreen with 4 subcategories',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Home & Utilities').first);
        await tester.pumpAndSettle();

        // CategoryDetailScreen is displayed
        expect(find.byType(CategoryDetailScreen), findsOneWidget);
        expect(find.text('Home & Utilities'), findsWidgets);
        expect(find.text('4 Categories'), findsOneWidget);

        // Subcategories
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Water'), findsOneWidget);
        expect(find.text('Electricity'), findsOneWidget);
        expect(find.text('Gas'), findsOneWidget);

        // Pop back
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailScreen), findsNothing);
        expect(find.text('Home & Utilities'), findsWidgets);
      },
    );

    testWidgets(
      'Category Section Navigation: Tap Personal Life opens CategoryDetailScreen with 7 subcategories',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Tap "Personal"
        await tester.tap(find.text('Personal').first);
        await tester.pumpAndSettle();

        // CategoryDetailScreen is displayed
        expect(find.byType(CategoryDetailScreen), findsOneWidget);
        expect(find.text('Personal Life'), findsWidgets);
        expect(find.text('7 Categories'), findsOneWidget);

        // Subcategories
        expect(find.text('Personal'), findsWidgets);
        expect(find.text('Medical & Health'), findsOneWidget);
        expect(find.text('Finance & Banking'), findsOneWidget);
        expect(find.text('Travel & Tickets'), findsOneWidget);
        expect(find.text('Fashion'), findsOneWidget);
        expect(find.text('Food'), findsOneWidget);
        expect(find.text('Shopping & Products'), findsOneWidget);

        // Pop back
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailScreen), findsNothing);
      },
    );

    testWidgets(
      'Child category navigation: Tap Work opens CategoryMemoriesScreen with dynamic empty state',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Tap "Work & Learning" parent section
        await tester.tap(find.text('Work & Learning').first);
        await tester.pumpAndSettle();

        // Tap "Work" child category card
        await tester.tap(find.text('Work').first);
        await tester.pumpAndSettle();

        // CategoryMemoriesScreen is pushed
        expect(find.byType(CategoryMemoriesScreen), findsOneWidget);
        expect(find.text('Work'), findsWidgets);

        // Dynamic empty state verification
        expect(find.text('No Work yet'), findsOneWidget);
        expect(find.text('or click + for other capture methods'), findsOneWidget);

        // Back navigation to CategoryDetailScreen
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryMemoriesScreen), findsNothing);
        expect(find.byType(CategoryDetailScreen), findsOneWidget);

        // Back navigation to HomeScreen
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailScreen), findsNothing);
        expect(find.text('Work & Learning'), findsWidgets);
      },
    );

    testWidgets(
      'CategoryMemoriesScreen displays real memories and navigates to MemoryDetailScreen',
      (tester) async {
        await tester.pumpWidget(
          createTestApp([workMemory, studyMemory, personalMemory]),
        );
        await tester.pumpAndSettle();

        // Tap "Work & Learning" parent section
        await tester.tap(find.text('Work & Learning').first);
        await tester.pumpAndSettle();

        // Tap "Work" child category card
        await tester.tap(find.text('Work').first);
        await tester.pumpAndSettle();

        // CategoryMemoriesScreen is displayed
        expect(find.byType(CategoryMemoriesScreen), findsOneWidget);

        // Only real Work memory is shown
        expect(find.text('Project Roadmap Q4'), findsOneWidget);
        expect(find.text('Quantum Physics Notes'), findsNothing);
        expect(find.text('Weekend Hiking Idea'), findsNothing);

        // Empty state is NOT visible
        expect(find.text('No Work memories yet!'), findsNothing);

        // Tap the memory card to open MemoryDetailScreen
        await tester.tap(find.text('Project Roadmap Q4'));
        await tester.pumpAndSettle();

        expect(find.byType(MemoryDetailScreen), findsOneWidget);
        expect(find.text('Project Roadmap Q4'), findsWidgets);

        // Pop back to CategoryMemoriesScreen
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailScreen), findsNothing);
        expect(find.byType(CategoryMemoriesScreen), findsOneWidget);
      },
    );

    testWidgets(
      '+ button on CategoryMemoriesScreen opens existing capture flow',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Navigate: Home -> Work & Learning -> Work
        await tester.tap(find.text('Work & Learning').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').first);
        await tester.pumpAndSettle();

        // Tap + button in empty state (or AppBar action)
        await tester.tap(find.byKey(const Key('empty_state_add_btn')));
        await tester.pumpAndSettle();

        // Verify the capture bottom sheet appears with options
        expect(find.text('Take Photo'), findsWidgets);
        expect(find.text('Scan Document'), findsWidgets);
        expect(find.text('Add Link'), findsWidgets);
        expect(find.text('Add Note'), findsWidgets);
        expect(find.text('Voice Note'), findsWidgets);
        expect(find.text('Choose File'), findsWidgets);
      },
    );

    testWidgets('State G: Search button opens SearchScreen', (tester) async {
      await tester.pumpWidget(createTestApp([workMemory]));
      await tester.pumpAndSettle();

      // Tap the search button in header
      await tester.tap(find.byKey(const Key('home_search_btn')));
      await tester.pumpAndSettle();

      // SearchScreen should be pushed
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('State H1: Bell button works and provides feedback', (
      tester,
    ) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Tap Bell
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pump();
      expect(find.text('No new notifications'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('State H2: Profile avatar button works with fallback user', (
      tester,
    ) async {
      await tester.pumpWidget(createTestApp([]));
      await tester.pumpAndSettle();

      // Tap Profile avatar
      await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
      await tester.pump();
      expect(find.text("Your Second Brain"), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Dynamic User Name: Noor displays Hey Noor and initial N', (
      tester,
    ) async {
      await tester.pumpWidget(createTestApp([], userName: 'Noor'));
      await tester.pumpAndSettle();

      expect(find.text('Hey Noor'), findsOneWidget);
      expect(find.text('N'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
      await tester.pump();
      expect(find.text("Noor's Second Brain"), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Dynamic User Name: Zainab displays Hey Zainab and initial Z',
      (tester) async {
        await tester.pumpWidget(createTestApp([], userName: 'Zainab'));
        await tester.pumpAndSettle();

        expect(find.text('Hey Zainab'), findsOneWidget);
        expect(find.text('Z'), findsOneWidget);

        await tester.tap(find.byKey(const Key('home_profile_avatar_btn')));
        await tester.pump();
        expect(find.text("Zainab's Second Brain"), findsOneWidget);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'State I: + capture button opens the bottom sheet with Take Photo',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Tap center + capture button in bottom nav
        await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
        await tester.pumpAndSettle();

        // Verify bottom sheet appears with Take Photo
        expect(find.text('What do you want to save?'), findsOneWidget);
        expect(find.text('Take Photo'), findsNWidgets(2));
        expect(find.text('Smart Scan'), findsOneWidget);
        expect(find.text('Scan Document'), findsOneWidget);
      },
    );

    testWidgets(
      'Recent memories See all navigates to SavedScreen tab',
      (tester) async {
        await tester.pumpWidget(createTestApp([workMemory]));
        await tester.pumpAndSettle();

        // Tap See all beside Recent memories
        await tester.tap(find.byKey(const Key('home_recent_memories_see_all_btn')));
        await tester.pumpAndSettle();

        // SavedScreen is now displayed
        expect(find.byType(SavedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Pro Upgrade Banner: Tap close button dismisses the banner cleanly',
      (tester) async {
        await tester.pumpWidget(createTestApp([]));
        await tester.pumpAndSettle();

        // Initially visible
        expect(find.textContaining('Upgrade to DocsSaver'), findsOneWidget);
        expect(find.text('Unlock smart reminders and other features'), findsOneWidget);
        expect(find.byKey(const Key('pro_banner_close_btn')), findsOneWidget);

        // Tap close (X) button
        await tester.tap(find.byKey(const Key('pro_banner_close_btn')));
        await tester.pumpAndSettle();

        // Banner is now dismissed
        expect(find.textContaining('Upgrade to DocsSaver'), findsNothing);
        expect(find.byKey(const Key('pro_banner_close_btn')), findsNothing);
        expect(find.text('Categories'), findsOneWidget);
      },
    );
  });
}
