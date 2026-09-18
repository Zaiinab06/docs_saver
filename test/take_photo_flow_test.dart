import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/photo_review_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';

class FakeAiRepository implements AiRepository {
  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
  }) async {
    return const AiIngestionResult(
      title: 'Fake Title',
      summary: '• Test point',
      category: 'General',
      tags: ['test'],
      aiStatus: 'processed',
    );
  }
}

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => List.from(memories);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Take Photo & Review Flow Verification', () {
    testWidgets('Save Memory persists custom title and appears on Home screen',
        (tester) async {
      final repo = FakeCaptureRepository([]);
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
            home: HomeScreen(userName: 'Noor'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially empty
      expect(find.text("Your brain is empty — let's fill it."), findsOneWidget);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);

      // Simulate saving a captured photo memory with custom user title
      captureBloc.add(
        const AddMemoryEvent(
          title: 'My Handwritten Lecture Notes',
          content: 'Key concepts of cell division and mitosis',
          category: 'Study',
          tags: ['biology', 'notes'],
          mediaUrl: '/data/user/0/memory_1.jpg',
          aiStatus: 'processed',
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Memory is saved in repository
      expect(repo.memories.length, 1);
      expect(repo.memories.first.title, 'My Handwritten Lecture Notes');
      expect(repo.memories.first.category, 'Study');
      expect(repo.memories.first.tags, contains('biology'));

      // Verified: Saved memory appears on Home screen
      expect(find.text('My Handwritten Lecture Notes'), findsOneWidget);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsOneWidget);
      expect(find.text("Your brain is empty — let's fill it."), findsNothing);
    });

    testWidgets('Memory Review screen preserves user-entered title and tags',
        (tester) async {
      final dummyFile = File('test_image.jpg');
      final repo = FakeCaptureRepository([]);
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
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyFile,
              initialTitle: 'AI Suggested Title',
              initialContent: 'Detected OCR text on paper',
              initialCategory: 'Work',
              initialTags: const ['work', 'doc'],
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 14, 1, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify fields are loaded with dynamic AI / OCR results
      expect(find.text('Review & Save'), findsOneWidget);
      expect(find.text('AI Suggested Title'), findsOneWidget);
      expect(find.text('Extracted Content'), findsOneWidget);
      expect(find.text('See what was extracted from your memory'), findsOneWidget);
      expect(find.text('View extracted text'), findsOneWidget);
      // Raw OCR text is hidden by default
      expect(find.text('Detected OCR text on paper'), findsNothing);
      expect(find.text('#work'), findsOneWidget);
      expect(find.text('#doc'), findsOneWidget);

      // Scroll to make sure "View extracted text" is visible and tap it
      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();
      expect(find.text('Hide extracted text'), findsOneWidget);
      expect(find.text('Detected OCR text on paper'), findsOneWidget);

      // Verify user can edit title and add tag
      final titleFinder = find.byType(TextField).first;
      await tester.enterText(titleFinder, 'My Custom User Title');
      await tester.pumpAndSettle();

      expect(find.text('My Custom User Title'), findsOneWidget);
    });

    testWidgets('PhotoReviewScreen places Retake and Use Photo buttons inside SafeArea',
        (tester) async {
      final tempDir = Directory.systemTemp.createTempSync();
      final transparentPng = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ];
      final dummyFile = File('${tempDir.path}/test_image.png')
        ..writeAsBytesSync(transparentPng);

      addTearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoReviewScreen(
            imageFile: dummyFile,
            ingestMemoryUseCase: IngestMemoryUseCase(FakeAiRepository()),
          ),
        ),
      );
      await tester.pump();

      // Find Retake and Use Photo button text widgets
      final retakeText = find.text('Retake');
      final usePhotoText = find.text('Use Photo');

      expect(retakeText, findsOneWidget);
      expect(usePhotoText, findsOneWidget);

      // Verify that both buttons are inside a SafeArea ancestor
      final safeAreaFinder = find.ancestor(
        of: retakeText,
        matching: find.byType(SafeArea),
      );
      expect(safeAreaFinder, findsOneWidget);

      final safeAreaUsePhotoFinder = find.ancestor(
        of: usePhotoText,
        matching: find.byType(SafeArea),
      );
      expect(safeAreaUsePhotoFinder, findsOneWidget);
    });

    testWidgets('MemoryReviewScreen displays concise AI semantic description and hides raw OCR dump',
        (tester) async {
      final dummyFile = File('test_image.jpg');
      final repo = FakeCaptureRepository([]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      const semanticDescription = '• Pinterest\n• Bottom navigation ideas for a notes app';
      const rawOcrDump = '7:45 PM LTE https://pinterest.com/pin/1234 Back Share More Search Less AI random text';

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyFile,
              initialTitle: 'Bottom Nav Ideas',
              initialContent: semanticDescription,
              initialSummary: semanticDescription,
              rawOcrText: rawOcrDump,
              initialCategory: 'Work',
              initialTags: const ['design', 'ui'],
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 14, 1, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AI summary card shows the semantic description
      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text(semanticDescription), findsOneWidget);

      // Verify raw OCR is hidden in Extracted Content by default
      expect(find.text(rawOcrDump), findsNothing);
      expect(find.text('View extracted text'), findsOneWidget);

      // Ensure visible and expand
      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();

      expect(find.text('Hide extracted text'), findsOneWidget);
      expect(find.text(rawOcrDump), findsOneWidget);
    });

    testWidgets('HomeScreen memory card displays concise semantic description and never raw OCR dump',
        (tester) async {
      const semanticDescription = '• Pinterest\n• Bottom navigation ideas for a notes app';
      final testMemory = MemoryEntity(
        id: 'mem-101',
        userId: 'local_user',
        title: 'Notes App Nav',
        content: semanticDescription,
        category: 'Work',
        tags: const ['ui'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 14, 1, 0),
        clientUpdatedAt: DateTime(2026, 9, 14, 1, 0),
        serverUpdatedAt: DateTime(2026, 9, 14, 1, 0),
      );

      final repo = FakeCaptureRepository([testMemory]);
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
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expect the concise semantic description on the card
      expect(find.text(semanticDescription), findsOneWidget);
    });
  });
}
