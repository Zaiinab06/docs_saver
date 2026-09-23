import '../repositories/search_repository.dart';
import 'semantic_relevance_filter.dart';

class SearchMemoriesUseCase {
  final SearchRepository repository;

  SearchMemoriesUseCase(this.repository);

  Future<SearchResponse> call(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) async {
    final response = await repository.search(
      query,
      matchThreshold: matchThreshold,
      matchCount: matchCount,
    );

    if (response.isOffline) {
      return response;
    }

    final filteredResults = SemanticRelevanceFilter.filter(
      response.results,
      query: query,
      minThreshold:
          matchThreshold ?? SemanticRelevanceFilter.minSimilarityThreshold,
    );

    return SearchResponse(
      results: filteredResults,
      isOffline: response.isOffline,
      query: response.query,
    );
  }
}
