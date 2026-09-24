import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:second_brain/features/capture/presentation/widgets/add_link_dialog.dart';

class FakeLinkAiRepository implements AiRepository {
  final String title;
  final String summary;
  final String category;
  final List<String> tags;

  const FakeLinkAiRepository({
    this.title = 'Flutter Official Website',
    this.summary =
        '• Flutter multi-platform UI framework\n• Build apps for mobile, web, and desktop',
    this.category = AppStrings.categoryWork,
    this.tags = const ['flutter', 'dart', 'framework'],
  });

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
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

  group('URL Validation Unit Tests', () {
    test('valid http URL is accepted', () {
      final error = LinkMetadataExtractor.validateUrl(
        'http://example.com/article',
      );
      expect(error, isNull);
    });

    test('valid https URL is accepted', () {
      final error = LinkMetadataExtractor.validateUrl(
        'https://flutter.dev/docs',
      );
      expect(error, isNull);
    });

    test('invalid URL without http/https is rejected', () {
      final error = LinkMetadataExtractor.validateUrl(
        'ftp://files.example.com',
      );
      expect(error, contains('Only http:// and https://'));
    });

    test('random text is rejected as invalid URL', () {
      final error = LinkMetadataExtractor.validateUrl('not a url at all');
      expect(error, contains('URL must start with http:// or https://'));
    });

    test('empty or null URL is rejected', () {
      expect(LinkMetadataExtractor.validateUrl(''), isNotNull);
      expect(LinkMetadataExtractor.validateUrl(null), isNotNull);
    });

    test('URL missing host is rejected', () {
      expect(LinkMetadataExtractor.validateUrl('http://'), isNotNull);
      expect(LinkMetadataExtractor.validateUrl('https:///'), isNotNull);
      expect(
        LinkMetadataExtractor.validateUrl('https://invalidhost'),
        isNotNull,
      );
    });
  });

