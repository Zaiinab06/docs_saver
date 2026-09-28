import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/services/related_memory_matcher.dart';

MemoryEntity memory({
  required String id,
  required String userId,
  required String title,
  required String category,
  List<String> tags = const [],
  List<double>? embedding,
  required DateTime createdAt,
}) {
  return MemoryEntity(
    id: id,
    userId: userId,
    title: title,
    category: category,
    tags: tags,
    content: title,
    embedding: embedding,
    clientCreatedAt: createdAt,
    clientUpdatedAt: createdAt,
    serverUpdatedAt: createdAt,
  );
}

void main() {
  const matcher = RelatedMemoryMatcher();
  final baseDate = DateTime(2026, 9, 21);

  test('ranks actual same-user memories by shared tags then category', () {
    final source = memory(
      id: 'source',
      userId: 'user-a',
      title: 'Source',
      category: 'Work',
      tags: const ['Flutter', 'Architecture'],
      createdAt: baseDate,
    );
    final tagMatch = memory(
      id: 'tag-match',
      userId: 'user-a',
      title: 'Tag match',
      category: 'Personal',
      tags: const ['architecture', 'flutter'],
      createdAt: baseDate.subtract(const Duration(days: 1)),
    );
    final categoryMatch = memory(
      id: 'category-match',
      userId: 'user-a',
      title: 'Category match',
      category: 'Work',
      tags: const ['architecture'],
      createdAt: baseDate.subtract(const Duration(days: 2)),
    );

    final result = matcher.find(
      memory: source,
      candidates: [source, categoryMatch, tagMatch],
      userId: 'user-a',
    );

    expect(result.map((item) => item.id), ['tag-match', 'category-match']);
  });

  test('excludes the current memory and records owned by another user', () {
    final source = memory(
      id: 'source',
      userId: 'user-a',
      title: 'Source',
      category: 'Study',
      tags: const ['dart'],
      createdAt: baseDate,
    );
    final otherUser = memory(
      id: 'other-user',
      userId: 'user-b',
      title: 'Other user',
      category: 'Study',
      tags: const ['dart'],
      createdAt: baseDate,
    );

    final result = matcher.find(
      memory: source,
      candidates: [source, otherUser],
      userId: 'user-a',
    );

    expect(result, isEmpty);
  });

  test('requires relevant content with a category tag match', () {
    final source = memory(
      id: 'source',
      userId: 'user-a',
      title: 'Study source',
      category: 'Study',
      tags: const ['study-notes'],
      createdAt: baseDate,
    );
    final sameCategory = memory(
      id: 'same-category',
      userId: 'user-a',
      title: 'Another study note',
      category: ' study ',
      tags: const ['study-notes'],
      createdAt: baseDate.subtract(const Duration(days: 1)),
    );
    final weakMetadataOnly = memory(
      id: 'weak',
      userId: 'user-a',
      title: 'Unrelated work note',
      category: 'Work',
      tags: const ['pdf'],
      createdAt: baseDate,
    );
    final unrelatedSameCategory = memory(
      id: 'unrelated-same-category',
      userId: 'user-a',
      title: 'Unrelated astronomy observation',
      category: 'Study',
      tags: const ['study'],
      createdAt: baseDate,
    );

    final result = matcher.find(
      memory: source,
      candidates: [sameCategory, unrelatedSameCategory, weakMetadataOnly],
      userId: 'user-a',
    );

    expect(result.map((item) => item.id), ['same-category']);
  });

  test('rejects generic category and generic-tag matches', () {
    final source = memory(
      id: 'health-source',
      userId: 'user-a',
      title: 'Human foot on brown carpet',
      category: 'Health & Fitness',
      tags: const ['health'],
      createdAt: baseDate,
    );
    final unrelated = memory(
      id: 'keyboard',
      userId: 'user-a',
      title: 'Laptop QWERTY Keyboard Close-up',
      category: 'Health & Fitness',
      tags: const ['health'],
      createdAt: baseDate,
    );

    expect(
      matcher.find(memory: source, candidates: [unrelated], userId: 'user-a'),
      isEmpty,
    );
  });

  test(
    'reports exact evidence and rejects one-tag or category-only matches',
    () {
      final source = memory(
        id: 'study-source',
        userId: 'user-a',
        title: 'Study source',
        category: 'Study',
        tags: const ['research', 'dart'],
        createdAt: baseDate,
      );
      final strongMatch = memory(
        id: 'strong',
        userId: 'user-a',
        title: 'Study research',
        category: 'Study',
        tags: const ['research', 'dart'],
        createdAt: baseDate.subtract(const Duration(days: 1)),
      );
      final oneTagMatch = memory(
        id: 'one-tag',
        userId: 'user-a',
        title: 'Health record',
        category: 'Health & Fitness',
        tags: const ['research'],
        createdAt: baseDate,
      );
      final categoryOnly = memory(
        id: 'category-only',
        userId: 'user-a',
        title: 'Another study',
        category: 'Study',
        tags: const ['document'],
        createdAt: baseDate,
      );

      final matches = matcher.matches(
        memory: source,
        candidates: [strongMatch, oneTagMatch, categoryOnly],
        userId: 'user-a',
      );

      expect(matches.map((match) => match.memory.id), ['strong']);
      expect(matches.single.sharedTags, {'research', 'dart'});
      expect(matches.single.sameCategory, isTrue);
    },
  );

  test(
    'keeps distinct records with duplicate titles but removes repeated IDs',
    () {
      final source = memory(
        id: 'source',
        userId: 'user-a',
        title: 'SnapSplit report',
        category: 'Study',
        tags: const ['research'],
        createdAt: baseDate,
      );
      final firstReport = memory(
        id: 'report-1',
        userId: 'user-a',
        title: 'SnapSplit report',
        category: 'Study',
        tags: const ['research'],
        createdAt: baseDate.subtract(const Duration(days: 1)),
      );
      final secondReport = memory(
        id: 'report-2',
        userId: 'user-a',
        title: 'SnapSplit report',
        category: 'Study',
        tags: const ['research'],
        createdAt: baseDate.subtract(const Duration(days: 2)),
      );

      final result = matcher.find(
        memory: source,
        candidates: [firstReport, firstReport, secondReport],
        userId: 'user-a',
      );

      expect(result.map((item) => item.id), ['report-1', 'report-2']);
    },
  );

  test('matches candidates with vector cosine similarity >= 0.65', () {
    final source = memory(
      id: 'vec-source',
      userId: 'user-a',
      title: 'Machine learning fundamentals',
      category: 'Study',
      embedding: const [1.0, 0.0, 0.0],
      createdAt: baseDate,
    );
    final closeCandidate = memory(
      id: 'vec-match',
      userId: 'user-a',
      title: 'Deep learning concepts',
      category: 'Work',
      // Cosine similarity with [1, 0, 0] is 0.8 / sqrt(0.8^2 + 0.6^2) = 0.8 / 1.0 = 0.80 (> 0.65)
      embedding: const [0.8, 0.6, 0.0],
      createdAt: baseDate.subtract(const Duration(days: 1)),
    );
    final distantCandidate = memory(
      id: 'vec-distant',
      userId: 'user-a',
      title: 'Baking sourdough bread',
      category: 'Food',
      // Cosine similarity with [1, 0, 0] is 0.1 / sqrt(0.1^2 + 0.99^2) ~= 0.1 (< 0.65)
      embedding: const [0.1, 0.99, 0.0],
      createdAt: baseDate.subtract(const Duration(days: 2)),
    );

    final matches = matcher.matches(
      memory: source,
      candidates: [closeCandidate, distantCandidate],
      userId: 'user-a',
    );

    expect(matches.map((m) => m.memory.id), ['vec-match']);
    expect(matches.single.similarity, closeTo(0.80, 0.01));
  });

  test('returns empty list and avoids arbitrary defaults when no semantic match exists', () {
    final source = memory(
      id: 'isolated-memory',
      userId: 'user-a',
      title: 'Isolated topic',
      category: 'General',
      tags: const [],
      createdAt: baseDate,
    );
    final arbitraryCandidate1 = memory(
      id: 'arbitrary-1',
      userId: 'user-a',
      title: 'Completely different item',
      category: 'Work',
      tags: const ['different'],
      createdAt: baseDate.subtract(const Duration(days: 1)),
    );
    final arbitraryCandidate2 = memory(
      id: 'arbitrary-2',
      userId: 'user-a',
      title: 'Another unrelated note',
      category: 'Personal',
      tags: const ['random'],
      createdAt: baseDate.subtract(const Duration(days: 2)),
    );

    final matches = matcher.matches(
      memory: source,
      candidates: [arbitraryCandidate1, arbitraryCandidate2],
      userId: 'user-a',
    );

    // Strict relevance: MUST be empty, never picking the first memory arbitrarily
    expect(matches, isEmpty);
  });
}

