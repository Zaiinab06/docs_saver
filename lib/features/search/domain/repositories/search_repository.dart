import '../entities/search_result_item.dart';

class SearchResponse {
  final List<SearchResultItem> results;
  final bool isOffline;
  final String query;

  const SearchResponse({
    required this.results,
    required this.isOffline,
    required this.query,
  });
}

abstract class SearchRepository {
  Future<SearchResponse> search(
    String query, {
    double? matchThreshold,
    int? matchCount,
  });
}
