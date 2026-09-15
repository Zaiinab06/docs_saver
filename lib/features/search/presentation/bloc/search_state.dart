import 'package:equatable/equatable.dart';
import '../../domain/entities/search_result_item.dart';

abstract class SearchState extends Equatable {
  const SearchState();

  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {
  const SearchInitial();
}

class SearchLoading extends SearchState {
  final String query;

  const SearchLoading(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchLoaded extends SearchState {
  final List<SearchResultItem> results;
  final String query;
  final bool isOffline;

  const SearchLoaded({
    required this.results,
    required this.query,
    this.isOffline = false,
  });

  @override
  List<Object?> get props => [results, query, isOffline];
}

class SearchEmpty extends SearchState {
  final String query;
  final bool isOffline;

  const SearchEmpty({
    required this.query,
    this.isOffline = false,
  });

  @override
  List<Object?> get props => [query, isOffline];
}

class SearchError extends SearchState {
  final String message;
  final String query;

  const SearchError({
    required this.message,
    required this.query,
  });

  @override
  List<Object?> get props => [message, query];
}
