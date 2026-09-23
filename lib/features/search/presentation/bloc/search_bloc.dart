import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/search_memories_usecase.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchMemoriesUseCase searchMemoriesUseCase;

  int _activeRequestId = 0;
  String _lastQuery = '';

  SearchBloc({required this.searchMemoriesUseCase})
    : super(const SearchInitial()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<ClearSearchRequested>(_onClearSearch);
    on<RetrySearchRequested>(_onRetrySearch);
  }

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final cleanQuery = event.query.trim();
    _lastQuery = cleanQuery;

    if (cleanQuery.isEmpty) {
      _activeRequestId++;
      emit(const SearchInitial());
      return;
    }

    final requestId = ++_activeRequestId;
    emit(SearchLoading(cleanQuery));

    try {
      final response = await searchMemoriesUseCase(cleanQuery);

      if (requestId != _activeRequestId) {
        // Discard out-of-order stale response
        return;
      }

      if (response.results.isEmpty) {
        emit(SearchEmpty(query: cleanQuery, isOffline: response.isOffline));
      } else {
        emit(
          SearchLoaded(
            results: response.results,
            query: cleanQuery,
            isOffline: response.isOffline,
          ),
        );
      }
    } catch (e) {
      if (requestId != _activeRequestId) return;
      emit(
        SearchError(
          message: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
          query: cleanQuery,
        ),
      );
    }
  }

  void _onClearSearch(ClearSearchRequested event, Emitter<SearchState> emit) {
    _activeRequestId++;
    _lastQuery = '';
    emit(const SearchInitial());
  }

  void _onRetrySearch(RetrySearchRequested event, Emitter<SearchState> emit) {
    if (_lastQuery.isNotEmpty) {
      add(SearchQueryChanged(_lastQuery));
    }
  }
}
