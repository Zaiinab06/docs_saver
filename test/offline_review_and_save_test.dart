import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/network/network_checker.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';

class FakeAiRepository implements AiRepository {
  bool shouldFail = false;
  Duration delay = Duration.zero;
  AiIngestionResult? customResult;

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
  }) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (shouldFail) {
      throw Exception('Simulated AI failure');
    }
    return customResult ??
        const AiIngestionResult(
          title: 'Project Roadmap Notes',
          category: 'Work',
          tags: ['roadmap', 'strategy'],
          summary: '• Key milestone deliverables\n• Target launch in Q4',
          aiStatus: 'processed',
        );
  }
}

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> savedMemories = [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => savedMemories;

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    savedMemories.add(memory);
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline Review & Save Screen Tests', () {
    late Directory tempDir;
    late File dummyImage;
    late FakeCaptureRepository repo;
    late CaptureBloc captureBloc;
    late FakeAiRepository fakeAiRepo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      dummyImage = File('${tempDir.path}/test_image.jpg')..writeAsBytesSync([1, 2, 3]);
      repo = FakeCaptureRepository();
      fakeAiRepo = FakeAiRepository();
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return tempDir.path;
      });
    });

    tearDown(() {
      NetworkChecker.testOverride = null;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget createTestWidget({
      required bool isOffline,
      String aiStatus = 'pending',
      String initialTitle = '',
      String rawOcrText = 'Local OCR text recognized on device',
      IngestMemoryUseCase? useCase,
    }) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<CaptureBloc>.value(value: captureBloc),
        ],
        child: MaterialApp(
          home: MemoryReviewScreen(
            imageFile: dummyImage,
            initialTitle: initialTitle,
            initialContent: '',
            rawOcrText: rawOcrText,
            initialCategory: 'Personal',
            initialTags: const [],
            aiStatus: aiStatus,
            createdAt: DateTime(2026, 9, 14, 13, 55),
            isOffline: isOffline,
            ingestMemoryUseCase: useCase ?? IngestMemoryUseCase(fakeAiRepo),
          ),
        ),
      );
    }

    testWidgets('Status row does not overflow on narrow screens (320px width)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(isOffline: false, aiStatus: 'pending'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('AI Ingestion Pending'), findsOneWidget);
      expect(find.text('Analyze with AI'), findsOneWidget);
      expect(find.text('Sep 14, 2026 • 1:55 PM'), findsOneWidget);
    });

    testWidgets('Status row does not overflow on narrow screens when offline',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(isOffline: true, aiStatus: 'pending'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Analyze with AI'), findsNothing);
      expect(find.text('Sep 14, 2026 • 1:55 PM'), findsOneWidget);
    });

    testWidgets('Offline state: shows "You\'re offline" with yellow dot and hides analyze action',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isOffline: true, aiStatus: 'pending'));
      await tester.pumpAndSettle();

      // "Analyze with AI" must NOT be present
      expect(find.text('Analyze with AI'), findsNothing);

      // Shows exact offline text "You're offline"
      expect(find.text("You're offline"), findsOneWidget);

      // Yellow status dot is rendered beside it
      final yellowDotFinder = find.byWidgetPredicate((widget) {
        return widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == const Color(0xFFF59E0B) &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle;
      });
      expect(yellowDotFinder, findsOneWidget);

      // Extracted OCR text is preserved
      expect(find.text('Extracted Content'), findsOneWidget);
      expect(find.text('View extracted text'), findsOneWidget);

      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();
      expect(find.text('Local OCR text recognized on device'), findsOneWidget);
    });

    testWidgets('Online restored: reveals "Analyze with AI" automatically without scroll or pull',
        (tester) async {
      // Start offline
      NetworkChecker.testOverride = false;
      await tester.pumpWidget(createTestWidget(isOffline: true, aiStatus: 'pending'));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Analyze with AI'), findsNothing);

      // Network becomes available again
      NetworkChecker.testOverride = true;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Status updates immediately to show device is online
      expect(find.text('AI Ingestion Pending'), findsOneWidget);
      expect(find.text("You're offline"), findsNothing);

      // Clearly tappable "Analyze with AI" action appears without pull-to-refresh
      expect(find.text('Analyze with AI'), findsOneWidget);
    });

    testWidgets('Analyze with AI: updates title, category, tags, and summary, replacing action with processed state',
        (tester) async {
      NetworkChecker.testOverride = true;
      fakeAiRepo.delay = const Duration(milliseconds: 50);

      await tester.pumpWidget(createTestWidget(
        isOffline: false,
        aiStatus: 'pending',
        initialTitle: '',
        rawOcrText: 'Roadmap notes for Q4 launch',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Analyze with AI'), findsOneWidget);
      expect(find.text('AI Summary'), findsNothing);

      // Tap Analyze with AI
      await tester.tap(find.text('Analyze with AI'));
      await tester.pump();

      // Shows loading state while analyzing
      expect(find.text('Analyzing...'), findsOneWidget);

      // Let AI analysis complete
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      // Title updated with real AI result
      expect(find.text('Project Roadmap Notes'), findsOneWidget);

      // Category updated to Work
      expect(find.text('Work'), findsWidgets);

      // Tags updated
      expect(find.text('#roadmap'), findsOneWidget);
      expect(find.text('#strategy'), findsOneWidget);

      // Concise semantic summary card is displayed (max 1-2 points)
      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text('• Key milestone deliverables\n• Target launch in Q4'), findsOneWidget);

      // Action replaced with successful processed state
      expect(find.text('AI Organized'), findsOneWidget);
      expect(find.text('Analyze with AI'), findsNothing);
    });

    testWidgets('Analyze with AI: preserves user-edited title and does not overwrite it',
        (tester) async {
      NetworkChecker.testOverride = true;
      fakeAiRepo.delay = Duration.zero;

      await tester.pumpWidget(createTestWidget(
        isOffline: false,
        aiStatus: 'pending',
        initialTitle: '',
        rawOcrText: 'Meeting action items',
      ));
      await tester.pumpAndSettle();

      // User manually enters a custom title before tapping Analyze
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'My Custom User Title');
      await tester.pumpAndSettle();

      expect(find.text('My Custom User Title'), findsOneWidget);

      // Tap Analyze with AI
      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      // AI updates category, tags, and summary, but keeps user's custom title
      expect(find.text('My Custom User Title'), findsOneWidget);
      expect(find.text('Project Roadmap Notes'), findsNothing);
      expect(find.text('#roadmap'), findsOneWidget);
    });

    testWidgets('Analyze with AI: shows clear error state and retry action when AI analysis fails',
        (tester) async {
      fakeAiRepo.shouldFail = true;
      fakeAiRepo.delay = Duration.zero;
      NetworkChecker.testOverride = true;

      await tester.pumpWidget(createTestWidget(
        isOffline: false,
        aiStatus: 'pending',
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      // Error state is displayed
      expect(find.text('AI Analysis Failed'), findsOneWidget);
      expect(find.text('Retry AI'), findsOneWidget);

      // Now fix AI and tap Retry AI
      fakeAiRepo.shouldFail = false;
      await tester.tap(find.text('Retry AI'));
      await tester.pumpAndSettle();

      // Re-analysis succeeds
      expect(find.text('AI Organized'), findsOneWidget);
      expect(find.text('Retry AI'), findsNothing);
    });

    testWidgets('Offline state: saves memory locally without fake AI data',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        isOffline: true,
        aiStatus: 'pending',
        initialTitle: '',
        rawOcrText: 'My receipt: Coffee \$4.50',
      ));
      await tester.pumpAndSettle();

      // Scroll to and tap Save Memory
      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Memory is saved into local repository
      expect(repo.savedMemories.length, 1);
      final saved = repo.savedMemories.first;

      // Verified: zero fake AI title or tags injected
      expect(saved.aiStatus, 'pending');
      expect(saved.tags, isEmpty);
      expect(saved.title, startsWith('Captured Memory'));
    });
  });
}
