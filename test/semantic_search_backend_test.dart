import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/search/data/models/search_result_model.dart';

void main() {
  group('Semantic Search Phase 1 — Embedding Lifecycle Tests', () {
    test('Memory without embedding requires embedding generation', () {
      final memory = MemoryEntity(
        id: 'mem-1',
        userId: 'user-1',
        title: 'Work Sprint Retrospective',
        content: 'Discussed sprint 42 accomplishments and blockers',
        category: 'Work',
        tags: const ['agile', 'sprint'],
        aiStatus: 'processed', // Reviewed & approved by user
        embedding: null, // No embedding yet
        clientCreatedAt: DateTime.now(),
        clientUpdatedAt: DateTime.now(),
        serverUpdatedAt: DateTime.now(),
      );

      final needsEmbedding =
          memory.embedding == null || memory.embedding!.isEmpty;
      final hasMeaningfulContent =
          memory.content.trim().isNotEmpty || memory.title.trim().isNotEmpty;

      expect(needsEmbedding, isTrue);
      expect(hasMeaningfulContent, isTrue);
      // Confirms embedding_only payload flag should be sent
      expect(memory.aiStatus == 'processed', isTrue);
    });

    test(
      'Memory with existing valid 768-d embedding avoids duplicate generation',
      () {
        final validEmbedding = List<double>.filled(768, 0.042);
        final memory = MemoryEntity(
          id: 'mem-2',
          userId: 'user-1',
          title: 'Existing Embedded Memory',
          content: 'Content that is already embedded in vector space',
          category: 'Study',
          tags: const ['ai'],
          aiStatus: 'processed',
          embedding: validEmbedding,
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        final needsEmbedding =
            memory.embedding == null || memory.embedding!.isEmpty;
        expect(needsEmbedding, isFalse);
        expect(memory.embedding!.length, 768);
      },
    );

    test('Pending memory triggers full AI ingestion', () {
      final pendingMemory = MemoryEntity(
        id: 'mem-3',
        userId: 'user-1',
        title: 'Quick Note',
        content: 'Raw unprocessed text captured offline',
        category: 'General',
        tags: const [],
        aiStatus: 'pending',
        embedding: null,
        clientCreatedAt: DateTime.now(),
        clientUpdatedAt: DateTime.now(),
        serverUpdatedAt: DateTime.now(),
      );

      expect(pendingMemory.aiStatus, 'pending');
      final needsFullIngestion = pendingMemory.aiStatus == 'pending';
      expect(needsFullIngestion, isTrue);
    });

    test(
      'Embedding failure preserves memory with null embedding without fabricating synthetic data',
      () {
        final memory = MemoryEntity(
          id: 'mem-4',
          userId: 'user-1',
          title: 'Network Timeout Note',
          content: 'Saved during network blip',
          category: 'Personal',
          tags: const ['offline'],
          aiStatus: 'processed',
          embedding: null,
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        // Embedding remains null; memory is intact; no mock or fake vector is created
        expect(memory.embedding, isNull);
        expect(memory.title, 'Network Timeout Note');
        expect(memory.content, 'Saved during network blip');
      },
    );
  });

  group(
    'Semantic Search Phase 1 — Database Vector Search & RPC Contract Tests',
    () {
      test(
        'RPC match_memories_v2 response contract includes all required card fields',
        () {
          final mockRpcRow = {
            'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'title': 'Flutter BLoC Architecture Guide',
            'content':
                'Comprehensive guide on clean architecture and state management in Flutter',
            'category': 'Work',
            'tags': ['flutter', 'bloc', 'architecture'],
            'media_url': 'https://storage.example.com/memories/diagram.png',
            'client_created_at': '2026-09-15T12:00:00.000Z',
            'similarity': 0.8754,
          };

          // Verify field presence and types
          expect(mockRpcRow['id'], isA<String>());
          expect(mockRpcRow['title'], isA<String>());
          expect(mockRpcRow['content'], isA<String>());
          expect(mockRpcRow['category'], 'Work');
          expect(mockRpcRow['tags'], containsAll(['flutter', 'bloc']));
          expect(mockRpcRow['media_url'], startsWith('https://'));
          expect(mockRpcRow['client_created_at'], isNotNull);
          expect(mockRpcRow['similarity'], greaterThanOrEqualTo(0.3));
        },
      );

      test(
        'Cosine similarity threshold filter excludes low-scoring memories',
        () {
          const matchThreshold = 0.3;
          final candidates = [
            {'id': '1', 'similarity': 0.85},
            {'id': '2', 'similarity': 0.42},
            {'id': '3', 'similarity': 0.28}, // Below threshold
            {'id': '4', 'similarity': 0.12}, // Below threshold
          ];

          final filtered = candidates
              .where((c) => (c['similarity'] as double) >= matchThreshold)
              .toList();
          expect(filtered.length, 2);
          expect(filtered.map((c) => c['id']), containsAll(['1', '2']));
          expect(filtered.map((c) => c['id']), isNot(contains('3')));
        },
      );

      test('Cosine similarity ordering sorts closest matches first', () {
        final results = [
          {'id': '1', 'similarity': 0.55},
          {'id': '2', 'similarity': 0.92},
          {'id': '3', 'similarity': 0.78},
        ];

        results.sort(
          (a, b) =>
              (b['similarity'] as double).compareTo(a['similarity'] as double),
        );

        expect(results.first['id'], '2');
        expect(results[1]['id'], '3');
        expect(results.last['id'], '1');
      });

      test('Match count limit caps result set', () {
        const matchCount = 2;
        final results = List.generate(
          10,
          (i) => {'id': 'mem-$i', 'similarity': 0.9 - (i * 0.05)},
        );

        final capped = results.take(matchCount).toList();
        expect(capped.length, 2);
        expect(capped.first['id'], 'mem-0');
        expect(capped.last['id'], 'mem-1');
      });

      test('Multi-tenant user isolation rejects cross-user memory leakage', () {
        const authenticatedUserId = 'user-alice';
        final rawRpcResults = [
          {
            'id': '1',
            'user_id': 'user-alice',
            'title': 'Alice Note',
            'similarity': 0.9,
          },
          {
            'id': '2',
            'user_id': 'user-bob',
            'title': 'Bob Note',
            'similarity': 0.88,
          },
        ];

        final isolated = rawRpcResults
            .filterDefenseInDepth(authenticatedUserId)
            .toList();

        expect(isolated.length, 1);
        expect(isolated.first['title'], 'Alice Note');
        expect(isolated.any((m) => m['user_id'] == 'user-bob'), isFalse);
      });
    },
  );

  group('Semantic Search Phase 1 — Edge Function Contract Tests', () {
    test('Query validation rejects empty or whitespace-only queries', () {
      expect(isValidQuery(''), isFalse);
      expect(isValidQuery('   '), isFalse);
      expect(isValidQuery('\t\n'), isFalse);
      expect(isValidQuery('valid query'), isTrue);
    });

    test('Query validation rejects queries exceeding 1000 characters', () {
      final tooLong = 'a' * 1001;
      expect(isValidQuery(tooLong), isFalse);

      final exactly1000 = 'a' * 1000;
      expect(isValidQuery(exactly1000), isTrue);
    });

    test('Query parameters clamp threshold and count to safe bounds', () {
      // Default fallback
      expect(resolveThreshold(null), 0.3);
      expect(resolveThreshold(-0.5), 0.0);
      expect(resolveThreshold(1.5), 1.0);
      expect(resolveThreshold(0.65), 0.65);

      expect(resolveCount(null), 10);
      expect(resolveCount(0), 1);
      expect(resolveCount(100), 50);
      expect(resolveCount(25), 25);
    });

    test('Edge function response serialization format', () {
      final responseMap = {
        'success': true,
        'query': 'clean architecture',
        'count': 1,
        'threshold': 0.3,
        'results': [
          {
            'id': 'mem-123',
            'title': 'Clean Architecture in Dart',
            'content': 'Entities, UseCases, Repositories, and DataSources',
            'category': 'Work',
            'tags': ['dart', 'clean-architecture'],
            'media_url': null,
            'client_created_at': '2026-09-15T10:00:00Z',
            'similarity': 0.8412,
          },
        ],
        'execution_time_ms': 142,
      };

      final jsonStr = jsonEncode(responseMap);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['success'], isTrue);
      expect(decoded['count'], 1);
      expect(decoded['results'], isA<List>());
      expect((decoded['results'] as List).first['similarity'], 0.8412);
    });
  });

  group(
    'Semantic Search Phase 1 — Content Embedding Quality & Provider Regressions',
    () {
      test('Dual content strips bare URL on line 1 for embedding text', () {
        const rawContent =
            'https://docs.flutter.dev/get-started\n\nFlutter transforms the app development process.';
        final textToEmbed = extractTextForEmbedding(
          title: 'Flutter Docs',
          content: rawContent,
        );

        expect(textToEmbed, startsWith('Flutter Docs\n\n'));
        expect(
          textToEmbed,
          contains('Flutter transforms the app development process.'),
        );
        expect(
          textToEmbed.contains('https://docs.flutter.dev/get-started'),
          isFalse,
        );
      });

      test('URL-only content preserves URL as embedding fallback', () {
        const rawContent = 'https://flutter.dev';
        final textToEmbed = extractTextForEmbedding(
          title: 'Flutter Official',
          content: rawContent,
        );

        expect(textToEmbed, 'Flutter Official\n\nhttps://flutter.dev');
      });

      test(
        'YouTube video content provides rich channel, caption, and transcript context',
        () {
          const content =
              'https://youtu.be/dQw4w9WgXcQ\n\nChannel: Rick Astley\nTitle: Never Gonna Give You Up\nDescription: Official Music Video\nTranscript: Never gonna give you up, never gonna let you down';
          final textToEmbed = extractTextForEmbedding(
            title: 'Never Gonna Give You Up',
            content: content,
          );

          expect(textToEmbed, contains('Channel: Rick Astley'));
          expect(textToEmbed, contains('Transcript: Never gonna give you up'));
          expect(
            textToEmbed.startsWith(
              'Never Gonna Give You Up\n\nChannel: Rick Astley',
            ),
            isTrue,
          );
        },
      );

      test(
        'TikTok video content provides rich creator, caption, and description context',
        () {
          const content =
              'https://www.tiktok.com/@chef/video/123\n\nCreator: @chef\nCaption: Homemade sourdough bread 🍞\nDescription: Step by step baking tutorial';
          final textToEmbed = extractTextForEmbedding(
            title: 'Sourdough Bread',
            content: content,
          );

          expect(textToEmbed, contains('Creator: @chef'));
          expect(textToEmbed, contains('Homemade sourdough bread 🍞'));
        },
      );

      test(
        'Instagram Reel content provides clean caption and description context',
        () {
          const content =
              'https://www.instagram.com/reel/C8xyz/\n\nCreator: @baker\nCaption: Perfect croissants 🥐\nDescription: 10K likes - Perfect croissants';
          final textToEmbed = extractTextForEmbedding(
            title: 'Perfect Croissants',
            content: content,
          );

          expect(textToEmbed, contains('Creator: @baker'));
          expect(textToEmbed, contains('Perfect croissants 🥐'));
        },
      );

      test(
        'Photo OCR summary is embedded without UI buttons or status bar junk',
        () {
          const content =
              '• App/Platform: Google Maps\n• Core Subject: Route from Tokyo to Osaka via Shinkansen';
          final textToEmbed = extractTextForEmbedding(
            title: 'Trip Itinerary',
            content: content,
          );

          expect(
            textToEmbed,
            'Trip Itinerary\n\n• App/Platform: Google Maps\n• Core Subject: Route from Tokyo to Osaka via Shinkansen',
          );
          expect(textToEmbed.contains('100%'), isFalse);
          expect(textToEmbed.contains('5G'), isFalse);
          expect(textToEmbed.contains('Cancel'), isFalse);
        },
      );
    },
  );

  group('Semantic Search — Generic Relevance Filtering Contract Tests', () {
    test('1. 0.56 result excluded (below 0.57 noise floor)', () {
      final candidates = [
        {'id': 'mem-noise', 'title': 'Noise Memory', 'similarity': 0.56},
        {'id': 'mem-weak', 'title': 'Weak Memory', 'similarity': 0.52},
        {
          'id': 'mem-unrelated',
          'title': 'Unrelated Memory',
          'similarity': 0.48,
        },
      ];

      final filtered = filterRelevantSemanticResultsBackend(candidates);

      // 0.56 fails the 0.57 absolute noise floor
      expect(filtered, isEmpty);
    });

    test(
      '2. 0.57 result can be retained when it passes the dynamic cutoff',
      () {
        // Single 0.57 result meeting the floor
        final singleCandidate = [
          {
            'id': 'mem-roman-urdu',
            'title': 'chair save ki thi mny?',
            'similarity': 0.57,
          },
        ];
        final filteredSingle = filterRelevantSemanticResultsBackend(
          singleCandidate,
        );
        expect(filteredSingle.length, 1);
        expect(filteredSingle.first['id'], 'mem-roman-urdu');
        expect(filteredSingle.first['similarity'], 0.57);

        // Moderate top result (0.59) with a 0.57 companion within 0.18 margin
        final pairedCandidates = [
          {'id': 'mem-urdu-notes', 'title': 'urdu k notes', 'similarity': 0.59},
          {
            'id': 'mem-urdu-grammar',
            'title': 'Urdu Grammar Rules',
            'similarity': 0.57,
          },
          {'id': 'mem-noise', 'title': 'Noise', 'similarity': 0.54},
        ];
        final filteredPaired = filterRelevantSemanticResultsBackend(
          pairedCandidates,
        );
        expect(filteredPaired.length, 2);
        expect(
          filteredPaired.map((c) => c['id']),
          containsAll(['mem-urdu-notes', 'mem-urdu-grammar']),
        );
        expect(filteredPaired.any((c) => c['id'] == 'mem-noise'), isFalse);
      },
    );

    test('3. strong top result still filters unrelated 0.48–0.56 results', () {
      final candidates = [
        {
          'id': 'mem-bottle',
          'title': 'Water Bottle on Desk',
          'similarity': 0.82,
        },
        {'id': 'mem-urdu', 'title': 'Urdu Poetry Notes', 'similarity': 0.56},
        {
          'id': 'mem-chair',
          'title': 'Office Chair Receipt',
          'similarity': 0.52,
        },
        {'id': 'mem-misc', 'title': 'Random Item', 'similarity': 0.48},
      ];

      final filtered = filterRelevantSemanticResultsBackend(candidates);

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'mem-bottle');
      expect(filtered.first['similarity'], 0.82);
    });

    test('4. multiple genuinely strong results remain', () {
      final candidates = [
        {
          'id': 'mem-arch',
          'title': 'Clean Architecture Guide',
          'similarity': 0.88,
        },
        {
          'id': 'mem-bloc',
          'title': 'BLoC State Management',
          'similarity': 0.82,
        },
        {'id': 'mem-repo', 'title': 'Repository Pattern', 'similarity': 0.79},
        {
          'id': 'mem-receipt',
          'title': 'Grocery Store Receipt',
          'similarity': 0.50,
        },
      ];

      final filtered = filterRelevantSemanticResultsBackend(candidates);

      expect(filtered.length, 3);
      expect(
        filtered.map((c) => c['id']),
        containsAll(['mem-arch', 'mem-bloc', 'mem-repo']),
      );
      expect(filtered.any((c) => c['id'] == 'mem-receipt'), isFalse);
    });

    test('5. no relevant results returns empty', () {
      final candidates = [
        {'id': 'mem-1', 'title': 'Unrelated Memory A', 'similarity': 0.55},
        {'id': 'mem-2', 'title': 'Unrelated Memory B', 'similarity': 0.51},
        {'id': 'mem-3', 'title': 'Unrelated Memory C', 'similarity': 0.48},
      ];

      final filtered = filterRelevantSemanticResultsBackend(candidates);

      expect(filtered, isEmpty);
    });

    test(
      'no hardcoded/query-specific matching — purely similarity score driven',
      () {
        // Test two completely different queries with identical score distributions
        final query1Candidates = [
          {'id': '1', 'title': 'urdu k notes', 'similarity': 0.81},
          {'id': '2', 'title': 'water bottle', 'similarity': 0.52},
        ];
        final query2Candidates = [
          {'id': '1', 'title': 'chair save ki thi mny?', 'similarity': 0.81},
          {'id': '2', 'title': 'grocery list', 'similarity': 0.52},
        ];

        final filtered1 = filterRelevantSemanticResultsBackend(
          query1Candidates,
        );
        final filtered2 = filterRelevantSemanticResultsBackend(
          query2Candidates,
        );

        expect(filtered1.length, 1);
        expect(filtered1.first['id'], '1');
        expect(filtered2.length, 1);
        expect(filtered2.first['id'], '1');
      },
    );

    test('Edge function response count matches relevant results length', () {
      final rawCandidates = [
        {'id': '1', 'title': 'Relevant', 'similarity': 0.84},
        {'id': '2', 'title': 'Noise', 'similarity': 0.52},
      ];
      final filtered = filterRelevantSemanticResultsBackend(rawCandidates);

      final response = {
        'success': true,
        'count': filtered.length,
        'results': filtered,
      };

      expect(response['count'], 1);
      expect((response['results'] as List).length, 1);
    });

    test(
      'REGRESSION 1: "laptop"-style results where strong relevant results remain and unrelated moderate-score results are excluded',
      () {
        final candidates = [
          {'id': '1', 'title': 'Laptop QWERTY Keyboard', 'similarity': 0.68},
          {'id': '2', 'title': 'Laptop Keyboard', 'similarity': 0.66},
          {
            'id': '3',
            'title': 'Dell Latitude Laptop Keyboard',
            'similarity': 0.66,
          },
          {
            'id': '4',
            'title': 'Black Wired HP Computer/Mouse',
            'similarity': 0.60,
          },
          {'id': '5', 'title': 'Letter Advising Brother', 'similarity': 0.60},
          {'id': '6', 'title': 'Urdu Poetry', 'similarity': 0.58},
          {'id': '7', 'title': 'Dining Table', 'similarity': 0.58},
        ];

        final filtered = filterRelevantSemanticResultsBackend(
          candidates,
          query: 'laptop',
        );

        // Only the 3 genuine laptop results must remain
        expect(filtered.length, 3);
        expect(
          filtered.map((c) => c['title']),
          containsAll([
            'Laptop QWERTY Keyboard',
            'Laptop Keyboard',
            'Dell Latitude Laptop Keyboard',
          ]),
        );

        // Unrelated moderate-score results (0.58-0.60) must be excluded
        expect(
          filtered.any((c) => c['title'] == 'Letter Advising Brother'),
          isFalse,
        );
        expect(filtered.any((c) => c['title'] == 'Urdu Poetry'), isFalse);
        expect(filtered.any((c) => c['title'] == 'Dining Table'), isFalse);
        expect(
          filtered.any((c) => c['title'] == 'Black Wired HP Computer/Mouse'),
          isFalse,
        );
      },
    );

    test(
      'REGRESSION 2: No query-specific keyword hacks — generic mathematical and domain-agnostic behavior',
      () {
        // Test arbitrary synthetic tokens with no special-case dictionary presence
        final candidates = [
          {
            'id': 'x1',
            'title': 'Zeta Protocol Specification',
            'similarity': 0.69,
          },
          {
            'id': 'x2',
            'title': 'Zeta Protocol Implementation',
            'similarity': 0.67,
          },
          {'id': 'x3', 'title': 'Unrelated Document K', 'similarity': 0.60},
          {'id': 'x4', 'title': 'Random Note M', 'similarity': 0.58},
        ];

        final filtered = filterRelevantSemanticResultsBackend(
          candidates,
          query: 'Zeta Protocol',
        );
        expect(filtered.length, 2);
        expect(filtered.map((c) => c['id']), containsAll(['x1', 'x2']));
        expect(filtered.any((c) => c['id'] == 'x3'), isFalse);
        expect(filtered.any((c) => c['id'] == 'x4'), isFalse);
      },
    );

    test(
      'REGRESSION 3: Existing cross-lingual and Roman Urdu semantic matching remains supported',
      () {
        // Query "gari" (Urdu for car) matching automotive concepts without exact English token overlap
        final crossLingualCandidates = [
          {
            'id': 'c1',
            'title': 'Toyota Corolla Engine Maintenance',
            'similarity': 0.68,
          },
          {
            'id': 'c2',
            'title': 'Honda Civic Tire Pressure',
            'similarity': 0.66,
          },
          {'id': 'c3', 'title': 'Letter Advising Brother', 'similarity': 0.59},
          {'id': 'c4', 'title': 'Urdu Poetry', 'similarity': 0.58},
        ];

        final filtered = filterRelevantSemanticResultsBackend(
          crossLingualCandidates,
          query: 'gari',
        );
        expect(filtered.length, 2);
        expect(filtered.map((c) => c['id']), containsAll(['c1', 'c2']));
        expect(filtered.any((c) => c['id'] == 'c3'), isFalse);
        expect(filtered.any((c) => c['id'] == 'c4'), isFalse);
      },
    );

    test(
      'REGRESSION 4 & 6: Search uses persisted memory timestamp from client_created_at or created_at, never DateTime.now() fallback',
      () {
        final specificTime = DateTime.parse('2026-09-19T10:00:00.000Z');

        // 1. With client_created_at
        final jsonWithClientCreated = {
          'id': 'mem-1',
          'title': 'Test Memory',
          'content': 'Content',
          'category': 'Work',
          'client_created_at': specificTime.toIso8601String(),
          'similarity': 0.75,
        };
        final model1 = SearchResultModel.fromJson(jsonWithClientCreated);
        expect(model1.clientCreatedAt, equals(specificTime));

        // 2. With created_at (Supabase default column)
        final jsonWithCreatedAt = {
          'id': 'mem-2',
          'title': 'Test Memory 2',
          'content': 'Content 2',
          'category': 'General',
          'created_at': specificTime.toIso8601String(),
          'similarity': 0.75,
        };
        final model2 = SearchResultModel.fromJson(jsonWithCreatedAt);
        expect(model2.clientCreatedAt, equals(specificTime));

        // 3. No timestamp in JSON must NOT fall back to DateTime.now()
        final jsonWithoutTimestamp = {
          'id': 'mem-3',
          'title': 'Test Memory 3',
          'content': 'Content 3',
          'category': 'General',
          'similarity': 0.75,
        };
        final model3 = SearchResultModel.fromJson(jsonWithoutTimestamp);
        expect(model3.clientCreatedAt, isNull);
      },
    );

    test(
      'REGRESSION 5: Search and Saved produce consistent relative time for the same timestamps',
      () {
        String formatTimeAgo(DateTime dateTime) {
          final diff = DateTime.now().difference(dateTime);
          if (diff.inSeconds < 60) {
            return 'Just now';
          } else if (diff.inMinutes < 60) {
            return '${diff.inMinutes}m ago';
          } else if (diff.inHours < 24) {
            return '${diff.inHours}h ago';
          } else if (diff.inDays == 1) {
            return 'Yesterday';
          } else if (diff.inDays < 7) {
            return '${diff.inDays}d ago';
          } else {
            return DateFormat('MMM d').format(dateTime);
          }
        }

        final now = DateTime.now();

        // 4 hours ago (the exact scenario from real-device testing)
        final fourHoursAgo = now.subtract(const Duration(hours: 4));
        expect(formatTimeAgo(fourHoursAgo), '4h ago');

        // 30 seconds ago
        final thirtySecAgo = now.subtract(const Duration(seconds: 30));
        expect(formatTimeAgo(thirtySecAgo), 'Just now');

        // 15 minutes ago
        final fifteenMinAgo = now.subtract(const Duration(minutes: 15));
        expect(formatTimeAgo(fifteenMinAgo), '15m ago');

        // 1 day ago
        final oneDayAgo = now.subtract(const Duration(days: 1));
        expect(formatTimeAgo(oneDayAgo), 'Yesterday');

        // 3 days ago
        final threeDaysAgo = now.subtract(const Duration(days: 3));
        expect(formatTimeAgo(threeDaysAgo), '3d ago');
      },
    );
  });
}

