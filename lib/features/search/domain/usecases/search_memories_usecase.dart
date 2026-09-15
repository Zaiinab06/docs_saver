import '../repositories/search_repository.dart';

class SearchMemoriesUseCase {
  final SearchRepository repository;

  SearchMemoriesUseCase(this.repository);

  Future<SearchResponse> call(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) {
    return repository.search(
      query,
      matchThreshold: matchThreshold,
      matchCount: matchCount,
    );
  }
}
