import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/core/utils/link_metadata_extractor.dart';
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

  @override
  Future<void> deleteMemory(String memoryId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Add Link v2 - TikTok Detection & Extraction Tests', () {
    test('detects standard TikTok video URL with username', () {
      final uri = Uri.parse(
        'https://www.tiktok.com/@scout2015/video/6718335390845095173',
      );
      expect(LinkProviderDetector.detect(uri), LinkProvider.tiktok);
      expect(LinkProviderDetector.isTikTok(uri), isTrue);
      expect(LinkProviderDetector.extractTikTokUsername(uri), 'scout2015');
      expect(
        LinkProviderDetector.extractTikTokVideoId(uri),
        '6718335390845095173',
      );
      expect(
        LinkProviderDetector.toCanonicalTikTokUrl(uri),
        'https://www.tiktok.com/@scout2015/video/6718335390845095173',
      );
    });

    test('detects mobile TikTok URL (m.tiktok.com/v/...)', () {
      final uri = Uri.parse('https://m.tiktok.com/v/6718335390845095173.html');
      expect(LinkProviderDetector.detect(uri), LinkProvider.tiktok);
      expect(
        LinkProviderDetector.extractTikTokVideoId(uri),
        '6718335390845095173',
      );
    });

    test('detects short TikTok URLs (vm.tiktok.com and vt.tiktok.com)', () {
      final vmUri = Uri.parse('https://vm.tiktok.com/ZMhN12345/');
      final vtUri = Uri.parse('https://vt.tiktok.com/ZShN67890/');
      expect(LinkProviderDetector.detect(vmUri), LinkProvider.tiktok);
      expect(LinkProviderDetector.detect(vtUri), LinkProvider.tiktok);
    });

    test('cleans tracking parameters on TikTok URLs', () {
      final uri = Uri.parse(
        'https://www.tiktok.com/@scout2015/video/6718335390845095173?is_from_webapp=1&sender_device=pc&utm_source=share',
      );
      expect(LinkProviderDetector.detect(uri), LinkProvider.tiktok);
      expect(LinkProviderDetector.extractTikTokUsername(uri), 'scout2015');
      expect(
        LinkProviderDetector.extractTikTokVideoId(uri),
        '6718335390845095173',
      );
      expect(
        LinkProviderDetector.toCanonicalTikTokUrl(uri),
        'https://www.tiktok.com/@scout2015/video/6718335390845095173',
      );
    });

    test('negative domain tests for TikTok spoofing', () {
      expect(
        LinkProviderDetector.detect(
          Uri.parse('https://not-tiktok.com/@user/video/123'),
        ),
        LinkProvider.genericWeb,
      );
      expect(
        LinkProviderDetector.detect(
          Uri.parse('https://tiktok.com.scam.net/video/123'),
        ),
        LinkProvider.genericWeb,
      );
    });

    test(
      'TikTokLinkExtractor extracts real oEmbed metadata and builds readable content',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.uri.host == 'www.tiktok.com' &&
                  options.uri.path == '/oembed') {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'version': '1.0',
                      'type': 'video',
                      'title':
                          "Scramble up ur name & I'll try to guess it???? #foryoupage #petsoftiktok #aesthetic",
                      'author_url': 'https://www.tiktok.com/@scout2015',
                      'author_name': 'Scout, Suki & Stella',
                      'author_unique_id': 'scout2015',
                      'thumbnail_url':
                          'https://p19-sign.tiktokcdn.com/tos-maliva-p/test_thumb.jpg',
                      'embed_product_id': '6718335390845095173',
                      'provider_name': 'TikTok',
                    },
                  ),
                );
              }
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'Not found',
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final extractor = TikTokLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse(
            'https://www.tiktok.com/@scout2015/video/6718335390845095173',
          ),
        );

        expect(rich.provider, LinkProvider.tiktok);
        expect(
          rich.canonicalUrl,
          'https://www.tiktok.com/@scout2015/video/6718335390845095173',
        );
        expect(
          rich.title,
          "Scramble up ur name & I'll try to guess it???? #foryoupage #petsoftiktok #aesthetic",
        );
        expect(rich.creator, 'Scout, Suki & Stella (@scout2015)');
        expect(
          rich.thumbnailUrl,
          'https://p19-sign.tiktokcdn.com/tos-maliva-p/test_thumb.jpg',
        );
        expect(rich.siteName, 'TikTok');
        expect(rich.transcript, isNull); // Never fake a transcript
        expect(rich.readableContent, contains('Platform: TikTok'));
        expect(
          rich.readableContent,
          contains('Creator: Scout, Suki & Stella (@scout2015)'),
        );
        expect(rich.readableContent, contains('Caption: Scramble up ur name'));
        expect(rich.wordCount, greaterThan(5));
        expect(rich.metadata?['videoId'], '6718335390845095173');
        expect(rich.metadata?['authorUniqueId'], 'scout2015');
      },
    );

    test(
      'TikTokLinkExtractor gracefully handles offline/network error without crash',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'Network offline',
                  type: DioExceptionType.connectionError,
                ),
              );
            },
          ),
        );

        final extractor = TikTokLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse(
            'https://www.tiktok.com/@scout2015/video/6718335390845095173',
          ),
        );

        expect(rich.provider, LinkProvider.tiktok);
        expect(
          rich.canonicalUrl,
          'https://www.tiktok.com/@scout2015/video/6718335390845095173',
        );
        expect(rich.creator, '@scout2015');
        expect(rich.siteName, 'TikTok');
        expect(rich.transcript, isNull);
      },
    );
  });

  group('Add Link v2 - Instagram Detection & Extraction Tests', () {
    test('detects Instagram post URL (/p/SHORTCODE/)', () {
      final uri = Uri.parse('https://www.instagram.com/p/C6tK_7CvM8p/');
      expect(LinkProviderDetector.detect(uri), LinkProvider.instagram);
      expect(LinkProviderDetector.isInstagram(uri), isTrue);
      expect(
        LinkProviderDetector.extractInstagramShortcode(uri),
        'C6tK_7CvM8p',
      );
      expect(LinkProviderDetector.extractInstagramPostType(uri), 'p');
      expect(
        LinkProviderDetector.toCanonicalInstagramUrl(uri),
        'https://www.instagram.com/p/C6tK_7CvM8p/',
      );
    });

    test('detects Instagram reel URL (/reel/SHORTCODE/ and /reels/)', () {
      final reelUri = Uri.parse('https://www.instagram.com/reel/C6tK_7CvM8p/');
      final reelsUri = Uri.parse('https://instagram.com/reels/C6tK_7CvM8p/');
      expect(LinkProviderDetector.detect(reelUri), LinkProvider.instagram);
      expect(LinkProviderDetector.detect(reelsUri), LinkProvider.instagram);
      expect(
        LinkProviderDetector.extractInstagramShortcode(reelUri),
        'C6tK_7CvM8p',
      );
      expect(LinkProviderDetector.extractInstagramPostType(reelUri), 'reel');
      expect(LinkProviderDetector.extractInstagramPostType(reelsUri), 'reel');
      expect(
        LinkProviderDetector.toCanonicalInstagramUrl(reelUri),
        'https://www.instagram.com/reel/C6tK_7CvM8p/',
      );
    });

    test('detects Instagram TV URL (/tv/SHORTCODE/)', () {
      final uri = Uri.parse('https://www.instagram.com/tv/C6tK_7CvM8p/');
      expect(LinkProviderDetector.detect(uri), LinkProvider.instagram);
      expect(
        LinkProviderDetector.extractInstagramShortcode(uri),
        'C6tK_7CvM8p',
      );
      expect(LinkProviderDetector.extractInstagramPostType(uri), 'tv');
      expect(
        LinkProviderDetector.toCanonicalInstagramUrl(uri),
        'https://www.instagram.com/tv/C6tK_7CvM8p/',
      );
    });

    test('detects instagr.am short domain and cleans tracking parameters', () {
      final uri = Uri.parse(
        'https://instagr.am/p/C6tK_7CvM8p/?igsh=MWQ1N3M5bDE2cTIzNA==&utm_source=ig_web_copy_link',
      );
      expect(LinkProviderDetector.detect(uri), LinkProvider.instagram);
      expect(
        LinkProviderDetector.extractInstagramShortcode(uri),
        'C6tK_7CvM8p',
      );
      expect(
        LinkProviderDetector.toCanonicalInstagramUrl(uri),
        'https://www.instagram.com/p/C6tK_7CvM8p/',
      );
    });

    test('negative domain tests for Instagram spoofing', () {
      expect(
        LinkProviderDetector.detect(
          Uri.parse('https://notinstagram.com/p/123'),
        ),
        LinkProvider.genericWeb,
      );
      expect(
        LinkProviderDetector.detect(
          Uri.parse('https://instagram.com.scam.net/p/123'),
        ),
        LinkProvider.genericWeb,
      );
    });

    test(
      'InstagramLinkExtractor strictly guards against Meta login wall and Login • Instagram title',
      () async {
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
  <title>Login • Instagram</title>
  <meta name="description" content="Welcome back to Instagram. Sign in to check out what your friends, family & interests have been capturing & sharing around the world." />
  <link rel="canonical" href="https://www.instagram.com/accounts/login/" />
</head>
<body>
  <div>Log In to Instagram</div>
</body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/reel/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(
          rich.canonicalUrl,
          'https://www.instagram.com/reel/C6tK_7CvM8p/',
        );
        expect(rich.siteName, 'Instagram');
        // Login title and description must be nullified, never stored!
        expect(rich.title, isNull);
        expect(rich.description, isNull);
        expect(rich.readableContent, isNull);
        expect(rich.transcript, isNull);
        expect(rich.metadata?['shortcode'], 'C6tK_7CvM8p');
        expect(rich.metadata?['postType'], 'reel');
      },
    );

    test(
      'InstagramLinkExtractor extracts real metadata when unblocked OpenGraph tags exist',
      () async {
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
  <title>National Geographic (@natgeo) on Instagram: "A breathtaking view of the aurora borealis dancing across the Arctic sky."</title>
  <meta property="og:title" content="National Geographic (@natgeo) on Instagram: &quot;A breathtaking view of the aurora borealis dancing across the Arctic sky.&quot;" />
  <meta property="og:description" content="A breathtaking view of the aurora borealis dancing across the Arctic sky." />
  <meta property="og:image" content="https://scontent.cdninstagram.com/v/aurora_post.jpg" />
  <meta property="og:site_name" content="Instagram" />
</head>
<body>
</body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/p/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(rich.canonicalUrl, 'https://www.instagram.com/p/C6tK_7CvM8p/');
        expect(rich.creator, 'National Geographic (@natgeo)');
        expect(
          rich.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/aurora_post.jpg',
        );
        expect(
          rich.description,
          'A breathtaking view of the aurora borealis dancing across the Arctic sky.',
        );
        expect(rich.readableContent, contains('Platform: Instagram'));
        expect(
          rich.readableContent,
          contains('Creator: National Geographic (@natgeo)'),
        );
        expect(rich.readableContent, contains('Caption: A breathtaking view'));
      },
    );

    test(
      'InstagramLinkExtractor parses reversed meta attributes and engagement string caption',
      () async {
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
  <meta content="12K likes, 45 comments - chef_mario on July 4, 2024: &quot;Crispy garlic parmesan potatoes recipe 🥔&quot;" property="og:description" />
  <meta content="https://scontent.cdninstagram.com/v/potatoes.jpg" property="og:image" />
  <meta content="https://www.instagram.com/reel/C8rNqYpOWJt/" property="og:url" />
</head>
<body></body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse(
            'https://www.instagram.com/reel/C8rNqYpOWJt/?igsh=abc123xyz',
          ),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(
          rich.canonicalUrl,
          'https://www.instagram.com/reel/C8rNqYpOWJt/',
        );
        expect(rich.creator, '@chef_mario');
        expect(rich.title, 'Crispy garlic parmesan potatoes recipe 🥔');
        expect(
          rich.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/potatoes.jpg',
        );
        expect(rich.readableContent, contains('Platform: Instagram'));
        expect(rich.readableContent, contains('Creator: @chef_mario'));
        expect(
          rich.readableContent,
          contains('Caption: Crispy garlic parmesan potatoes recipe 🥔'),
        );
      },
    );

    test(
      'InstagramLinkExtractor parses public structured metadata / JSON-LD schema.org object',
      () async {
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
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "SocialMediaPosting",
    "headline": "Morning coffee brewing ritual",
    "articleBody": "Step by step guide to the perfect pour-over coffee ☕",
    "author": {
      "@type": "Person",
      "name": "Coffee Lab",
      "alternateName": "@coffeelab"
    },
    "image": "https://scontent.cdninstagram.com/v/coffee.jpg"
  }
  </script>
</head>
<body></body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/p/C-vL-oRPbN6/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(rich.creator, 'Coffee Lab (@coffeelab)');
        expect(
          rich.title,
          'Step by step guide to the perfect pour-over coffee ☕',
        );
        expect(
          rich.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/coffee.jpg',
        );
        expect(rich.readableContent, contains('Platform: Instagram'));
        expect(
          rich.readableContent,
          contains('Creator: Coffee Lab (@coffeelab)'),
        );
        expect(
          rich.readableContent,
          contains(
            'Caption: Step by step guide to the perfect pour-over coffee ☕',
          ),
        );
      },
    );

    test(
      'InstagramLinkExtractor gracefully handles missing og:title',
      () async {
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
  <meta property="og:description" content="100 likes, 10 comments - baker_bob on Jan 1, 2024: &quot;Artisan sourdough loaves just out of the oven!&quot;" />
  <meta property="og:image" content="https://scontent.cdninstagram.com/v/bread.jpg" />
</head>
<body></body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/p/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(rich.creator, '@baker_bob');
        expect(rich.title, 'Artisan sourdough loaves just out of the oven!');
        expect(
          rich.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/bread.jpg',
        );
        expect(rich.readableContent, contains('Platform: Instagram'));
        expect(
          rich.readableContent,
          contains('Caption: Artisan sourdough loaves just out of the oven!'),
        );
      },
    );

    test(
      'InstagramLinkExtractor gracefully handles missing og:description',
      () async {
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
  <meta property="og:title" content="Chef Mario (@chef_mario) on Instagram: &quot;Fresh handmade pasta with truffles&quot;" />
  <meta property="og:image" content="https://scontent.cdninstagram.com/v/pasta.jpg" />
</head>
<body></body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/reel/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(rich.creator, 'Chef Mario (@chef_mario)');
        expect(rich.title, 'Fresh handmade pasta with truffles');
        expect(
          rich.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/pasta.jpg',
        );
        expect(rich.readableContent, contains('Platform: Instagram'));
        expect(
          rich.readableContent,
          contains('Caption: Fresh handmade pasta with truffles'),
        );
      },
    );

    test(
      'InstagramLinkExtractor sets thumbnailUrl to null when og:image is unavailable',
      () async {
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
  <meta property="og:title" content="Writer (@writer) on Instagram: &quot;Words on paper&quot;" />
</head>
<body></body>
</html>
''',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/p/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(rich.thumbnailUrl, isNull);
        expect(rich.title, 'Words on paper');
      },
    );

    test(
      'InstagramLinkExtractor handles malformed/broken response gracefully',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data:
                      '<<< broken html <script type="application/ld+json">{ invalid json</script>',
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/reel/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(
          rich.canonicalUrl,
          'https://www.instagram.com/reel/C6tK_7CvM8p/',
        );
        expect(rich.title, isNull);
        expect(rich.description, isNull);
        expect(rich.readableContent, isNull);
      },
    );

    test(
      'InstagramLinkExtractor gracefully handles offline/timeout without crash',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'Connection timeout',
                  type: DioExceptionType.connectionTimeout,
                ),
              );
            },
          ),
        );

        final extractor = InstagramLinkExtractor(dio: dio);
        final rich = await extractor.extract(
          Uri.parse('https://www.instagram.com/reel/C6tK_7CvM8p/'),
        );

        expect(rich.provider, LinkProvider.instagram);
        expect(
          rich.canonicalUrl,
          'https://www.instagram.com/reel/C6tK_7CvM8p/',
        );
        expect(rich.siteName, 'Instagram');
        expect(rich.title, isNull);
      },
    );
  });

  group('Add Link v2 - Dispatch Routing via LinkMetadataExtractor', () {
    test('routes TikTok URLs to TikTokLinkExtractor', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'www.tiktok.com' &&
                options.uri.path == '/oembed') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'title': 'Viral Dance Move #dance',
                    'author_name': 'Dancer Joe',
                    'author_unique_id': 'dancerjoe',
                    'thumbnail_url': 'https://tiktokcdn.com/thumb.jpg',
                    'embed_product_id': '99887766',
                  },
                ),
              );
            }
            return handler.reject(DioException(requestOptions: options));
          },
        ),
      );

      final extractor = LinkMetadataExtractor(dio: dio);
      final metadata = await extractor.extract(
        'https://www.tiktok.com/@dancerjoe/video/99887766',
      );

      expect(metadata.provider, LinkProvider.tiktok);
      expect(metadata.title, 'Viral Dance Move #dance');
      expect(metadata.creator, 'Dancer Joe (@dancerjoe)');
      expect(metadata.imageUrl, 'https://tiktokcdn.com/thumb.jpg');
    });

    test('routes Instagram URLs to InstagramLinkExtractor', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data:
                    '<html><head><title>Login • Instagram</title></head></html>',
              ),
            );
          },
        ),
      );

      final extractor = LinkMetadataExtractor(dio: dio);
      final metadata = await extractor.extract(
        'https://www.instagram.com/reel/C6tK_7CvM8p/',
      );

      expect(metadata.provider, LinkProvider.instagram);
      expect(metadata.url, 'https://www.instagram.com/reel/C6tK_7CvM8p/');
      expect(metadata.title, isNull);
      expect(metadata.siteName, 'Instagram');
    });
  });

  group('Add Link v2 - Gemini Input Context Structure Tests', () {
    test('constructs TikTok Gemini prompt with only real available fields', () {
      const metadata = LinkMetadata(
        url: 'https://www.tiktok.com/@scout2015/video/6718335390845095173',
        provider: LinkProvider.tiktok,
        creator: 'Scout, Suki & Stella (@scout2015)',
        title:
            "Scramble up ur name & I'll try to guess it???? #foryoupage #petsoftiktok #aesthetic",
        description: null,
        transcript: null,
      );

      final buffer = StringBuffer();
      buffer.writeln(metadata.url);
      if (metadata.provider == LinkProvider.tiktok) {
        buffer.writeln('Platform: TikTok');
        if (metadata.creator != null && metadata.creator!.isNotEmpty) {
          buffer.writeln('Creator: ${metadata.creator}');
        }
      }
      if (metadata.title != null && metadata.title!.isNotEmpty) {
        buffer.writeln('Caption: ${metadata.title}');
      }
      if (metadata.description != null &&
          metadata.description!.isNotEmpty &&
          metadata.description != metadata.title) {
        buffer.writeln('Description: ${metadata.description}');
      }
      if (metadata.transcript != null && metadata.transcript!.isNotEmpty) {
        buffer.writeln('\nTranscript:\n${metadata.transcript}');
      }
      final contentForAi = buffer.toString().trim();

      expect(
        contentForAi,
        contains('https://www.tiktok.com/@scout2015/video/6718335390845095173'),
      );
      expect(contentForAi, contains('Platform: TikTok'));
      expect(
        contentForAi,
        contains('Creator: Scout, Suki & Stella (@scout2015)'),
      );
      expect(contentForAi, contains('Caption: Scramble up ur name'));
      expect(contentForAi, isNot(contains('Transcript:')));
      expect(contentForAi, isNot(contains('Channel:')));
    });

    test(
      'constructs Instagram Gemini prompt with only real available fields',
      () {
        const metadata = LinkMetadata(
          url: 'https://www.instagram.com/reel/C6tK_7CvM8p/',
          provider: LinkProvider.instagram,
          creator: null,
          title: null,
          description: null,
          transcript: null,
        );

        final buffer = StringBuffer();
        buffer.writeln(metadata.url);
        if (metadata.provider == LinkProvider.instagram) {
          buffer.writeln('Platform: Instagram');
          if (metadata.creator != null && metadata.creator!.isNotEmpty) {
            buffer.writeln('Creator: ${metadata.creator}');
          }
        }
        if (metadata.title != null && metadata.title!.isNotEmpty) {
          buffer.writeln('Caption: ${metadata.title}');
        }
        if (metadata.transcript != null && metadata.transcript!.isNotEmpty) {
          buffer.writeln('\nTranscript:\n${metadata.transcript}');
        }
        final contentForAi = buffer.toString().trim();

        expect(
          contentForAi,
          contains('https://www.instagram.com/reel/C6tK_7CvM8p/'),
        );
        expect(contentForAi, contains('Platform: Instagram'));
        expect(contentForAi, isNot(contains('Creator:')));
        expect(contentForAi, isNot(contains('Caption:')));
        expect(contentForAi, isNot(contains('Transcript:')));
      },
    );
  });

  group('Add Link v2 - MemoryReviewScreen & MemoryDetailScreen Presentation Tests', () {
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

    testWidgets('renders TikTok memory review with thumbnail and caption', (
      tester,
    ) async {
      const canonicalUrl =
          'https://www.tiktok.com/@scout2015/video/6718335390845095173';
      const readableBody =
          'Platform: TikTok\nCreator: Scout, Suki & Stella (@scout2015)\nCaption: Scramble up ur name & I\'ll try to guess it????';

      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              linkUrl: canonicalUrl,
              previewImageUrl:
                  'https://p19-sign.tiktokcdn.com/tos-maliva-p/test_thumb.jpg',
              readableContent: readableBody,
              initialTitle: 'Quick 5-Minute Breakfast',
              initialContent: canonicalUrl,
              initialCategory: AppStrings.categoryPersonal,
              initialTags: const ['link', 'tiktok', 'recipe'],
              initialSummary:
                  '• Easy avocado toast\n• High-protein morning meal',
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 15),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify review title
      expect(find.text('Review & Save'), findsOneWidget);
      expect(find.text('Quick 5-Minute Breakfast'), findsOneWidget);

      // Verify TikTok tag and Personal category
      expect(find.text('#tiktok'), findsOneWidget);
      expect(find.text('#link'), findsOneWidget);
      expect(find.text(AppStrings.categoryPersonal), findsOneWidget);

      // Verify Extracted Content card
      expect(find.text('Extracted Content'), findsOneWidget);

      // Verify Save Memory works and stores canonical URL on line 1 and real context on line 2+
      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.content.startsWith(canonicalUrl), isTrue);
      expect(saved.content.contains('Platform: TikTok'), isTrue);
      expect(saved.content.contains('Creator: Scout, Suki & Stella'), isTrue);
      expect(
        saved.mediaUrl,
        'https://p19-sign.tiktokcdn.com/tos-maliva-p/test_thumb.jpg',
      );
    });

    testWidgets('renders Instagram memory review with fallback title and tag', (
      tester,
    ) async {
      final dateStr = DateFormat('MMM d').format(DateTime.now());
      final fallbackTitle = 'Instagram Reel ($dateStr)';
      const canonicalUrl = 'https://www.instagram.com/reel/C6tK_7CvM8p/';

      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: MaterialApp(
            home: MemoryReviewScreen(
              linkUrl: canonicalUrl,
              readableContent: null,
              previewImageUrl: null,
              initialTitle: fallbackTitle,
              initialContent: canonicalUrl,
              initialCategory: AppStrings.categoryPersonal,
              initialTags: const ['link', 'instagram'],
              initialSummary: '',
              aiStatus: 'pending',
              createdAt: DateTime(2026, 9, 15),
              isOffline: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify review title
      expect(find.text(fallbackTitle), findsOneWidget);

      // Verify tags
      expect(find.text('#instagram'), findsOneWidget);
      expect(find.text('#link'), findsOneWidget);

      // Save
      await tester.ensureVisible(find.text('Save Memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Memory'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(fakeRepo.memories.length, 1);
      final saved = fakeRepo.memories.first;
      expect(saved.content, canonicalUrl);
      expect(saved.tags.contains('instagram'), isTrue);
    });

    testWidgets(
      'MemoryDetailScreen renders TikTok / Instagram canonical URL banner and extracted content',
      (tester) async {
        const url =
            'https://www.tiktok.com/@scout2015/video/6718335390845095173';
        const body =
            'Platform: TikTok\nCreator: Scout, Suki & Stella (@scout2015)\nCaption: Dancing dog video';

        final memory = MemoryEntity(
          id: 'tiktok-mem-1',
          userId: 'user-1',
          title: 'Dancing Dog TikTok',
          content: '$url\n\n$body',
          category: AppStrings.categoryPersonal,
          tags: const ['tiktok', 'link', 'pets'],
          clientCreatedAt: DateTime(2026, 9, 15),
          clientUpdatedAt: DateTime(2026, 9, 15),
          serverUpdatedAt: DateTime(2026, 9, 15),
          aiStatus: 'processed',
          mediaUrl: 'https://p19-sign.tiktokcdn.com/thumb.jpg',
        );

        fakeRepo.memories.add(memory);

        await tester.pumpWidget(
          BlocProvider<CaptureBloc>.value(
            value: captureBloc,
            child: MaterialApp(
              home: MemoryDetailScreen(
                memoryId: memory.id,
                initialMemory: memory,
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Dancing Dog TikTok'), findsOneWidget);
        expect(find.text(url), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(find.text('#tiktok'), findsOneWidget);

        // Expand Extracted Content
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Platform: TikTok'), findsOneWidget);
        expect(
          find.textContaining('Creator: Scout, Suki & Stella'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Caption: Dancing dog video'),
          findsOneWidget,
        );
      },
    );
  });
}