  group('Web Metadata Extraction Unit Tests', () {
    test('extracts OpenGraph and HTML meta tags accurately', () {
      const sampleHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Flutter - Build apps for any screen</title>
  <meta property="og:title" content="Flutter Documentation" />
  <meta property="og:description" content="Build, test, and deploy beautiful mobile, web, desktop, and embedded apps from a single codebase." />
  <meta property="og:image" content="https://flutter.dev/images/flutter-logo-sharing.png" />
  <meta property="og:site_name" content="Flutter" />
  <link rel="icon" href="/favicon.png" />
</head>
<body><h1>Welcome</h1></body>
</html>
''';

      final metadata = LinkMetadataExtractor.parseHtml(
        'https://flutter.dev',
        sampleHtml,
      );

      expect(metadata.url, 'https://flutter.dev');
      expect(metadata.title, 'Flutter Documentation');
      expect(metadata.description, contains('Build, test, and deploy'));
      expect(
        metadata.imageUrl,
        'https://flutter.dev/images/flutter-logo-sharing.png',
      );
      expect(metadata.siteName, 'Flutter');
      expect(metadata.faviconUrl, 'https://flutter.dev/favicon.png');
      expect(metadata.hasContent, isTrue);
    });

    test('falls back to standard title and description if og tags missing', () {
      const sampleHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Simple Blog &amp; Notes</title>
  <meta name="description" content="Personal thoughts and tech guides." />
</head>
<body><h1>Hello World</h1></body>
</html>
''';

      final metadata = LinkMetadataExtractor.parseHtml(
        'https://myblog.com/post',
        sampleHtml,
      );

      expect(metadata.title, 'Simple Blog & Notes');
      expect(metadata.description, 'Personal thoughts and tech guides.');
      expect(metadata.siteName, 'myblog.com');
      expect(metadata.hasContent, isTrue);
    });

    test('gracefully handles metadata extraction failure', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Network connection refused',
              ),
            );
          },
        ),
      );

      final extractor = LinkMetadataExtractor(dio: dio);
      final metadata = await extractor.extract(
        'https://offline-example.com/item',
      );

      expect(metadata.url, 'https://offline-example.com/item');
      expect(metadata.title, isNull);
      expect(metadata.siteName, 'offline-example.com');
    });
  });

  group('Readable Webpage Content Extraction Unit Tests', () {
    test(
      'extracts <article> container when present, ignoring noise, navigation, and sidebar',
      () {
        const html = '''
<!DOCTYPE html>
<html>
<head>
  <title>The Future of Computing</title>
</head>
<body>
  <nav><a href="/">Home</a><a href="/archive">Archive</a></nav>
  <header><h1>Blog Header</h1></header>
  <aside>
    <div class="ad-container">Special Offer Advertisement</div>
    <button>Share</button>
  </aside>
  <article>
    <h1>The Future of Mobile Computing</h1>
    <p>Mobile computing has evolved dramatically over the last decade with the advent of powerful edge processors, neural engines, and sophisticated cross-platform frameworks.</p>
    <p>Developers can now build high-performance applications that deliver native performance, rich animations, and comprehensive offline capabilities using modern reactive UI toolkits.</p>
    <p>This paradigm shift enables single-codebase architectures to conquer desktop, mobile, and web targets without compromising on tactile user experience or accessibility standards.</p>
    <p>Furthermore, cloud synchronization protocols allow distributed clients to persist states smoothly even when operating in intermittent connectivity conditions.</p>
    <p>These architectural principles ensure data integrity, responsive interfaces, and long-term maintainability for mission-critical software systems across platforms.</p>
  </article>
  <footer>
    <p>© 2026 All rights reserved. Cookie policy and terms of service apply.</p>
  </footer>
</body>
</html>
''';

        final metadata = LinkMetadataExtractor.parseHtml(
          'https://techblog.com/future-mobile',
          html,
        );

        expect(metadata.readableContent, isNotNull);
        expect(
          metadata.readableContent,
          contains('# The Future of Mobile Computing'),
        );
        expect(
          metadata.readableContent,
          contains('Mobile computing has evolved dramatically'),
        );
        expect(
          metadata.readableContent,
          contains('Developers can now build high-performance'),
        );
        expect(
          metadata.readableContent,
          isNot(contains('Special Offer Advertisement')),
        );
        expect(
          metadata.readableContent,
          isNot(contains('All rights reserved')),
        );
        expect(metadata.readableContent, isNot(contains('Cookie policy')));
        expect(metadata.readableContent, isNot(contains('Archive')));
        expect(metadata.wordCount, greaterThan(80));
      },
    );

    test('extracts <main> container when <article> is not present', () {
      const html = '''
<!DOCTYPE html>
<html>
<head>
  <title>Vector Search Essentials</title>
</head>
<body>
  <div class="site-header">Site Header Bar</div>
  <main>
    <h2>Deep Dive into Vector Embeddings</h2>
    <p>Vector embeddings transform multimodal unstructured information into dense numerical representations within high-dimensional geometric spaces.</p>
    <p>By computing cosine similarities between query vectors and stored knowledge embeddings, personal assistants can efficiently retrieve contextually relevant memories.</p>
    <p>This foundational technique powers semantic search, grounded retrieval-augmented generation, and automated tag clustering across vast historical data corpora.</p>
    <p>Modern machine learning models produce semantic vectors that capture deep conceptual relationships and contextual nuances across multiple languages.</p>
    <p>Understanding these mathematical foundations enables engineers to design highly scalable knowledge management engines with minimal lookup latencies.</p>
  </main>
  <div class="site-footer">Page Footer Information</div>
</body>
</html>
''';

      final metadata = LinkMetadataExtractor.parseHtml(
        'https://ai.example.org/embeddings',
        html,
      );

      expect(metadata.readableContent, isNotNull);
      expect(
        metadata.readableContent,
        contains('## Deep Dive into Vector Embeddings'),
      );
      expect(
        metadata.readableContent,
        contains('Vector embeddings transform multimodal'),
      );
      expect(metadata.wordCount, greaterThan(80));
    });

    test('formats headings, blockquotes, lists, and code blocks correctly', () {
      const html = '''
<!DOCTYPE html>
<html>
<head><title>Syntax Guide</title></head>
<body>
  <article>
    <h1>Top Level Header</h1>
    <h2>Second Level Header</h2>
    <h3>Third Level Header</h3>
    <blockquote>"Knowledge is power, but memory is its foundation."</blockquote>
    <p>Here is an introduction to the core data structures and functional algorithms implemented in this project.</p>
    <ul>
      <li>First important item in unordered list</li>
      <li>Second critical point regarding memory safety</li>
    </ul>
    <pre>final client = SupabaseClient(url, key);</pre>
    <p>Following the code sample, we observe how reactive streams synchronize state across client devices without requiring manual network polling.</p>
    <p>Each component subscribes to distinct broadcast channels, updating local in-memory states whenever server push notifications are detected.</p>
    <p>This robust synchronization topology guarantees consistent views of personal knowledge bases while keeping battery and radio consumption at optimal levels.</p>
  </article>
</body>
</html>
''';

      final metadata = LinkMetadataExtractor.parseHtml(
        'https://syntax.dev/guide',
        html,
      );

      expect(metadata.readableContent, contains('# Top Level Header'));
      expect(metadata.readableContent, contains('## Second Level Header'));
      expect(metadata.readableContent, contains('### Third Level Header'));
      expect(
        metadata.readableContent,
        contains('> "Knowledge is power, but memory is its foundation."'),
      );
      expect(
        metadata.readableContent,
        contains('• First important item in unordered list'),
      );
      expect(
        metadata.readableContent,
        contains('• Second critical point regarding memory safety'),
      );
      expect(
        metadata.readableContent,
        contains('final client = SupabaseClient(url, key);'),
      );
      expect(metadata.wordCount, greaterThan(80));
    });

    test(
      'caps long readable content cleanly at ~10,000 characters without crashing',
      () {
        final paragraph =
            'This is an extensive analysis of autonomous software engineering agents and distributed systems. ' *
            8;
        final longHtml =
            '''
<!DOCTYPE html>
<html>
<head><title>Long Document</title></head>
<body>
  <article>
    ${List.generate(25, (i) => '<p>Section $i: $paragraph</p>').join('\n')}
  </article>
</body>
</html>
''';

        final metadata = LinkMetadataExtractor.parseHtml(
          'https://longtext.org/book',
          longHtml,
        );

        expect(metadata.readableContent, isNotNull);
        expect(metadata.readableContent!.length, lessThanOrEqualTo(10000));
        expect(metadata.readableContent!.length, greaterThan(6500));
      },
    );

    test(
      'falls back to og:title and og:description when content has fewer than 80 words',
      () {
        const shortHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Short Page</title>
  <meta property="og:title" content="Micro Note Title" />
  <meta property="og:description" content="A very concise summary describing an instant thought or idea." />
</head>
<body>
  <article>
    <p>Tiny body.</p>
  </article>
</body>
</html>
''';

        final metadata = LinkMetadataExtractor.parseHtml(
          'https://micro.blog/note',
          shortHtml,
        );

        expect(metadata.readableContent, isNotNull);
        expect(metadata.readableContent, contains('Micro Note Title'));
        expect(
          metadata.readableContent,
          contains(
            'A very concise summary describing an instant thought or idea.',
          ),
        );
        expect(metadata.wordCount, greaterThan(5));
      },
    );

    test(
      'handles 403 Forbidden and network errors gracefully without failing link metadata',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 403,
                    statusMessage: 'Forbidden',
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final extractor = LinkMetadataExtractor(dio: dio);
        final metadata = await extractor.extract(
          'https://protected.com/secret',
        );

        expect(metadata.url, 'https://protected.com/secret');
        expect(metadata.siteName, 'protected.com');
        expect(metadata.readableContent, isNull);
      },
    );
  });

  group('AddLinkBottomSheet Widget Tests', () {
    testWidgets('renders input field, paste button, and continue button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AddLinkBottomSheet())),
      );

      expect(find.text('Add Web Link'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Paste from Clipboard'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets(
      'shows inline validation error on empty or invalid URL submission',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AddLinkBottomSheet())),
        );

        // Tap continue with empty field
        await tester.tap(find.text('Continue'));
        await tester.pump();

        expect(find.text('Please enter a URL'), findsOneWidget);

        // Enter invalid scheme
        await tester.enterText(find.byType(TextField), 'ftp://bad-link.com');
        await tester.tap(find.text('Continue'));
        await tester.pump();

        expect(
          find.text('Only http:// and https:// URLs are supported'),
          findsOneWidget,
        );
      },
    );

    testWidgets('prefills clipboard URL when valid http/https URL is copied', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'https://github.com/flutter/flutter'};
            }
            return null;
          });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AddLinkBottomSheet())),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://github.com/flutter/flutter'), findsOneWidget);
    });
  });

  group('MemoryReviewScreen with Link (Nullable imageFile) Tests', () {
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

    testWidgets(
      'renders styled link card without crashing when imageFile is null',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: null,
                linkUrl: 'https://flutter.dev',
                previewImageUrl: null,
                initialTitle: 'Flutter Dev Official',
                initialContent: 'https://flutter.dev',
                rawOcrText: 'https://flutter.dev\n\nBuild apps for any screen',
                initialCategory: AppStrings.categoryWork,
                initialTags: const ['flutter', 'link'],
                initialSummary:
                    '• Official Flutter documentation and resources',
                aiStatus: 'processed',
                createdAt: DateTime(2025, 1, 1),
              ),
            ),
          ),
        );

        await tester.pump();

        // Verify domain and link url in header preview card
        expect(find.text('flutter.dev'), findsOneWidget);
        expect(find.text('https://flutter.dev'), findsWidgets);
        expect(find.text('Flutter Dev Official'), findsOneWidget);
        expect(find.text('Work'), findsWidgets);
        expect(find.text('#flutter'), findsOneWidget);
        expect(find.text('#link'), findsOneWidget);
        expect(
          find.text('• Official Flutter documentation and resources'),
          findsOneWidget,
        );
        expect(find.text('Save Memory'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Save Memory persists URL in content and navigates home',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: null,
                linkUrl: 'https://dart.dev',
                previewImageUrl: 'https://dart.dev/assets/img/logo.png',
                initialTitle: 'Dart Language Reference',
                initialContent: 'https://dart.dev',
                initialCategory: AppStrings.categoryStudy,
                initialTags: const ['dart', 'programming', 'link'],
                initialSummary:
                    '• Fast, productive language for multi-platform apps',
                aiStatus: 'processed',
                createdAt: DateTime(2025, 1, 1),
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap Save Memory
        await tester.ensureVisible(find.text('Save Memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Memory'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        // Verify memory was saved in repository
        expect(fakeRepo.memories.length, 1);
        final saved = fakeRepo.memories.first;
        expect(saved.title, 'Dart Language Reference');
        expect(saved.content, 'https://dart.dev');
        expect(saved.mediaUrl, 'https://dart.dev/assets/img/logo.png');
        expect(saved.category, AppStrings.categoryStudy);
        expect(saved.tags, contains('link'));
        expect(saved.tags, contains('dart'));
        expect(saved.aiStatus, 'processed');
      },
    );

    testWidgets('offline Add Link saves locally with aiStatus pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: null,
              linkUrl: 'https://offline-article.org/guide',
              previewImageUrl: null,
              initialTitle: 'Offline Reading Guide',
              initialContent: 'https://offline-article.org/guide',
              initialCategory: AppStrings.categoryPersonal,
              initialTags: const ['offline', 'link'],
              initialSummary: '',
              aiStatus: 'pending',
              createdAt: DateTime(2025, 1, 1),
              isOffline: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Offline badge should be visible
      expect(find.text("You're offline"), findsOneWidget);

      // Tap Save Memory
      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.title, 'Offline Reading Guide');
      expect(saved.content, 'https://offline-article.org/guide');
      expect(saved.aiStatus, 'pending');
    });

    testWidgets(
      'displays readable content in Extracted Content card and saves URL on line 1 with readable content',
      (tester) async {
        const readableText =
            '# Article Title\n\nDetailed readable webpage paragraph extracted cleanly.';
        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: null,
                linkUrl: 'https://news.example.com/article',
                readableContent: readableText,
                previewImageUrl: null,
                initialTitle: 'Article Title',
                initialContent: 'https://news.example.com/article',
                initialCategory: AppStrings.categoryWork,
                initialTags: const ['article', 'link'],
                initialSummary: '• Article summary point',
                aiStatus: 'processed',
                createdAt: DateTime(2025, 1, 1),
              ),
            ),
          ),
        );

        await tester.pump();

        // Extracted Content card should be visible
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(find.text('View extracted text'), findsOneWidget);

        // Expand Extracted Content
        await tester.ensureVisible(find.text('View extracted text'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(find.text('Hide extracted text'), findsOneWidget);
        expect(find.text(readableText), findsOneWidget);

        // Tap Save Memory
        await tester.ensureVisible(find.text('Save Memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Memory'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(fakeRepo.memories.length, 1);
        final saved = fakeRepo.memories.first;
        expect(
          saved.content,
          'https://news.example.com/article\n\n$readableText',
        );
        expect(saved.title, 'Article Title');
      },
    );
  });

  group('Take Photo / Scan Document Regression Verification', () {
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
      dummyImageFile = File('${tempDir.path}/test_image.png')
        ..writeAsBytesSync(transparentPng);
    });

    tearDown(() {
      captureBloc.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'MemoryReviewScreen with imageFile renders Image.file and persists image properly',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: dummyImageFile,
                initialTitle: 'Photo Captured Memory',
                initialContent: 'Visual content notes',
                initialCategory: AppStrings.categoryPersonal,
                initialTags: const ['photo'],
                initialSummary: '• Photo summary note',
                aiStatus: 'processed',
                createdAt: DateTime(2025, 1, 1),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Photo Captured Memory'), findsOneWidget);

        await tester.ensureVisible(find.text('Save Memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Memory'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(fakeRepo.memories.length, 1);
        final saved = fakeRepo.memories.first;
        expect(saved.title, 'Photo Captured Memory');
        expect(saved.mediaUrl, isNotNull);
      },
    );

    testWidgets(
      'MemoryReviewScreen with scan document parameters saves correctly with photo and summary',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryReviewScreen(
                imageFile: dummyImageFile,
                linkUrl: null,
                readableContent: null,
                initialTitle: 'Scanned Invoice #4021',
                initialContent: 'Invoice #4021 Total: \$150.00 Due: Oct 1',
                rawOcrText: 'Invoice #4021 Total: \$150.00 Due: Oct 1',
                initialCategory: AppStrings.categoryFinance,
                initialTags: const ['invoice', 'finance'],
                initialSummary: '• Invoice #4021 due Oct 1 for \$150.00',
                aiStatus: 'processed',
                createdAt: DateTime(2025, 1, 1),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Scanned Invoice #4021'), findsOneWidget);

        await tester.ensureVisible(find.text('Save Memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Memory'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(fakeRepo.memories.length, 1);
        final saved = fakeRepo.memories.first;
        expect(saved.title, 'Scanned Invoice #4021');
        expect(saved.content, '• Invoice #4021 due Oct 1 for \$150.00');
        expect(saved.mediaUrl, isNotNull);
        expect(saved.category, AppStrings.categoryFinance);
      },
    );
  });

  group('MemoryDetailScreen Link and Readable Content Tests', () {
    testWidgets(
      'displays Link Action Banner with line 1 URL and renders readable content in Extracted Content card',
      (tester) async {
        const url = 'https://flutter.dev/multiplatform';
        const body =
            'Flutter transforms the app development process. Build, test, and deploy beautiful apps from a single codebase.';
        final memory = MemoryEntity(
          id: 'mem-link-101',
          userId: 'user-xyz',
          title: 'Multiplatform Development with Flutter',
          content: '$url\n\n$body',
          category: AppStrings.categoryWork,
          tags: const ['flutter', 'mobile', 'link'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 15, 12, 0),
          clientUpdatedAt: DateTime(2026, 9, 15, 12, 0),
          serverUpdatedAt: DateTime(2026, 9, 15, 12, 0),
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

        // Link Action Banner should display the URL only
        expect(find.text(url), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

        // Extracted Content card should be present
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(find.text('View extracted text'), findsOneWidget);

        // Expand Extracted Content
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(find.text('Hide extracted text'), findsOneWidget);
        // It should display the body text and NOT repeat the URL
        expect(
          find.textContaining('Flutter transforms the app development process'),
          findsOneWidget,
        );
      },
    );
  });
}
