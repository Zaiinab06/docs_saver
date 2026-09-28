import 'dart:math' as math;
import '../entities/memory_entity.dart';

class RelatedMemoryMatcher {
  const RelatedMemoryMatcher();

  /// Minimum cosine similarity threshold for vector-based semantic relevance.
  static const double minCosineSimilarityThreshold = 0.65;

  static const _nonSemanticTags = {
    'audio',
    'document',
    'image',
    'pdf',
    'photo',
    'picture',
    'pin',
    'pinned',
    'voice',
    'fitness',
    'general',
    'health',
    'personal',
    'study',
    'travel',
    'work',
  };

  /// Calculates cosine similarity between two embedding vectors.
  /// Returns 0.0 if either vector is null, empty, or dimensions do not match.
  static double cosineSimilarity(List<double>? a, List<double>? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty || a.length != b.length) {
      return 0.0;
    }
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  List<MemoryEntity> find({
    required MemoryEntity memory,
    required Iterable<MemoryEntity> candidates,
    required String userId,
    int limit = 5,
  }) {
    return matches(
      memory: memory,
      candidates: candidates,
      userId: userId,
      limit: limit,
    ).map((match) => match.memory).toList();
  }

  List<RelatedMemoryMatch> matches({
    required MemoryEntity memory,
    required Iterable<MemoryEntity> candidates,
    required String userId,
    int limit = 5,
  }) {
    if (userId.isEmpty || memory.userId != userId || limit <= 0) {
      return const [];
    }

    final memoryTags = _meaningfulTags(memory.tags);
    final seenIds = <String>{};
    final related =
        candidates
            .where(
              (candidate) =>
                  candidate.id != memory.id &&
                  candidate.userId == userId &&
                  seenIds.add(candidate.id),
            )
            .map((candidate) {
              final sharedTags = _meaningfulTags(
                candidate.tags,
              ).intersection(memoryTags);
              final sameCategory =
                  memory.category.isNotEmpty &&
                  _normalize(memory.category) == _normalize(candidate.category);
              final similarity = cosineSimilarity(
                memory.embedding,
                candidate.embedding,
              );

              final vectorScore =
                  similarity >= minCosineSimilarityThreshold
                      ? (similarity * 10).round()
                      : 0;
              final tagScore = sharedTags.length * 3;
              final categoryScore = sameCategory ? 1 : 0;
              final score = vectorScore + tagScore + categoryScore;

              return RelatedMemoryMatch(
                memory: candidate,
                sharedTags: sharedTags,
                sameCategory: sameCategory,
                similarity: similarity,
                score: score,
              );
            })
            .where(
              (match) =>
                  match.similarity >= minCosineSimilarityThreshold ||
                  match.sharedTags.length >= 2 ||
                  (match.sharedTags.isNotEmpty && match.sameCategory),
            )
            .toList()
          ..sort((a, b) {
            final scoreComparison = b.score.compareTo(a.score);
            if (scoreComparison != 0) return scoreComparison;
            return b.memory.clientCreatedAt.compareTo(a.memory.clientCreatedAt);
          });

    return related.take(limit).toList();
  }

  Set<String> _meaningfulTags(Iterable<String> tags) {
    return tags
        .map(_normalize)
        .where((tag) => tag.isNotEmpty && !_nonSemanticTags.contains(tag))
        .toSet();
  }

  String _normalize(String value) => value.trim().toLowerCase();
}

class RelatedMemoryMatch {
  final MemoryEntity memory;
  final Set<String> sharedTags;
  final bool sameCategory;
  final double similarity;
  final int score;

  const RelatedMemoryMatch({
    required this.memory,
    required this.sharedTags,
    required this.sameCategory,
    this.similarity = 0.0,
    required this.score,
  });
}
