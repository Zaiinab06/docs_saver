import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:second_brain/core/network/network_checker.dart';
import 'package:second_brain/features/search/data/datasources/search_local_data_source.dart';
import 'package:second_brain/features/search/data/datasources/search_remote_data_source.dart';
import 'package:second_brain/features/search/data/models/search_result_model.dart';
import 'package:second_brain/features/search/data/repositories/search_repository_impl.dart';
import 'package:second_brain/features/search/domain/entities/search_result_item.dart';
import 'package:second_brain/features/search/domain/repositories/search_repository.dart';
import 'package:second_brain/features/search/domain/usecases/search_memories_usecase.dart';
import 'package:second_brain/features/search/presentation/bloc/search_bloc.dart';
import 'package:second_brain/features/search/presentation/bloc/search_event.dart';
import 'package:second_brain/features/search/presentation/bloc/search_state.dart';
import 'package:second_brain/features/search/presentation/screens/search_screen.dart';

class MockSearchRemoteDataSource implements SearchRemoteDataSource {
  List<SearchResultModel> results = [];
  bool shouldThrow = false;
  Exception? exceptionToThrow;
  String? lastQuery;

  @override
  Future<List<SearchResultModel>> searchMemories(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) async {
    lastQuery = query;
    if (shouldThrow) {
      throw exceptionToThrow ?? Exception('Network connection timed out');
    }
    return results;
  }
}

class MockSearchLocalDataSource implements SearchLocalDataSource {
  List<SearchResultModel> results = [];
  String? lastQuery;
  String? lastUserId;

  @override
  Future<List<SearchResultModel>> searchMemoriesLocally(
    String query, {
    String? userId,
  }) async {
    lastQuery = query;
    lastUserId = userId;
    return results;
  }
}

class MockSearchRepository implements SearchRepository {
  List<SearchResultItem> mockResults = [];
  bool mockIsOffline = false;
  bool shouldThrow = false;
  String lastSearchedQuery = '';

  @override
  Future<SearchResponse> search(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) async {
    lastSearchedQuery = query;
    if (shouldThrow) {
      throw Exception('Network connection timed out');
    }
    return SearchResponse(
      results: mockResults,
      isOffline: mockIsOffline,
      query: query,
    );
  }
}

