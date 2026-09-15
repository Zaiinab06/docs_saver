import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/core/utils/link_metadata_extractor.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';

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
}

class FakeAiRepository implements AiRepository {
  final String title;
  final String summary;
  final String category;
  final List<String> tags;

  const FakeAiRepository({
    this.title = 'Riverpod State Management Tutorial',
    this.summary = '• Riverpod architecture and state providers\n• Reactive UI updates with Flutter',
    this.category = AppStrings.categoryStudy,
    this.tags = const ['riverpod', 'flutter', 'state-management', 'youtube'],
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Link Provider Detection Tests', () {
    test('detects standard youtube.com/watch?v=... URL', () {
      final uri = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('detects youtube.com without www and with extra query params', () {
      final uri = Uri.parse('https://youtube.com/watch?v=dQw4w9WgXcQ&t=120&feature=shared');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('detects m.youtube.com mobile URL', () {
      final uri = Uri.parse('https://m.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('detects youtu.be short URL', () {
      final uri = Uri.parse('https://youtu.be/dQw4w9WgXcQ?si=abcdef123');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('detects YouTube Shorts URL', () {
      final uri = Uri.parse('https://www.youtube.com/shorts/dQw4w9WgXcQ');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('detects YouTube embed URL', () {
      final uri = Uri.parse('https://www.youtube.com/embed/dQw4w9WgXcQ');
      expect(LinkProviderDetector.detect(uri), LinkProvider.youtube);
      expect(LinkProviderDetector.extractYouTubeVideoId(uri), 'dQw4w9WgXcQ');
    });

    test('non-YouTube URL remains genericWeb', () {
      expect(
        LinkProviderDetector.detect(Uri.parse('https://flutter.dev/docs')),
        LinkProvider.genericWeb,
      );
      expect(
        LinkProviderDetector.detect(Uri.parse('https://news.ycombinator.com')),
        LinkProvider.genericWeb,
      );
    });

    test('provider detection does not misclassify URLs containing youtube in path or subdomain', () {
      expect(
        LinkProviderDetector.detect(Uri.parse('https://myblog.com/how-to-use-youtube')),
        LinkProvider.genericWeb,
      );
      expect(
        LinkProviderDetector.detect(Uri.parse('https://youtube.com.scam.net/watch?v=dQw4w9WgXcQ')),
        LinkProvider.genericWeb,
      );
      expect(
        LinkProviderDetector.detect(Uri.parse('https://fake-youtube.org/watch?v=dQw4w9WgXcQ')),
        LinkProvider.genericWeb,
      );
    });

    test('canonical YouTube URL generator produces standard watch URL', () {
      expect(
        LinkProviderDetector.toCanonicalYouTubeUrl('dQw4w9WgXcQ'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        LinkProviderDetector.toCanonicalYouTubeUrl('invalid_short'),
        isNull,
      );
    });
  });

  group('YouTube Extractor Real Metadata and Fallback Tests', () {
    test('maps real YouTube oEmbed metadata into RichLinkContent', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'www.youtube.com' &&
                options.uri.path == '/oembed') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'title': 'Flutter Riverpod 2.0 Full Tutorial',
                    'author_name': 'Code With Andrea',
                    'author_url': 'https://www.youtube.com/@codewithandrea',
                    'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
                    'provider_name': 'YouTube',
                  },
                ),
              );
            }
            if (options.uri.path == '/watch') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:description" content="Complete guide to Flutter state management using Riverpod 2.0 and code generation." />
</head>
<body></body>
</html>
''',
                ),
              );
            }
            return handler.reject(
              DioException(
                requestOptions: options,
                error: 'Not found',
              ),
            );
          },
        ),
      );

      final extractor = YouTubeLinkExtractor(dio: dio);
      final rich = await extractor.extract(
        Uri.parse('https://youtu.be/dQw4w9WgXcQ'),
      );

      expect(rich.provider, LinkProvider.youtube);
      expect(rich.canonicalUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(rich.title, 'Flutter Riverpod 2.0 Full Tutorial');
      expect(rich.creator, 'Code With Andrea');
      expect(rich.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(rich.description, contains('Riverpod 2.0 and code generation'));
      expect(rich.readableContent, contains('Channel: Code With Andrea'));
      expect(rich.readableContent, contains('Description:'));
      expect(rich.siteName, 'YouTube');
    });

    test('missing transcript leaves transcript null without faking data', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/oembed') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'title': 'Instrumental Beats',
                    'author_name': 'Lofi Girl',
                    'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
                  },
                ),
              );
            }
            if (options.uri.path.contains('timedtext')) {
              // Video has no captions
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 404,
                  ),
                ),
              );
            }
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: '<html></html>',
              ),
            );
          },
        ),
      );

      final extractor = YouTubeLinkExtractor(dio: dio);
      final rich = await extractor.extract(
        Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );

      expect(rich.title, 'Instrumental Beats');
      expect(rich.creator, 'Lofi Girl');
      expect(rich.transcript, isNull);
    });

    test('parses public closed captions when timedtext is available', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/oembed') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'title': 'State Management Lecture',
                    'author_name': 'Dr. Tech',
                  },
                ),
              );
            }
            if (options.uri.path.contains('timedtext')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: '''
<?xml version="1.0" encoding="utf-8" ?>
<transcript>
  <text start="0.0" dur="2.5">Welcome to this lecture on state management.</text>
  <text start="2.5" dur="3.0">Today we discuss BLoC, Riverpod, and Provider.</text>
</transcript>
''',
                ),
              );
            }
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: '<html></html>'),
            );
          },
        ),
      );

      final extractor = YouTubeLinkExtractor(dio: dio);
      final rich = await extractor.extract(
        Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );

      expect(rich.transcript, isNotNull);
      expect(rich.transcript, contains('Welcome to this lecture'));
      expect(rich.transcript, contains('BLoC, Riverpod, and Provider'));
      expect(rich.readableContent, contains('Transcript:'));
    });

    test('network failure falls back safely without throwing or losing URL', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                error: 'Network connection refused',
              ),
            );
          },
        ),
      );

      final extractor = YouTubeLinkExtractor(dio: dio);
      final rich = await extractor.extract(
        Uri.parse('https://youtu.be/dQw4w9WgXcQ'),
      );

      expect(rich.provider, LinkProvider.youtube);
      expect(rich.canonicalUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(rich.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(rich.siteName, 'YouTube');
      expect(rich.title, isNull);
    });
  });

  group('LinkMetadataExtractor Orchestration Tests', () {
    test('routes YouTube URLs through YouTubeLinkExtractor', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/oembed') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'title': 'How to Build Apps Fast',
                    'author_name': 'Tech Channel',
                    'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
                  },
                ),
              );
            }
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: '<html></html>'),
            );
          },
        ),
      );

      final extractor = LinkMetadataExtractor(dio: dio);
      final metadata = await extractor.extract('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

      expect(metadata.provider, LinkProvider.youtube);
      expect(metadata.title, 'How to Build Apps Fast');
      expect(metadata.creator, 'Tech Channel');
      expect(metadata.siteName, 'YouTube');
      expect(metadata.imageUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });

    test('routes standard blog URLs through generic HTML DOM parser', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: '''
<!DOCTYPE html>
<html>
<head>
  <title>Clean Architecture Guide</title>
  <meta property="og:title" content="Clean Architecture Guide" />
  <meta property="og:description" content="Detailed guide on data and presentation layer segregation." />
</head>
<body>
  <article>
    <h1>Clean Architecture Overview</h1>
    <p>Software engineering principles dictate clear separation of concerns between domain logic and presentation layers.</p>
    <p>This design facilitates unit testing, refactoring, and long-term codebase maintenance without UI framework coupling.</p>
    <p>Developers benefit from isolated business rules that run independently of external databases, APIs, or user interfaces.</p>
    <p>Adhering to these patterns ensures optimal scalability and test coverage across platforms.</p>
    <p>Ultimately, clean boundaries prevent technical debt from accumulating over multi-year software development lifecycles.</p>
    <p>Teams achieve predictable velocity by establishing consistent repository contracts and dependency injection containers.</p>
    <p>As enterprise requirements evolve, modular bounded contexts can be decoupled or refactored with zero regressions.</p>
  </article>
</body>
</html>
''',
              ),
            );
          },
        ),
      );

      final extractor = LinkMetadataExtractor(dio: dio);
      final metadata = await extractor.extract('https://myblog.com/clean-arch');

      expect(metadata.provider, LinkProvider.genericWeb);
      expect(metadata.title, 'Clean Architecture Guide');
      expect(metadata.readableContent, contains('# Clean Architecture Overview'));
      expect(metadata.wordCount, greaterThan(60));
    });
  });

  group('MemoryReviewScreen & MemoryDetailScreen YouTube Integration Tests', () {
    late FakeCaptureRepository fakeRepo;
    late CaptureBloc captureBloc;

    setUp(() {
      fakeRepo = FakeCaptureRepository([]);
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(fakeRepo),
        getMemoriesUseCase: GetMemoriesUseCase(fakeRepo),
        repository: fakeRepo,
      );
    });

    tearDown(() {
      captureBloc.close();
    });

    testWidgets('MemoryReviewScreen displays YouTube video thumbnail and saves dual content',
        (tester) async {
      const canonicalUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      const readableBody = 'Channel: Reso Coder\n\nDescription:\nFlutter BLoC state management tutorial covering events and states.';

      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: null,
              linkUrl: canonicalUrl,
              readableContent: readableBody,
              previewImageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
              initialTitle: 'Flutter BLoC Tutorial',
              initialContent: canonicalUrl,
              initialCategory: AppStrings.categoryStudy,
              initialTags: const ['flutter', 'bloc', 'youtube', 'link'],
              initialSummary: '• BLoC pattern tutorial with events and states',
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 15),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Flutter BLoC Tutorial'), findsOneWidget);
      expect(find.text('#youtube'), findsOneWidget);
      expect(find.text('#bloc'), findsOneWidget);
      expect(find.text('Extracted Content'), findsOneWidget);

      // Expand Extracted Content
      await tester.ensureVisible(find.text('View extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();

      expect(find.text('Hide extracted text'), findsOneWidget);
      expect(find.text(readableBody), findsOneWidget);

      // Save memory
      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.title, 'Flutter BLoC Tutorial');
      expect(saved.content, '$canonicalUrl\n\n$readableBody');
      expect(saved.tags, contains('youtube'));
      expect(saved.category, AppStrings.categoryStudy);
    });

    testWidgets('offline YouTube memory saves locally with pending status',
        (tester) async {
      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: null,
              linkUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              readableContent: null,
              previewImageUrl: null,
              initialTitle: 'YouTube Video (Offline)',
              initialContent: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              initialCategory: AppStrings.categoryPersonal,
              initialTags: const ['youtube', 'link'],
              initialSummary: '',
              aiStatus: 'pending',
              createdAt: DateTime(2026, 9, 15),
              isOffline: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text("You're offline"), findsOneWidget);

      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.content, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(saved.aiStatus, 'pending');
    });

    testWidgets('MemoryDetailScreen renders YouTube URL banner and video content card',
        (tester) async {
      const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      const body = 'Channel: Tech Creator\n\nDescription:\nComprehensive architecture breakdown.';
      final memory = MemoryEntity(
        id: 'yt-mem-1',
        userId: 'user-1',
        title: 'Software Architecture Video',
        content: '$url\n\n$body',
        category: AppStrings.categoryWork,
        tags: const ['architecture', 'youtube', 'link'],
        aiStatus: 'processed',
        clientCreatedAt: DateTime(2026, 9, 15),
        clientUpdatedAt: DateTime(2026, 9, 15),
        serverUpdatedAt: DateTime(2026, 9, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MemoryDetailScreen(
            memoryId: memory.id,
            initialMemory: memory,
          ),
        ),
      );

      await tester.pump();

      // Action banner shows the YouTube URL
      expect(find.text(url), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

      // Extracted Content shows section
      expect(find.text('Extracted Content'), findsOneWidget);
      await tester.tap(find.text('View extracted text'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Channel: Tech Creator'), findsOneWidget);
      expect(find.textContaining('Comprehensive architecture breakdown.'), findsOneWidget);
    });
  });

  group('Take Photo & Scan Document Regression Verification', () {
    late FakeCaptureRepository fakeRepo;
    late CaptureBloc captureBloc;
    late Directory tempDir;
    late File dummyImageFile;

    setUp(() {
      fakeRepo = FakeCaptureRepository([]);
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(fakeRepo),
        getMemoriesUseCase: GetMemoriesUseCase(fakeRepo),
        repository: fakeRepo,
      );

      tempDir = Directory.systemTemp.createTempSync();
      final transparentPng = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ];
      dummyImageFile = File('${tempDir.path}/test_image.png')
        ..writeAsBytesSync(transparentPng);
    });

    tearDown(() {
      captureBloc.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('Take Photo flow saves visual memory cleanly without regressions',
        (tester) async {
      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyImageFile,
              initialTitle: 'Photo Captured Note',
              initialContent: 'Physical note photo',
              initialCategory: AppStrings.categoryPersonal,
              initialTags: const ['photo'],
              initialSummary: '• Physical note content summary',
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 15),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.title, 'Photo Captured Note');
      expect(saved.mediaUrl, isNotNull);
    });

    testWidgets('Scan Document flow saves document memory cleanly without regressions',
        (tester) async {
      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyImageFile,
              initialTitle: 'Scanned Contract #99',
              initialContent: 'Contract clause details and signatories',
              rawOcrText: 'Contract clause details and signatories',
              initialCategory: AppStrings.categoryWork,
              initialTags: const ['contract', 'document'],
              initialSummary: '• Contract clause terms signed',
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 15),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.title, 'Scanned Contract #99');
      expect(saved.mediaUrl, isNotNull);
    });
  });
}
