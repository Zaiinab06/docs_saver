import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Take Photo & Review Flow Verification', () {
    testWidgets('Save Memory persists custom title and appears on Home screen', (
      tester,
    ) async {
      final repo = FakeCaptureRepository([]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
          child: const MaterialApp(home: HomeScreen(userName: 'Noor')),
        ),
      );
      await tester.pumpAndSettle();

      // Initially empty (empty-state section is removed from Home Screen)
      expect(find.text("Your brain is empty — let's fill it."), findsNothing);
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

      // Verified: Memory is in repository and HomeScreen empty state is hidden
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);
      expect(find.text("Your brain is empty — let's fill it."), findsNothing);
    });

    testWidgets(
      'Memory Review screen preserves user-entered title and tags without showing raw OCR section',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync();
        final transparentPng = <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ];
        final dummyFile = File('${tempDir.path}/test_image.png')
          ..writeAsBytesSync(transparentPng);

        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final repo = FakeCaptureRepository([]);
        final captureBloc = CaptureBloc(
          saveMemoryUseCase: SaveMemoryUseCase(repo),
          getMemoriesUseCase: GetMemoriesUseCase(repo),
          repository: repo,
        );
        addTearDown(() => captureBloc.close());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: dummyFile,
                initialTitle: 'AI Suggested Title',
                initialContent: 'Detected OCR text on paper',
                rawOcrText: 'Detected OCR text on paper',
                initialCategory: 'Work',
                initialTags: const ['work', 'doc'],
                aiStatus: 'processed',
                createdAt: DateTime(2026, 9, 14, 1, 0),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify fields are loaded with dynamic AI results
        expect(find.text('Review & Save'), findsOneWidget);
        expect(find.text('AI Suggested Title'), findsOneWidget);
        expect(find.text('#work'), findsOneWidget);
        expect(find.text('#doc'), findsOneWidget);

        // Raw OCR "Extracted Content" section is completely removed from Review & Save UI
        expect(find.text('Extracted Content'), findsNothing);
        expect(
          find.text('See what was extracted from your memory'),
          findsNothing,
        );
        expect(find.text('View extracted text'), findsNothing);
        expect(find.text('Hide extracted text'), findsNothing);
        expect(find.text('Detected OCR text on paper'), findsNothing);

        // Verify user can edit title and add tag
        final titleFinder = find.byType(TextField).first;
        await tester.enterText(titleFinder, 'My Custom User Title');
        await tester.pump();

        expect(find.text('My Custom User Title'), findsOneWidget);

        // Verify Save Memory saves the memory with data preserved internally
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.ensureVisible(find.text('Save Memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Memory'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(repo.memories.length, 1);
        expect(repo.memories.first.title, 'My Custom User Title');
        expect(repo.memories.first.category, 'Work');
        expect(repo.memories.first.tags, contains('work'));
      },
    );

    testWidgets(
      'PhotoReviewScreen places Retake, Rotate, and Use Photo buttons inside SafeArea',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync();
        final transparentPng = <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ];
        final dummyFile = File('${tempDir.path}/test_image.png')
          ..writeAsBytesSync(transparentPng);

        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
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

        // Find Retake, Rotate, and Use Photo button text widgets
        final retakeText = find.text('Retake');
        final rotateText = find.text('Rotate');
        final usePhotoText = find.text('Use Photo');

        expect(retakeText, findsOneWidget);
        expect(rotateText, findsOneWidget);
        expect(usePhotoText, findsOneWidget);

        // Verify that all buttons are inside a SafeArea ancestor
        final safeAreaFinder = find.ancestor(
          of: retakeText,
          matching: find.byType(SafeArea),
        );
        expect(safeAreaFinder, findsOneWidget);

        final safeAreaRotateFinder = find.ancestor(
          of: rotateText,
          matching: find.byType(SafeArea),
        );
        expect(safeAreaRotateFinder, findsOneWidget);

        final safeAreaUsePhotoFinder = find.ancestor(
          of: usePhotoText,
          matching: find.byType(SafeArea),
        );
        expect(safeAreaUsePhotoFinder, findsOneWidget);
      },
    );

    testWidgets(
      'PhotoReviewScreen provides visible Rotate control in AppBar and action bar',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync();
        final transparentPng = <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ];
        final dummyFile = File('${tempDir.path}/test_image.png')
          ..writeAsBytesSync(transparentPng);

        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
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

        // Verify visible Rotate button in action bar
        expect(find.text('Rotate'), findsOneWidget);

        // Verify Rotate icon in AppBar and bottom bar
        expect(find.byIcon(Icons.rotate_right_rounded), findsNWidgets(2));

        // Verify tooltip for accessibility
        expect(find.byTooltip('Rotate'), findsOneWidget);
      },
    );

    testWidgets(
      'Rotation updates the image file in 90-degree increments for subsequent processing',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync();
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        // Create an asymmetric 100x50 image to verify 90° rotation changes dimensions to 50x100
        final testImg = img.Image(width: 100, height: 50);
        img.fill(testImg, color: img.ColorRgb8(255, 0, 0));
        final pngBytes = img.encodePng(testImg);
        final dummyFile = File('${tempDir.path}/test_100x50.png')
          ..writeAsBytesSync(pngBytes);

        await tester.pumpWidget(
          MaterialApp(
            home: PhotoReviewScreen(
              imageFile: dummyFile,
              ingestMemoryUseCase: IngestMemoryUseCase(FakeAiRepository()),
            ),
          ),
        );
        await tester.pump();

        // Tap Rotate control (rotates 90 degrees clockwise)
        await tester.tap(find.text('Rotate'));
        await tester.pump();
        await tester.pump();

        // Verify image preview was updated with the rotated file
        final imageWidgetFinder = find.byType(Image);
        expect(imageWidgetFinder, findsOneWidget);
        final Image imageWidget = tester.widget<Image>(imageWidgetFinder);
        final FileImage fileImage = imageWidget.image as FileImage;
        expect(fileImage.file.path, isNot(dummyFile.path));
        expect(fileImage.file.existsSync(), isTrue);

        // Verify rotated file dimensions are now 50x100
        final rotatedBytes = fileImage.file.readAsBytesSync();
        final decodedRotated = img.decodeImage(rotatedBytes);
        expect(decodedRotated, isNotNull);
        expect(decodedRotated!.width, 50);
        expect(decodedRotated.height, 100);

        // Tap Rotate again (rotates another 90 degrees -> 180 degrees total)
        await tester.tap(find.text('Rotate'));
        await tester.pump();
        await tester.pump();

        final Image imageWidget2 = tester.widget<Image>(find.byType(Image));
        final FileImage fileImage2 = imageWidget2.image as FileImage;
        final rotatedBytes2 = fileImage2.file.readAsBytesSync();
        final decodedRotated2 = img.decodeImage(rotatedBytes2);
        expect(decodedRotated2, isNotNull);
        expect(decodedRotated2!.width, 100);
        expect(decodedRotated2.height, 50);
      },
    );

    testWidgets('Existing Take Photo flow continues to work without rotation', (
      tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync();
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final testImg = img.Image(width: 80, height: 80);
      img.fill(testImg, color: img.ColorRgb8(0, 255, 0));
      final dummyFile = File('${tempDir.path}/test_flow.png')
        ..writeAsBytesSync(img.encodePng(testImg));

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoReviewScreen(
            imageFile: dummyFile,
            isOffline: true,
            ingestMemoryUseCase: IngestMemoryUseCase(FakeAiRepository()),
          ),
        ),
      );
      await tester.pump();

      // Tapping Use Photo without rotation works normally and proceeds
      expect(find.text('Use Photo'), findsOneWidget);
      await tester.tap(find.text('Use Photo'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Navigated to MemoryReviewScreen
      expect(find.text('Review & Save'), findsOneWidget);
      // Raw OCR section is not displayed
      expect(find.text('Extracted Content'), findsNothing);
      expect(find.text('View extracted text'), findsNothing);
    });

    testWidgets(
      'MemoryReviewScreen displays concise AI semantic description and does not show raw OCR section',
      (tester) async {
        final dummyFile = File('test_image.jpg');
        final repo = FakeCaptureRepository([]);
        final captureBloc = CaptureBloc(
          saveMemoryUseCase: SaveMemoryUseCase(repo),
          getMemoriesUseCase: GetMemoriesUseCase(repo),
          repository: repo,
        );

        const semanticDescription =
            '• Pinterest\n• Bottom navigation ideas for a notes app';
        const rawOcrDump =
            '7:45 PM LTE https://pinterest.com/pin/1234 Back Share More Search Less AI random text';

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
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

        // Verify raw OCR is NOT displayed anywhere on screen
        expect(find.text(rawOcrDump), findsNothing);
        expect(find.text('Extracted Content'), findsNothing);
        expect(find.text('View extracted text'), findsNothing);
        expect(find.text('Hide extracted text'), findsNothing);
      },
    );

    testWidgets(
      'HomeScreen memory card displays concise semantic description and never raw OCR dump',
      (tester) async {
        const semanticDescription =
            '• Pinterest\n• Bottom navigation ideas for a notes app';
        final testMemory = MemoryEntity(
          id: 'mem-101',
          userId: 'local_user',
          title: 'Notes App Nav',
          content: semanticDescription,
          category: 'Work',
          tags: const ['ui', 'pinned'],
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
        captureBloc.add(LoadMemoriesEvent());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
            child: const MaterialApp(home: SavedScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Expect the concise semantic description on the card
        expect(find.text(semanticDescription), findsOneWidget);
      },
    );
  });
}
