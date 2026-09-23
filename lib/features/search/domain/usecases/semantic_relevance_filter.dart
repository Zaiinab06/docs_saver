import '../entities/search_result_item.dart';

/// Generic semantic relevance and reranking filter for dense vector search results.
///
/// In Gemini 768-dimensional embedding space (gemini-embedding-2-preview), unrelated texts
/// naturally exhibit background cosine similarities between ~0.48 and ~0.60.
///
/// This filter implements a generic, query-agnostic mathematical strategy:
/// 1. [minSimilarityThreshold] (0.57): The absolute noise floor. If the top match
///    does not reach this threshold, the query has no genuinely relevant results.
/// 2. Adaptive dynamic cutoff: Instead of a static subtractive margin (e.g. 0.18) which
///    drops straight into the noise floor for moderate top scores (e.g. top=0.68 -> cutoff 0.57),
///    the allowable drop scales with the top score's elevation above the noise floor:
///      allowedDrop = 0.03 + 0.25 * (topScore - noiseFloor)
///    - For top=0.59: drop is 0.035 -> cutoff 0.57 (retains 0.57 companion)
///    - For top=0.68: drop is 0.0575 -> cutoff 0.6225 (retains 0.66, rejects 0.58–0.60 noise)
///    - For top=0.88: drop is 0.1075 -> cutoff 0.7725 (retains 0.79+, rejects 0.50 noise)
/// 3. Hybrid token relevance: If query is provided, candidates with confirmed token
///    matches in title/tags/category/content are granted an extended margin (up to 0.12 from top)
///    provided they stay strictly above the absolute noise floor.
/// 4. Offline keyword search results are preserved verbatim without similarity filtering.
class SemanticRelevanceFilter {
  /// Baseline noise floor for Gemini 768-d embeddings.
  static const double minSimilarityThreshold = 0.57;

  /// Maximum allowed score drop from the top result (reference baseline).
  static const double maxDropFromTop = 0.18;

  /// Filters [items] by generic semantic relevance based on similarity scores
  /// and optional hybrid token relevance.
  static List<SearchResultItem> filter(
    List<SearchResultItem> items, {
    String? query,
    double minThreshold = minSimilarityThreshold,
    double? maxDrop,
  }) {
    if (items.isEmpty) return const [];

    // Offline keyword results are never filtered by similarity
    final hasOffline = items.any((item) => item.isOfflineResult);
    if (hasOffline) {
      return items;
    }

    final semanticItems = items.where((item) => item.similarity > 0).toList();
    if (semanticItems.isEmpty) {
      return items;
    }

    // Sort descending by similarity
    semanticItems.sort((a, b) => b.similarity.compareTo(a.similarity));

    final topScore = semanticItems.first.similarity;
    final effectiveMin = minThreshold > 0.57 ? minThreshold : 0.57;

    // If top match fails to reach the noise floor, no results are sufficiently relevant
    if (topScore < effectiveMin) {
      return const [];
    }

    final margin = topScore - effectiveMin;
    final adaptiveDrop = maxDrop ?? (0.03 + (0.25 * margin));
    final dynamicCutoff = (topScore - adaptiveDrop).clamp(effectiveMin, 1.0);

    // Extract query tokens if query is provided
    final queryTokens = query != null && query.trim().isNotEmpty
        ? query
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), ' ')
              .split(RegExp(r'\s+'))
              .where((t) => t.length >= 2)
              .toList()
        : const <String>[];

    return semanticItems.where((item) {
      // 1. Must meet the absolute noise floor
      if (item.similarity < effectiveMin) {
        return false;
      }

      // 2. Meets dense dynamic cutoff
      if (item.similarity >= dynamicCutoff) {
        return true;
      }

      // 3. Hybrid token match fallback
      if (queryTokens.isNotEmpty) {
        final titleLower = item.title.toLowerCase();
        final contentLower = item.content.toLowerCase();
        final categoryLower = item.category.toLowerCase();
        final tagsLower = item.tags.map((t) => t.toLowerCase()).toList();

        final hasTokenMatch = queryTokens.any(
          (t) =>
              titleLower.contains(t) ||
              contentLower.contains(t) ||
              categoryLower.contains(t) ||
              tagsLower.any((tag) => tag.contains(t)),
        );

        if (hasTokenMatch) {
          final hybridCutoff = (topScore - 0.12).clamp(effectiveMin, 1.0);
          return item.similarity >= hybridCutoff;
        }
      }

      return false;
    }).toList();
  }
}
