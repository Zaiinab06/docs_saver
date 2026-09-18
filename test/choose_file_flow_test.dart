import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/network/network_checker.dart';
import 'package:second_brain/core/services/file_picker_service.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository_impl.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/photo_review_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';

class FakeChooseFileAiRepository implements AiRepository {
  final String title;
  final String summary;
  final String category;
  final List<String> tags;
  final String? documentText;
  final String aiStatus;
  bool shouldFail;

  FakeChooseFileAiRepository({
    this.title = 'AI Organized Title',
    this.summary = '• Summary point 1\n• Summary point 2',
    this.category = 'Work',
    this.tags = const ['document', 'work'],
    this.documentText,
    this.aiStatus = 'processed',
    this.shouldFail = false,
  });

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
  }) async {
    if (shouldFail) {
      throw Exception('Remote AI service unavailable');
    }
    return AiIngestionResult(
      title: title,
      summary: summary,
      category: category,
      tags: tags,
      aiStatus: aiStatus,
      documentText: documentText,
    );
  }
}

class FakeFilePickerService implements FilePickerService {
  PlatformFile? pickedFile;
  bool wasCalled = false;
  List<String>? allowedExtensionsPassed;

  @override
  Future<PlatformFile?> pickFile({
    List<String>? allowedExtensions,
  }) async {
    wasCalled = true;
    allowedExtensionsPassed = allowedExtensions;
    return pickedFile;
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
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index >= 0) {
      memories[index] = memory;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Choose File Feature & Document Architecture Tests', () {
    late Directory tempDir;
    late List<MemoryEntity> memoryStore;
    late FakeCaptureRepository captureRepository;
    late FakeChooseFileAiRepository aiRepository;
    late IngestMemoryUseCase ingestMemoryUseCase;
    late CaptureBloc captureBloc;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('choose_file_test_');
      memoryStore = [];
      captureRepository = FakeCaptureRepository(memoryStore);
      aiRepository = FakeChooseFileAiRepository();
      ingestMemoryUseCase = IngestMemoryUseCase(aiRepository);
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(captureRepository),
        getMemoriesUseCase: GetMemoriesUseCase(captureRepository),
        repository: captureRepository,
      );

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return tempDir.path;
      });
      NetworkChecker.testOverride = false;
    });

    tearDown(() {
      NetworkChecker.testOverride = null;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      captureBloc.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget createTestApp({
      Widget? child,
      FilePickerService? filePickerService,
    }) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<CaptureBloc>.value(value: captureBloc),
        ],
        child: MaterialApp(
          home: child ??
              HomeScreen(
                filePickerService: filePickerService,
                ingestMemoryUseCase: ingestMemoryUseCase,
              ),
        ),
      );
    }

    test('1. MIME Type Resolution maps all supported extensions accurately', () {
      expect(CaptureRepositoryImpl.resolveMimeType('.pdf'), 'application/pdf');
      expect(CaptureRepositoryImpl.resolveMimeType('pdf'), 'application/pdf');
      expect(CaptureRepositoryImpl.resolveMimeType('.txt'), 'text/plain');
      expect(CaptureRepositoryImpl.resolveMimeType('.md'), 'text/plain');
      expect(CaptureRepositoryImpl.resolveMimeType('.csv'), 'text/plain');
      expect(CaptureRepositoryImpl.resolveMimeType('.json'), 'application/json');
      expect(CaptureRepositoryImpl.resolveMimeType('.png'), 'image/png');
      expect(CaptureRepositoryImpl.resolveMimeType('.jpg'), 'image/jpeg');
      expect(CaptureRepositoryImpl.resolveMimeType('.jpeg'), 'image/jpeg');
      expect(CaptureRepositoryImpl.resolveMimeType('.webp'), 'image/webp');
      expect(CaptureRepositoryImpl.resolveMimeType('.m4a'), 'audio/m4a');
      expect(CaptureRepositoryImpl.resolveMimeType('.mp3'), 'audio/mp3');
      expect(CaptureRepositoryImpl.resolveMimeType('.unknown'), 'application/octet-stream');
    });

    testWidgets('2. Choose File cancel returns cleanly without error or state change',
        (tester) async {
      final fakePicker = FakeFilePickerService()..pickedFile = null;

      await tester.pumpWidget(
        createTestApp(filePickerService: fakePicker),
      );
      await tester.pumpAndSettle();

      // Open capture bottom sheet directly
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      // Tap Choose File
      expect(find.text('Choose File'), findsOneWidget);
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      expect(fakePicker.wasCalled, isTrue);
      expect(fakePicker.allowedExtensionsPassed, contains('pdf'));
      expect(fakePicker.allowedExtensionsPassed, contains('txt'));
      expect(memoryStore.isEmpty, isTrue);
    });

    testWidgets('3. 15 MB file size limit triggers floating warning snackbar',
        (tester) async {
      final largeFile = File('${tempDir.path}/large_manual.pdf')
        ..writeAsBytesSync([1, 2, 3]);

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'large_manual.pdf',
          path: largeFile.path,
          size: 16 * 1024 * 1024, // 16 MB > 15 MB
        );

      await tester.pumpWidget(
        createTestApp(filePickerService: fakePicker),
      );
      await tester.pumpAndSettle();

      // Open capture sheet
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      // Tap Choose File
      final chooseFileOption = find.text('Choose File');
      expect(chooseFileOption, findsOneWidget);
      await tester.tap(chooseFileOption);
      await tester.pumpAndSettle();

      // Expect size limit snackbar
      expect(find.textContaining('15 MB'), findsOneWidget);
      expect(memoryStore.isEmpty, isTrue);
    });

    testWidgets('4. Unsupported extension triggers rejection snackbar',
        (tester) async {
      final unsupportedFile = File('${tempDir.path}/archive.zip')
        ..writeAsBytesSync([1, 2, 3]);

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'archive.zip',
          path: unsupportedFile.path,
          size: 1024,
        );

      await tester.pumpWidget(
        createTestApp(filePickerService: fakePicker),
      );
      await tester.pumpAndSettle();

      // Open capture sheet
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      // Tap Choose File
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Expect unsupported format snackbar
      expect(find.textContaining('Unsupported file format'), findsOneWidget);
      expect(memoryStore.isEmpty, isTrue);
    });

    testWidgets('5. Text file reading preserves verbatim contents and initial title',
        (tester) async {
      const originalText = 'System architecture specification:\n1. Microservices\n2. Event sourcing\n3. CQRS';
      final textFile = File('${tempDir.path}/architecture.md')
        ..writeAsStringSync(originalText);

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'architecture.md',
          path: textFile.path,
          size: textFile.lengthSync(),
        );

      await tester.pumpWidget(
        createTestApp(filePickerService: fakePicker),
      );
      await tester.pumpAndSettle();

      // Open capture sheet -> Choose File
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Should navigate to MemoryReviewScreen
      expect(find.byType(MemoryReviewScreen), findsOneWidget);

      // Title should contain filename
      expect(find.text('architecture.md'), findsWidgets);

      // Should render document card preview, NEVER an Image widget
      expect(find.text('MD'), findsOneWidget);
      expect(find.byIcon(Icons.description_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      // Extracted text card shows 'View extracted text'
      expect(find.text('View extracted text'), findsOneWidget);
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();

      // Verbatim text should now be visible
      expect(find.text(originalText), findsOneWidget);

      // Save memory and verify exact content is preserved in repository
      await tester.tap(find.text('Save Memory'));
      await tester.pumpAndSettle();

      expect(memoryStore.length, 1);
      expect(memoryStore.first.title, 'architecture.md');
      expect(memoryStore.first.content, originalText);
      expect(memoryStore.first.tags, contains('document'));
    });

    testWidgets('6. MemoryReviewScreen document card renders filename, extension, and file size',
        (tester) async {
      final sampleDoc = File('${tempDir.path}/report.pdf')
        ..writeAsBytesSync(List.filled(2048, 65)); // 2 KB

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: MaterialApp(
            home: MemoryReviewScreen(
              initialTitle: 'Quarterly Report',
              initialContent: '',
              initialCategory: 'Work',
              initialTags: const ['pdf', 'report'],
              aiStatus: 'pending',
              createdAt: DateTime.now(),
              documentFile: sampleDoc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check document preview card
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.textContaining('KB'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
      // Ensure no broken Image widget is instantiated for the PDF
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('7. Offline PDF memory preserves file and sets truthful pending ai_status',
        (tester) async {
      final samplePdf = File('${tempDir.path}/contract.pdf')
        ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]); // %PDF

      final now = DateTime.now();
      final memory = MemoryEntity(
        id: 'doc-123',
        userId: 'user-1',
        title: 'contract.pdf',
        content: '', // Empty because offline extraction did not happen
        category: 'Work',
        tags: const ['document', 'pdf'],
        mediaUrl: samplePdf.path,
        aiStatus: 'pending',
        isSynced: false,
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await captureRepository.saveMemory(memory);

      await tester.pumpWidget(
        createTestApp(
          child: MemoryDetailScreen(
            memoryId: memory.id,
            initialMemory: memory,
          ),
        ),
      );
      // Use pump() with finite duration because pending state animates CircularProgressIndicator
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Header title
      expect(find.text('contract.pdf'), findsWidgets);

      // Truthful offline pending badge
      expect(
        find.text('Saved offline — will organize when online'),
        findsOneWidget,
      );

      // Document detail card with Open File action
      expect(find.text('Open File'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

      // Should NOT show extracted text section since content is empty
      expect(find.text('Document Content'), findsNothing);
    });

    testWidgets('8. Failed PDF extraction displays truthful failure badge and preserves file',
        (tester) async {
      final samplePdf = File('${tempDir.path}/scanned_receipt.pdf')
        ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);

      final now = DateTime.now();
      final memory = MemoryEntity(
        id: 'doc-failed',
        userId: 'user-1',
        title: 'scanned_receipt.pdf',
        content: '',
        category: 'Finance',
        tags: const ['document', 'pdf'],
        mediaUrl: samplePdf.path,
        aiStatus: 'failed',
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await tester.pumpWidget(
        createTestApp(
          child: MemoryDetailScreen(
            memoryId: memory.id,
            initialMemory: memory,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Truthful failure badge (rendered in badge and banner)
      expect(find.text('Extraction failed — file preserved'), findsWidgets);

      // Open File button still available to inspect preserved file
      expect(find.text('Open File'), findsOneWidget);
    });

    testWidgets('9. Processed document memory displays extracted Document Content and AI Organized badge',
        (tester) async {
      const extractedDocumentContent = 'Invoice #4092\nVendor: Acme Corp\nAmount: \$350.00';
      final samplePdf = File('${tempDir.path}/invoice.pdf')
        ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);

      final now = DateTime.now();
      final memory = MemoryEntity(
        id: 'doc-processed',
        userId: 'user-1',
        title: 'Acme Corp Invoice',
        content: extractedDocumentContent,
        category: 'Finance',
        tags: const ['document', 'pdf', 'invoice'],
        mediaUrl: samplePdf.path,
        aiStatus: 'processed',
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await tester.pumpWidget(
        createTestApp(
          child: MemoryDetailScreen(
            memoryId: memory.id,
            initialMemory: memory,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AI Organized badge
      expect(find.text('AI Organized'), findsOneWidget);

      // Extracted Document Content card
      expect(find.text('Document Content'), findsOneWidget);
      expect(find.text('Text extracted from document'), findsOneWidget);

      // Tap to expand document content
      await tester.tap(find.text('Document Content'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invoice #4092'), findsOneWidget);

      // Document detail card
      expect(find.text('Open File'), findsOneWidget);
    });

    testWidgets('10. Image files selected via Choose File route directly to PhotoReviewScreen',
        (tester) async {
      final transparentPng = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ];
      final imageFile = File('${tempDir.path}/picked_photo.png')
        ..writeAsBytesSync(transparentPng);

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'picked_photo.png',
          path: imageFile.path,
          size: imageFile.lengthSync(),
        );

      await tester.pumpWidget(
        createTestApp(filePickerService: fakePicker),
      );
      await tester.pumpAndSettle();

      // Open capture sheet -> Choose File
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Should route directly to PhotoReviewScreen (existing OCR pipeline)
      expect(find.byType(PhotoReviewScreen), findsOneWidget);
    });

    testWidgets('11. Successful online PDF extraction sets AI Organized and displays extracted text and AI title',
        (tester) async {
      NetworkChecker.testOverride = true;

      final pdfFile = File('${tempDir.path}/nutrition_guide.pdf')
        ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46, 0x31]); // %PDF1

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'nutrition_guide.pdf',
          path: pdfFile.path,
          size: pdfFile.lengthSync(),
        );

      final customAiRepository = FakeChooseFileAiRepository(
        title: 'Nutritional Guidelines Reference',
        summary: '• Comprehensive macronutrient breakdown and daily allowances.',
        category: 'Health & Fitness',
        tags: const ['document', 'pdf', 'nutrition', 'health'],
        documentText: 'Nutritional Guidelines 2026\nMacronutrients:\n- Protein: 1.6g/kg\n- Carbs: 3g/kg',
        aiStatus: 'processed',
      );

      final customIngestUseCase = IngestMemoryUseCase(customAiRepository);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: MaterialApp(
            home: HomeScreen(
              filePickerService: fakePicker,
              ingestMemoryUseCase: customIngestUseCase,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open capture sheet -> Choose File
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Should be on MemoryReviewScreen
      expect(find.byType(MemoryReviewScreen), findsOneWidget);

      // AI Organized badge must be present
      expect(find.text('AI Organized'), findsOneWidget);

      // Semantic AI title must be used
      expect(find.text('Nutritional Guidelines Reference'), findsOneWidget);

      // AI Summary must be displayed
      expect(find.text('AI Summary'), findsOneWidget);
      expect(
        find.text('• Comprehensive macronutrient breakdown and daily allowances.'),
        findsOneWidget,
      );

      // Document Content section with extracted text
      expect(find.text('View extracted text'), findsOneWidget);
      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nutritional Guidelines 2026'), findsOneWidget);
    });

    testWidgets('12. Failed/empty PDF extraction preserves picked filename, clears summary, and sets failed status (never AI Organized)',
        (tester) async {
      NetworkChecker.testOverride = true;

      final pdfFile = File('${tempDir.path}/IBW Table.pdf')
        ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]); // %PDF

      final fakePicker = FakeFilePickerService()
        ..pickedFile = PlatformFile(
          name: 'IBW Table.pdf',
          path: pdfFile.path,
          size: pdfFile.lengthSync(),
        );

      // Simulate the backend returning empty documentText and a misleading visual-analysis title/summary
      final customAiRepository = FakeChooseFileAiRepository(
        title: 'Visual analysis context not available',
        summary: 'No visual content or OCR text was provided in the input.',
        category: 'Personal',
        tags: const ['document', 'pdf', 'personal'],
        documentText: '', // Empty document extraction!
        aiStatus: 'failed',
      );

      final customIngestUseCase = IngestMemoryUseCase(customAiRepository);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: MaterialApp(
            home: HomeScreen(
              filePickerService: fakePicker,
              ingestMemoryUseCase: customIngestUseCase,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open capture sheet -> Choose File
      tester.state<HomeScreenState>(find.byType(HomeScreen)).openCaptureBottomSheet();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      // Should be on MemoryReviewScreen
      expect(find.byType(MemoryReviewScreen), findsOneWidget);

      // MUST NOT be marked "AI Organized"
      expect(find.text('AI Organized'), findsNothing);

      // MUST truthfully show "AI Analysis Failed"
      expect(find.text('AI Analysis Failed'), findsOneWidget);

      // MUST preserve original picked filename, NEVER the misleading visual analysis title
      expect(find.text('IBW Table.pdf'), findsWidgets);
      expect(find.text('Visual analysis context not available'), findsNothing);

      // MUST NOT display any hallucinated AI summary
      expect(find.text('AI Summary'), findsNothing);
      expect(find.text('No visual content or OCR text was provided in the input.'), findsNothing);
    });
  });
}
