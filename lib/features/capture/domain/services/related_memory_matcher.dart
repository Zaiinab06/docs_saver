import '../entities/memory_entity.dart';

class RelatedMemoryMatcher {
  const RelatedMemoryMatcher();

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
  };

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
              final score = (sharedTags.length * 3) + (sameCategory ? 1 : 0);
              return RelatedMemoryMatch(
                memory: candidate,
                sharedTags: sharedTags,
                sameCategory: sameCategory,
                score: score,
              );
            })
            .where(
              (match) =>
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
  final int score;

  const RelatedMemoryMatch({
    required this.memory,
    required this.sharedTags,
    required this.sameCategory,
    required this.score,
  });
}
