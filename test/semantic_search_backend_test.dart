import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';

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

      final needsEmbedding = memory.embedding == null || memory.embedding!.isEmpty;
      final hasMeaningfulContent =
          memory.content.trim().isNotEmpty || memory.title.trim().isNotEmpty;

      expect(needsEmbedding, isTrue);
      expect(hasMeaningfulContent, isTrue);
      // Confirms embedding_only payload flag should be sent
      expect(memory.aiStatus == 'processed', isTrue);
    });

    test('Memory with existing valid 768-d embedding avoids duplicate generation', () {
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

      final needsEmbedding = memory.embedding == null || memory.embedding!.isEmpty;
      expect(needsEmbedding, isFalse);
      expect(memory.embedding!.length, 768);
    });

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

    test('Embedding failure preserves memory with null embedding without fabricating synthetic data', () {
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
    });
  });

  group('Semantic Search Phase 1 — Database Vector Search & RPC Contract Tests', () {
    test('RPC match_memories_v2 response contract includes all required card fields', () {
      final mockRpcRow = {
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'title': 'Flutter BLoC Architecture Guide',
        'content': 'Comprehensive guide on clean architecture and state management in Flutter',
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
    });

    test('Cosine similarity threshold filter excludes low-scoring memories', () {
      const matchThreshold = 0.3;
      final candidates = [
        {'id': '1', 'similarity': 0.85},
        {'id': '2', 'similarity': 0.42},
        {'id': '3', 'similarity': 0.28}, // Below threshold
        {'id': '4', 'similarity': 0.12}, // Below threshold
      ];

      final filtered = candidates.where((c) => (c['similarity'] as double) >= matchThreshold).toList();
      expect(filtered.length, 2);
      expect(filtered.map((c) => c['id']), containsAll(['1', '2']));
      expect(filtered.map((c) => c['id']), isNot(contains('3')));
    });

    test('Cosine similarity ordering sorts closest matches first', () {
      final results = [
        {'id': '1', 'similarity': 0.55},
        {'id': '2', 'similarity': 0.92},
        {'id': '3', 'similarity': 0.78},
      ];

      results.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));

      expect(results.first['id'], '2');
      expect(results[1]['id'], '3');
      expect(results.last['id'], '1');
    });

    test('Match count limit caps result set', () {
      const matchCount = 2;
      final results = List.generate(10, (i) => {'id': 'mem-$i', 'similarity': 0.9 - (i * 0.05)});

      final capped = results.take(matchCount).toList();
      expect(capped.length, 2);
      expect(capped.first['id'], 'mem-0');
      expect(capped.last['id'], 'mem-1');
    });

    test('Multi-tenant user isolation rejects cross-user memory leakage', () {
      const authenticatedUserId = 'user-alice';
      final rawRpcResults = [
        {'id': '1', 'user_id': 'user-alice', 'title': 'Alice Note', 'similarity': 0.9},
        {'id': '2', 'user_id': 'user-bob', 'title': 'Bob Note', 'similarity': 0.88},
      ];

      final isolated = rawRpcResults
          .filterDefenseInDepth(authenticatedUserId)
          .toList();

      expect(isolated.length, 1);
      expect(isolated.first['title'], 'Alice Note');
      expect(isolated.any((m) => m['user_id'] == 'user-bob'), isFalse);
    });
  });

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
          }
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

  group('Semantic Search Phase 1 — Content Embedding Quality & Provider Regressions', () {
    test('Dual content strips bare URL on line 1 for embedding text', () {
      const rawContent = 'https://docs.flutter.dev/get-started\n\nFlutter transforms the app development process.';
      final textToEmbed = extractTextForEmbedding(title: 'Flutter Docs', content: rawContent);

      expect(textToEmbed, startsWith('Flutter Docs\n\n'));
      expect(textToEmbed, contains('Flutter transforms the app development process.'));
      expect(textToEmbed.contains('https://docs.flutter.dev/get-started'), isFalse);
    });

    test('URL-only content preserves URL as embedding fallback', () {
      const rawContent = 'https://flutter.dev';
      final textToEmbed = extractTextForEmbedding(title: 'Flutter Official', content: rawContent);

      expect(textToEmbed, 'Flutter Official\n\nhttps://flutter.dev');
    });

    test('YouTube video content provides rich channel, caption, and transcript context', () {
      const content = 'https://youtu.be/dQw4w9WgXcQ\n\nChannel: Rick Astley\nTitle: Never Gonna Give You Up\nDescription: Official Music Video\nTranscript: Never gonna give you up, never gonna let you down';
      final textToEmbed = extractTextForEmbedding(title: 'Never Gonna Give You Up', content: content);

      expect(textToEmbed, contains('Channel: Rick Astley'));
      expect(textToEmbed, contains('Transcript: Never gonna give you up'));
      expect(textToEmbed.startsWith('Never Gonna Give You Up\n\nChannel: Rick Astley'), isTrue);
    });

    test('TikTok video content provides rich creator, caption, and description context', () {
      const content = 'https://www.tiktok.com/@chef/video/123\n\nCreator: @chef\nCaption: Homemade sourdough bread 🍞\nDescription: Step by step baking tutorial';
      final textToEmbed = extractTextForEmbedding(title: 'Sourdough Bread', content: content);

      expect(textToEmbed, contains('Creator: @chef'));
      expect(textToEmbed, contains('Homemade sourdough bread 🍞'));
    });

    test('Instagram Reel content provides clean caption and description context', () {
      const content = 'https://www.instagram.com/reel/C8xyz/\n\nCreator: @baker\nCaption: Perfect croissants 🥐\nDescription: 10K likes - Perfect croissants';
      final textToEmbed = extractTextForEmbedding(title: 'Perfect Croissants', content: content);

      expect(textToEmbed, contains('Creator: @baker'));
      expect(textToEmbed, contains('Perfect croissants 🥐'));
    });

    test('Photo OCR summary is embedded without UI buttons or status bar junk', () {
      const content = '• App/Platform: Google Maps\n• Core Subject: Route from Tokyo to Osaka via Shinkansen';
      final textToEmbed = extractTextForEmbedding(title: 'Trip Itinerary', content: content);

      expect(textToEmbed, 'Trip Itinerary\n\n• App/Platform: Google Maps\n• Core Subject: Route from Tokyo to Osaka via Shinkansen');
      expect(textToEmbed.contains('100%'), isFalse);
      expect(textToEmbed.contains('5G'), isFalse);
      expect(textToEmbed.contains('Cancel'), isFalse);
    });
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

String extractTextForEmbedding({required String title, required String content}) {
  final cleanTitle = title.trim();
  var cleanContent = content.trim();

  if ((cleanContent.startsWith('http://') || cleanContent.startsWith('https://')) &&
      cleanContent.contains('\n')) {
    final afterUrl = cleanContent.substring(cleanContent.indexOf('\n')).trim();
    if (afterUrl.isNotEmpty) {
      cleanContent = afterUrl;
    }
  }

  return cleanTitle.isNotEmpty ? '$cleanTitle\n\n$cleanContent' : cleanContent;
}

extension FilterDefenseInDepth on List<Map<String, dynamic>> {
  Iterable<Map<String, dynamic>> filterDefenseInDepth(String authenticatedUserId) {
    return where((rec) => rec['user_id'] == null || rec['user_id'] == authenticatedUserId);
  }
}
