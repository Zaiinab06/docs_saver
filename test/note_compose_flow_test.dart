import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_state.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/note_compose_screen.dart';
import 'package:second_brain/features/navigation/presentation/screens/main_navigation_shell.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async =>
      List.from(memories);

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
  group('Add Note Feature & NoteComposeScreen Tests', () {
    late FakeCaptureRepository repo;
    late CaptureBloc captureBloc;

    setUp(() {
      repo = FakeCaptureRepository([]);
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );
    });

    tearDown(() {
      captureBloc.close();
    });

    Widget createTestApp(Widget homeWidget, {WidgetTester? tester}) {
      if (tester != null) {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      return MultiBlocProvider(
        providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
        child: MaterialApp(home: homeWidget),
      );
    }

    testWidgets(
      '1. Add Note opens correctly from the capture sheet in MainNavigationShell',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const MainNavigationShell(), tester: tester),
        );
        await tester.pumpAndSettle();

        // Tap center + capture button in bottom nav
        await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
        await tester.pumpAndSettle();

        // Verify bottom sheet appears with Add Note
        expect(find.text('Add Note'), findsWidgets);
        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Scan Document'), findsOneWidget);
        expect(find.text('Add Link'), findsOneWidget);

        // Tap "Add Note"
        await tester.tap(find.text('Add Note').last);
        await tester.pumpAndSettle();

        // Verify NoteComposeScreen is pushed
        expect(find.byType(NoteComposeScreen), findsOneWidget);
        expect(find.text('Add Note'), findsOneWidget);
        expect(find.byKey(const Key('note_title_field')), findsOneWidget);
        expect(find.byKey(const Key('note_content_field')), findsOneWidget);
        expect(find.byKey(const Key('save_note_button')), findsOneWidget);
      },
    );

    testWidgets(
      '2. Empty content cannot be saved and displays validation error SnackBar',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const NoteComposeScreen(), tester: tester),
        );
        await tester.pumpAndSettle();

        // Leave content field empty and tap Save Note
        await tester.tap(find.byKey(const Key('save_note_button')));
        await tester.pump();

        // Verify validation message is shown
        expect(
          find.text('Please enter note content before saving.'),
          findsOneWidget,
        );

        // Verify no memory was added to repository
        expect(repo.memories, isEmpty);
      },
    );

    testWidgets(
      '3. Add Note can be saved with only content and user content is preserved exactly',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const NoteComposeScreen(), tester: tester),
        );
        await tester.pumpAndSettle();

        const rawNoteBody =
            'Line 1: Meeting follow-up\nLine 2: Important discussion points\n  • Sub-bullet with indentation\nSpecial symbols: #flutter @secondbrain & 100%';

        // Enter only content (title blank, no category selected, no tags added)
        await tester.enterText(
          find.byKey(const Key('note_content_field')),
          rawNoteBody,
        );

        // Tap Save Note
        await tester.tap(find.byKey(const Key('save_note_button')));
        await tester.pumpAndSettle();

        // Verify memory was saved
        expect(repo.memories.length, 1);
        final saved = repo.memories.first;

        // Deterministic title auto-derived from first line
        expect(saved.title, 'Line 1: Meeting follow-up');
        // Content preserved exactly with every whitespace and symbol
        expect(saved.content, rawNoteBody);
        // Category defaults to General when auto/unspecified
        expect(saved.category, AppStrings.categoryGeneral);
        // Tags list is empty (no fake tags added)
        expect(saved.tags, isEmpty);
        // MediaUrl is null for manual notes
        expect(saved.mediaUrl, isNull);
        // Status is pending for real AI organization
        expect(saved.aiStatus, 'pending');
      },
    );

    testWidgets(
      '4. User-provided category and tags override AI defaults and take precedence',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const NoteComposeScreen(), tester: tester),
        );
        await tester.pumpAndSettle();

        // Enter custom title
        await tester.enterText(
          find.byKey(const Key('note_title_field')),
          'Q3 Product Roadmap Review',
        );

        // Enter note content
        await tester.enterText(
          find.byKey(const Key('note_content_field')),
          'Key priorities for Q3: offline sync reliability and vector search speed.',
        );

        // Explicitly select category 'Work'
        await tester.tap(find.byKey(const Key('category_chip_work')));
        await tester.pumpAndSettle();

        // Add user-defined tags
        await tester.enterText(
          find.byKey(const Key('tag_input_field')),
          'roadmap',
        );
        await tester.tap(find.byKey(const Key('add_tag_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('tag_input_field')),
          'priority',
        );
        await tester.tap(find.byKey(const Key('add_tag_button')));
        await tester.pumpAndSettle();

        expect(find.text('#roadmap'), findsOneWidget);
        expect(find.text('#priority'), findsOneWidget);

        // Tap Save Note
        await tester.tap(find.byKey(const Key('save_note_button')));
        await tester.pumpAndSettle();

        expect(repo.memories.length, 1);
        final saved = repo.memories.first;

        expect(saved.title, 'Q3 Product Roadmap Review');
        expect(saved.category, AppStrings.categoryWork);
        expect(saved.tags, ['roadmap', 'priority']);
        expect(saved.aiStatus, 'pending');
      },
    );

    testWidgets(
      '5. Offline note saving does not create fake AI data and preserves original content',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const NoteComposeScreen(), tester: tester),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('note_content_field')),
          'Drafting offline thoughts without any internet access.',
        );

        await tester.tap(find.byKey(const Key('save_note_button')));
        await tester.pumpAndSettle();

        expect(repo.memories.length, 1);
        final saved = repo.memories.first;

        // Strictly zero fabricated AI data
        expect(saved.aiStatus, 'pending');
        expect(saved.embedding, isNull);
        expect(
          saved.content,
          'Drafting offline thoughts without any internet access.',
        );
      },
    );

    test(
      '6. Real AI ingestion results update memory and persist enriched metadata while protecting content',
      () async {
        captureBloc.add(
          const AddMemoryEvent(
            title: 'My Handwritten Notes',
            content: 'Important thoughts about thermodynamics and entropy.',
            category: 'General',
            tags: [],
            mediaUrl: null,
            aiStatus: 'pending',
          ),
        );
        await captureBloc.stream.firstWhere((state) => state is CaptureLoaded);

        final stateBefore = captureBloc.state as CaptureLoaded;
        expect(stateBefore.memories.length, 1);
        final originalId = stateBefore.memories.first.id;
        final originalUserId = stateBefore.memories.first.userId;

        // Simulate real production AI update event (from Supabase Edge Function / Realtime)
        final enrichedMemory = MemoryEntity(
          id: originalId,
          userId: originalUserId,
          title: 'Thermodynamics & Entropy Notes',
          content:
              'Important thoughts about thermodynamics and entropy.', // Preserved!
          category: 'Study', // AI categorized
          tags: const ['physics', 'thermodynamics'], // AI tagged
          embedding: List.filled(768, 0.05), // Real 768-d embedding
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
          isSynced: true,
        );

        captureBloc.add(MemoryUpdatedEvent(enrichedMemory));
        await captureBloc.stream.firstWhere(
          (state) =>
              state is CaptureLoaded &&
              state.memories.first.aiStatus == 'processed',
        );

        final stateAfter = captureBloc.state as CaptureLoaded;
        final updated = stateAfter.memories.first;

        // Content was strictly preserved
        expect(
          updated.content,
          'Important thoughts about thermodynamics and entropy.',
        );
        // Enriched metadata is persisted
        expect(updated.title, 'Thermodynamics & Entropy Notes');
        expect(updated.category, 'Study');
        expect(updated.tags, ['physics', 'thermodynamics']);
        expect(updated.embedding?.length, 768);
        expect(updated.aiStatus, 'processed');
      },
    );

    testWidgets('7. Custom tag deletion works properly in NoteComposeScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(const NoteComposeScreen(), tester: tester),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('tag_input_field')), 'temp');
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      expect(find.text('#temp'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete_tag_temp')));
      await tester.pumpAndSettle();
      expect(find.text('#temp'), findsNothing);
    });

    testWidgets(
      '8. Existing Photo, Document Scan, and Add Link sheet triggers remain intact',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const MainNavigationShell(), tester: tester),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Scan Document'), findsOneWidget);
        expect(find.text('Add Link'), findsOneWidget);
        expect(find.text('Add Note'), findsWidgets);

        await tester.tap(find.text('Add Link'));
        await tester.pumpAndSettle();
        expect(find.text('Add Web Link'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
      },
    );

    testWidgets(
      '9. As soon as AI ingestion completes, currently open MemoryDetailScreen automatically updates to AI Organized and displays enriched category/tags/entities without a Home refresh',
      (tester) async {
        final initialNote = MemoryEntity(
          id: 'note-refresh-test-id',
          userId: 'test_user',
          title: 'Project Roadmap Notes',
          content:
              'Discussing Q4 deliverables, milestones, and deployment timeline.',
          category: 'General',
          tags: const [],
          aiStatus: 'pending',
          clientCreatedAt: DateTime(2026, 9, 17, 10, 0),
          clientUpdatedAt: DateTime(2026, 9, 17, 10, 0),
          serverUpdatedAt: DateTime(2026, 9, 17, 10, 0),
          isSynced: true,
        );

        repo.memories.add(initialNote);
        captureBloc.add(LoadMemoriesEvent());

        // Open MemoryDetailScreen directly while AI ingestion is still pending
        await tester.pumpWidget(
          createTestApp(
            MemoryDetailScreen(
              memoryId: initialNote.id,
              initialMemory: initialNote,
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        // Verify that while pending, MemoryDetail shows "Organizing your memory..." and initial category
        expect(find.text('Organizing your memory...'), findsOneWidget);
        expect(find.text('AI Organized'), findsNothing);
        expect(find.text('General'), findsAtLeastNWidgets(1));

        // Simulate Gemini AI ingestion completion updating the memory in production pipeline
        final enrichedNote = MemoryEntity(
          id: initialNote.id,
          userId: initialNote.userId,
          title: initialNote.title,
          content: initialNote.content, // Content strictly preserved
          category: 'Work', // AI categorized
          tags: const ['roadmap', 'milestones'], // AI tagged
          embedding: List.filled(768, 0.02),
          aiStatus: 'processed', // AI processing completed
          clientCreatedAt: initialNote.clientCreatedAt,
          clientUpdatedAt: initialNote.clientUpdatedAt,
          serverUpdatedAt: DateTime.now(),
          isSynced: true,
        );

        // Dispatch real memory update event to BLoC (triggered by ingestion completion)
        await tester.runAsync(() async {
          final future = captureBloc.stream.firstWhere(
            (state) =>
                state is CaptureLoaded &&
                state.memories.any(
                  (m) => m.id == initialNote.id && m.aiStatus == 'processed',
                ),
          );
          captureBloc.add(MemoryUpdatedEvent(enrichedNote));
          await future;
        });
        await tester.pumpAndSettle();

        // EXPECTED: MemoryDetailScreen must automatically update:
        // 1. Status badge updates to "AI Organized"
        expect(find.text('AI Organized'), findsOneWidget);
        expect(find.text('Organizing your memory...'), findsNothing);

        // 2. Newly generated category is displayed
        expect(find.text('Work'), findsAtLeastNWidgets(1));

        // 3. Newly generated tags are displayed
        expect(find.text('#roadmap'), findsOneWidget);
        expect(find.text('#milestones'), findsOneWidget);

        // 4. Living Memory Knowledge Graph is removed
        expect(find.text('Living Memory Knowledge Graph'), findsNothing);
      },
    );
  });
}