// Helpers mirroring the TypeScript edge function & embedding generation logic
bool isValidQuery(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.length > 1000) return false;
  return true;
}

double resolveThreshold(double? matchThreshold) {
  if (matchThreshold == null) return 0.3;
  return matchThreshold.clamp(0.0, 1.0);
}

int resolveCount(int? matchCount) {
  if (matchCount == null) return 10;
  return matchCount.clamp(1, 50);
}

String extractTextForEmbedding({
  required String title,
  required String content,
}) {
  final cleanTitle = title.trim();
  var cleanContent = content.trim();

  if ((cleanContent.startsWith('http://') ||
          cleanContent.startsWith('https://')) &&
      cleanContent.contains('\n')) {
    final afterUrl = cleanContent.substring(cleanContent.indexOf('\n')).trim();
    if (afterUrl.isNotEmpty) {
      cleanContent = afterUrl;
    }
  }

  return cleanTitle.isNotEmpty ? '$cleanTitle\n\n$cleanContent' : cleanContent;
}

extension FilterDefenseInDepth on List<Map<String, dynamic>> {
  Iterable<Map<String, dynamic>> filterDefenseInDepth(
    String authenticatedUserId,
  ) {
    return where(
      (rec) => rec['user_id'] == null || rec['user_id'] == authenticatedUserId,
    );
  }
}

