import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/photo_review_screen.dart';
import 'package:second_brain/features/navigation/presentation/screens/main_navigation_shell.dart';

class FakeDocumentAiRepository implements AiRepository {
  final String title;
  final String summary;
  final String category;
  final List<String> tags;

  const FakeDocumentAiRepository({
    this.title = 'Quarterly Financial Invoice',
    this.summary = '• Invoice total: \$1,250.00\n• Payment due in 30 days',
    this.category = 'Finance',
    this.tags = const ['invoice', 'finance'],
  });

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
  }) async {
    return AiIngestionResult(
      title: title,
      summary: summary,
      category: category,
      tags: tags,
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

  group('Scan Document Flow Verification Tests', () {
    late Directory tempDir;
    late File dummyDocumentFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      final transparentPng = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ];
      dummyDocumentFile = File('${tempDir.path}/scanned_document.png')
        ..writeAsBytesSync(transparentPng);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('PhotoReviewScreen in document mode displays Review Document and Use Document',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoReviewScreen(
            imageFile: dummyDocumentFile,
            isDocumentScan: true,
            ingestMemoryUseCase: IngestMemoryUseCase(const FakeDocumentAiRepository()),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify AppBar title says "Review Document"
      expect(find.text('Review Document'), findsOneWidget);
      expect(find.text('Review Photo'), findsNothing);

      // 2. Verify primary button says "Use Document"
      expect(find.text('Use Document'), findsOneWidget);
      expect(find.text('Use Photo'), findsNothing);

      // 3. Verify Retake button is present
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('MemoryReviewScreen correctly renders scanned document data with #document tag and category',
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
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyDocumentFile,
              initialTitle: 'Quarterly Financial Invoice',
              initialContent: 'Invoice details and amount',
              initialSummary: '• Invoice total: \$1,250.00\n• Payment due in 30 days',
              rawOcrText: 'INVOICE #9823 Total: \$1250.00 Due: 30 days',
              initialCategory: 'Work',
              initialTags: const ['document', 'invoice'],
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 14, 1, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Review & Save screen renders document title
      expect(find.text('Review & Save'), findsOneWidget);
      expect(find.text('Quarterly Financial Invoice'), findsOneWidget);

      // Verified: Tag '#document' is included for scanned documents
      expect(find.text('#document'), findsOneWidget);
      expect(find.text('#invoice'), findsOneWidget);

      // Verified: Category detected by AI is displayed
      expect(find.text('Work'), findsAtLeastNWidgets(1));

      // Verified: Extracted content collapsible card works
      expect(find.text('Extracted Content'), findsOneWidget);
      expect(find.text('INVOICE #9823 Total: \$1250.00 Due: 30 days'), findsNothing);
      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();
      expect(find.text('INVOICE #9823 Total: \$1250.00 Due: 30 days'), findsOneWidget);
    });

    testWidgets('HomeScreen Scan Document option safely handles user cancellation',
        (tester) async {
      // Mock cunning_document_scanner method channel returning null (user cancelled)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('cunning_document_scanner'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getPictures') {
            return null; // User cancelled
          }
          return null;
        },
      );

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
            home: MainNavigationShell(userName: 'Noor'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open + bottom sheet
      await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
      await tester.pumpAndSettle();

      // Tap "Scan Document"
      expect(find.text('Scan Document'), findsOneWidget);
      await tester.tap(find.text('Scan Document'));
      await tester.pumpAndSettle();

      // Verified: Returns safely to Home without errors or crash
      expect(tester.takeException(), isNull);
      expect(find.text('Scan Document capture flow will be available soon.'), findsNothing);
    });

    testWidgets('HomeScreen Scan Document option gracefully handles scanner exception',
        (tester) async {
      // Mock cunning_document_scanner method channel throwing permission exception
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('cunning_document_scanner'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getPictures') {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'Camera permission denied',
            );
          }
          return null;
        },
      );

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
            home: MainNavigationShell(userName: 'Noor'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open + bottom sheet
      await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
      await tester.pumpAndSettle();

      // Tap "Scan Document"
      await tester.tap(find.text('Scan Document'));
      await tester.pumpAndSettle();

      // Verified: User-friendly error message is displayed
      expect(
        find.text('Camera permission denied. Please enable camera access in Settings.'),
        findsOneWidget,
      );
    });
  });
}