void main() {
  group('SearchBloc Unit Tests', () {
    late MockSearchRepository mockRepo;
    late SearchMemoriesUseCase useCase;
    late SearchBloc bloc;

    setUp(() {
      mockRepo = MockSearchRepository();
      useCase = SearchMemoriesUseCase(mockRepo);
      bloc = SearchBloc(searchMemoriesUseCase: useCase);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is SearchInitial', () {
      expect(bloc.state, isA<SearchInitial>());
    });

    test('empty or whitespace query emits SearchInitial', () async {
      bloc.add(const SearchQueryChanged('   '));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<SearchInitial>());
    });

    test('successful online search emits SearchLoading then SearchLoaded', () async {
      final now = DateTime.now();
      mockRepo.mockResults = [
        SearchResultItem(
          id: 'mem-1',
          title: 'Flutter Architecture',
          content: 'Clean architecture guide',
          category: 'Work',
          tags: const ['flutter', 'bloc'],
          clientCreatedAt: now,
          similarity: 0.88,
        ),
      ];
      mockRepo.mockIsOffline = false;

      final expectedStates = [
        const SearchLoading('flutter'),
        SearchLoaded(
          results: mockRepo.mockResults,
          query: 'flutter',
          isOffline: false,
        ),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));

      bloc.add(const SearchQueryChanged('flutter'));
    });

    test('zero results emit SearchEmpty', () async {
      mockRepo.mockResults = [];
      mockRepo.mockIsOffline = false;

      final expectedStates = [
        const SearchLoading('quantum'),
        const SearchEmpty(query: 'quantum', isOffline: false),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));

      bloc.add(const SearchQueryChanged('quantum'));
    });

    test('failure emits SearchError', () async {
      mockRepo.shouldThrow = true;

      final expectedStates = [
        const SearchLoading('error_test'),
        const SearchError(
          message: 'Network connection timed out',
          query: 'error_test',
        ),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));

      bloc.add(const SearchQueryChanged('error_test'));
    });

    test('clear search resets state to SearchInitial', () async {
      bloc.add(ClearSearchRequested());
      await Future.delayed(const Duration(milliseconds: 20));
      expect(bloc.state, isA<SearchInitial>());
    });
  });

  group('SearchScreen Widget Tests', () {
    late MockSearchRepository mockRepo;
    late SearchMemoriesUseCase useCase;
    late SearchBloc bloc;

    setUp(() {
      mockRepo = MockSearchRepository();
      useCase = SearchMemoriesUseCase(mockRepo);
      bloc = SearchBloc(searchMemoriesUseCase: useCase);
    });

    tearDown(() {
      bloc.close();
    });

    testWidgets('renders initial suggestions and search input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Semantic Search'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
    });

    testWidgets('shows loading state while search is in progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.emit(const SearchLoading('react'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Searching memories for "react"...'), findsOneWidget);
    });

    testWidgets('renders ranked semantic cards with similarity score badges', (tester) async {
      final now = DateTime.now();
      final item = SearchResultItem(
        id: 'mem-99',
        title: 'Microservices Design',
        content: 'Event-driven architecture and streaming patterns',
        category: 'Work',
        tags: const ['microservices', 'kafka'],
        clientCreatedAt: now,
        similarity: 0.942,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.emit(SearchLoaded(results: [item], query: 'microservices', isOffline: false));
      await tester.pumpAndSettle();

      expect(find.text('Microservices Design'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget); // Math.round(0.942 * 100)
      expect(find.text('#microservices'), findsOneWidget);
      expect(find.text('#kafka'), findsOneWidget);
      expect(find.text('Ranked by AI meaning'), findsOneWidget);
    });

    testWidgets('shows offline indicator banner when offline fallback results are returned', (tester) async {
      final now = DateTime.now();
      final item = SearchResultItem(
        id: 'mem-101',
        title: 'Offline Notes',
        content: 'Local database keywords match',
        category: 'Personal',
        tags: const ['offline'],
        clientCreatedAt: now,
        similarity: 0.0,
        isOfflineResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.emit(SearchLoaded(results: [item], query: 'offline', isOffline: true));
      await tester.pumpAndSettle();

      expect(find.text('Offline Mode • Showing local keyword matches'), findsOneWidget);
      expect(find.text('Keyword'), findsOneWidget);
      expect(find.text('Offline Notes'), findsOneWidget);
    });

    testWidgets('shows empty state when no memories match query', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.emit(const SearchEmpty(query: 'astronomy', isOffline: false));
      await tester.pumpAndSettle();

      expect(find.text('No memories found'), findsOneWidget);
      expect(find.textContaining('astronomy'), findsOneWidget);
    });

    testWidgets('shows error state with retry button on failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.emit(const SearchError(message: 'Network timeout', query: 'server'));
      await tester.pumpAndSettle();

      expect(find.text('Search Failed'), findsOneWidget);
      expect(find.text('Network timeout'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('tapping clear button empties text field and resets state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      await tester.enterText(find.byType(TextField), 'testing');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(find.text('testing'), findsNothing);
      expect(bloc.state, isA<SearchInitial>());
    });

    testWidgets('tapping preset chip enters query and triggers search', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      await tester.tap(find.text('Work'));
      await tester.pump();

      expect(find.text('Work'), findsWidgets);
      expect(mockRepo.lastSearchedQuery, 'Work');
    });
  });

  group('SearchRepository Reachability & Offline Fallback Tests', () {
    late MockSearchRemoteDataSource mockRemote;
    late MockSearchLocalDataSource mockLocal;
    late SearchRepositoryImpl repository;

    setUp(() {
      mockRemote = MockSearchRemoteDataSource();
      mockLocal = MockSearchLocalDataSource();
      repository = SearchRepositoryImpl(
        remoteDataSource: mockRemote,
        localDataSource: mockLocal,
      );
      NetworkChecker.testOverride = null;
      NetworkChecker.resetCache();
    });

    tearDown(() {
      NetworkChecker.testOverride = null;
      NetworkChecker.resetCache();
    });

    test('internet available → online semantic search with isOffline: false', () async {
      NetworkChecker.testOverride = true;
      mockRemote.results = [
        SearchResultModel(
          id: 'mem-1',
          title: 'Semantic Note',
          content: 'Found via dense vector similarity',
          category: 'Ideas',
          tags: const ['ai'],
          clientCreatedAt: DateTime.now(),
          similarity: 0.91,
        ),
      ];

      final response = await repository.search('ideas');

      expect(mockRemote.lastQuery, 'ideas');
      expect(response.isOffline, isFalse);
      expect(response.results.length, 1);
      expect(response.results.first.title, 'Semantic Note');
      expect(response.results.first.similarity, 0.91);
      expect(response.results.first.isOfflineResult, isFalse);
    });

    test('genuinely offline → Isar fallback with isOffline: true', () async {
      NetworkChecker.testOverride = false;
      mockLocal.results = [
        SearchResultModel(
          id: 'mem-2',
          title: 'Offline Note',
          content: 'Found via local Isar keyword match',
          category: 'Personal',
          tags: const ['local'],
          clientCreatedAt: DateTime.now(),
          similarity: 0.0,
        ),
      ];

      final response = await repository.search('offline');

      expect(mockRemote.lastQuery, isNull);
      expect(mockLocal.lastQuery, 'offline');
      expect(response.isOffline, isTrue);
      expect(response.results.length, 1);
      expect(response.results.first.title, 'Offline Note');
      expect(response.results.first.isOfflineResult, isTrue);
    });

    test('online but remote throws SocketException (network drop) → falls back to Isar with isOffline: true', () async {
      NetworkChecker.testOverride = true;
      mockRemote.shouldThrow = true;
      mockRemote.exceptionToThrow = const SocketException('Failed host lookup: vsqzsirrdkaxjdqmmwac.supabase.co');
      mockLocal.results = [
        SearchResultModel(
          id: 'mem-3',
          title: 'Cached Note',
          content: 'Local fallback after socket drop',
          category: 'Work',
          tags: const ['fallback'],
          clientCreatedAt: DateTime.now(),
          similarity: 0.0,
        ),
      ];

      final response = await repository.search('work');

      expect(response.isOffline, isTrue);
      expect(response.results.first.title, 'Cached Note');
    });

    test('online but remote throws server 500 error → rethrows exception without marking as offline', () async {
      NetworkChecker.testOverride = true;
      mockRemote.shouldThrow = true;
      mockRemote.exceptionToThrow = Exception('Internal server error (HTTP 500)');

      expect(
        () => repository.search('server_error'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Internal server error'),
        )),
      );
    });

    test('missing session or auth 401 error → throws AuthException, NOT offline mode', () async {
      NetworkChecker.testOverride = true;
      mockRemote.shouldThrow = true;
      mockRemote.exceptionToThrow = const AuthException('Unauthorized: Missing or malformed Authorization header. Bearer token required.');

      expect(
        () => repository.search('unauthorized_query'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized'),
        )),
      );
      // Local fallback must NOT be called to hide auth failures
      expect(mockLocal.lastQuery, isNull);
    });

    test('empty query returns empty response immediately without network calls', () async {
      NetworkChecker.testOverride = true;
      final response = await repository.search('   ');

      expect(response.results, isEmpty);
      expect(response.isOffline, isFalse);
      expect(mockRemote.lastQuery, isNull);
      expect(mockLocal.lastQuery, isNull);
    });
  });

  group('SearchRemoteDataSource Supabase Authentication & Header Tests', () {
    test('valid authenticated session → Authorization Bearer token sent with request', () async {
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;

      final remoteDataSource = SearchRemoteDataSourceImpl(
        tokenProvider: () async => 'jwt-test-token-xyz',
        functionsInvoker: (functionName, {body, headers}) async {
          capturedHeaders = headers;
          capturedBody = body;
          return const FunctionResponse(
            status: 200,
            data: {
              'success': true,
              'results': [
                {
                  'id': 'mem-auth-1',
                  'title': 'Secure Memory',
                  'content': 'Verified with real bearer token',
                  'category': 'Work',
                  'tags': ['auth', 'jwt'],
                  'client_created_at': '2026-09-15T20:00:00.000Z',
                  'similarity': 0.95,
                }
              ],
            },
          );
        },
      );

      final results = await remoteDataSource.searchMemories('secure query');

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['Authorization'], 'Bearer jwt-test-token-xyz');
      expect(capturedBody?['query'], 'secure query');
      expect(results.length, 1);
      expect(results.first.title, 'Secure Memory');
      expect(results.first.similarity, 0.95);
    });

    test('missing session → proper authentication error, NOT offline', () async {
      bool invokerCalled = false;
      final remoteDataSource = SearchRemoteDataSourceImpl(
        tokenProvider: () async => null,
        functionsInvoker: (functionName, {body, headers}) async {
          invokerCalled = true;
          return const FunctionResponse(status: 200, data: {});
        },
      );

      expect(
        () => remoteDataSource.searchMemories('missing_session'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Authentication required'),
        )),
      );
      expect(invokerCalled, isFalse);
    });

    test('FunctionsHttpException 401 → converts to AuthException with server message', () async {
      final remoteDataSource = SearchRemoteDataSourceImpl(
        tokenProvider: () async => 'expired-token',
        functionsInvoker: (functionName, {body, headers}) async {
          throw const FunctionsHttpException(
            status: 401,
            details: {
              'error': 'Unauthorized: Invalid or expired authentication token.',
            },
          );
        },
      );

      expect(
        () => remoteDataSource.searchMemories('expired_query'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Invalid or expired authentication token.'),
        )),
      );
    });
  });

  group('NetworkChecker Reachability & Caching Tests', () {
    setUp(() {
      NetworkChecker.testOverride = null;
      NetworkChecker.resetCache();
    });

    tearDown(() {
      NetworkChecker.testOverride = null;
      NetworkChecker.resetCache();
    });

    test('testOverride returns deterministic status without network lookup', () async {
      NetworkChecker.setTestOverride(true);
      expect(await NetworkChecker.isConnected(), isTrue);

      NetworkChecker.setTestOverride(false);
      expect(await NetworkChecker.isConnected(), isFalse);
    });

    test('onConnectivityChanged stream emits transitions', () async {
      final states = <bool>[];
      final sub = NetworkChecker.onConnectivityChanged.listen(states.add);

      NetworkChecker.setTestOverride(false);
      NetworkChecker.setTestOverride(true);
      NetworkChecker.setTestOverride(false);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states, [false, true, false]);
      await sub.cancel();
    });
  });
}