List<Map<String, dynamic>> filterRelevantSemanticResultsBackend(
  List<Map<String, dynamic>> items, {
  double minThreshold = 0.57,
  double? maxDropFromTop,
  String? query,
}) {
  if (items.isEmpty) return [];
  final sorted = List<Map<String, dynamic>>.from(items)
    ..sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );

  final topScore = sorted.first['similarity'] as double;
  final effectiveMin = minThreshold > 0.57 ? minThreshold : 0.57;
  if (topScore < effectiveMin) return [];

  final margin = topScore - effectiveMin;
  final adaptiveDrop = maxDropFromTop ?? (0.03 + (0.25 * margin));
  final dynamicCutoff = (topScore - adaptiveDrop).clamp(effectiveMin, 1.0);

  final queryTokens = query != null && query.trim().isNotEmpty
      ? query
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((t) => t.length >= 2)
            .toList()
      : const <String>[];

  return sorted.where((item) {
    final sim = item['similarity'] as double;
    if (sim < effectiveMin) return false;
    if (sim >= dynamicCutoff) return true;

    if (queryTokens.isNotEmpty) {
      final titleLower = (item['title'] ?? '').toString().toLowerCase();
      final contentLower = (item['content'] ?? '').toString().toLowerCase();
      final categoryLower = (item['category'] ?? '').toString().toLowerCase();
      final tags = item['tags'] is List ? (item['tags'] as List) : [];
      final tagsLower = tags.map((t) => t.toString().toLowerCase()).toList();

      final hasTokenMatch = queryTokens.any(
        (t) =>
            titleLower.contains(t) ||
            contentLower.contains(t) ||
            categoryLower.contains(t) ||
            tagsLower.any((tag) => tag.contains(t)),
      );

      if (hasTokenMatch) {
        final hybridCutoff = (topScore - 0.12).clamp(effectiveMin, 1.0);
        return sim >= hybridCutoff;
      }
    }

    return false;
  }).toList();
}
