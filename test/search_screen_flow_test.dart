import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:second_brain/core/network/network_checker.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import 'package:second_brain/features/search/data/datasources/search_local_data_source.dart';
import 'package:second_brain/features/search/data/datasources/search_remote_data_source.dart';
import 'package:second_brain/features/search/data/models/search_result_model.dart';
import 'package:second_brain/features/search/data/repositories/search_repository_impl.dart';
import 'package:second_brain/features/search/domain/entities/search_result_item.dart';
import 'package:second_brain/features/search/domain/repositories/search_repository.dart';
import 'package:second_brain/features/search/domain/usecases/search_memories_usecase.dart';
import 'package:second_brain/features/search/domain/usecases/semantic_relevance_filter.dart';
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
  Map<String, MemoryModel> memoryStore = {};
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

  @override
  Future<MemoryModel?> getMemoryById(String serverId) async {
    return memoryStore[serverId];
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

    testWidgets('renders initial state and search input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Semantic Search'), findsOneWidget);
      expect(find.text('Search by meaning, feeling, or concept —\nnot just exact keywords.'), findsOneWidget);
      expect(find.text('Try searching for'), findsNothing);
      expect(find.text('Work'), findsNothing);
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

    testWidgets('entering query triggers search', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Work');
      await tester.pump(const Duration(milliseconds: 350));

      expect(mockRepo.lastSearchedQuery, 'Work');
    });
  });

  group('SearchScreen Tab State Reset Tests', () {
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

    testWidgets('leaving Search (isActive: false) clears query and resets results', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: true),
        ),
      );

      await tester.enterText(find.byType(TextField), 'prayer mat');
      await tester.pump();
      expect(find.text('prayer mat'), findsOneWidget);

      // User leaves Search tab (isActive becomes false)
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: false),
        ),
      );
      await tester.pump();

      // Query text field is cleared and state reset to initial
      expect(find.text('prayer mat'), findsNothing);
      expect(bloc.state, isA<SearchInitial>());

      // Reopening Search tab starts with empty query and fresh session
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: true),
        ),
      );
      await tester.pump();

      expect(find.text('prayer mat'), findsNothing);
      expect(find.text('Semantic Search'), findsOneWidget);
    });

    testWidgets('typing a query and searching still works normally', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: 'mem-1',
          title: 'Prayer Mat in Closet',
          content: 'Green velvet prayer mat stored on top shelf',
          category: 'Personal',
          clientCreatedAt: DateTime.now(),
          similarity: 0.89,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('prayer mat'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Prayer Mat in Closet'), findsOneWidget);
      expect(find.text('89%'), findsOneWidget);

      bloc.close();
    });

    testWidgets('semantic search results are NOT cleared while staying on the Search screen', (tester) async {
      final results = [
        SearchResultItem(
          id: 'mem-1',
          title: 'Prayer Mat in Closet',
          content: 'Green velvet prayer mat stored on top shelf',
          category: 'Personal',
          clientCreatedAt: DateTime.now(),
          similarity: 0.89,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: true),
        ),
      );

      bloc.emit(SearchLoaded(results: results, query: 'prayer mat', isOffline: false));
      await tester.pumpAndSettle();

      expect(find.text('Prayer Mat in Closet'), findsOneWidget);

      // Re-pumping while staying on Search screen (isActive: true)
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: true),
        ),
      );
      await tester.pumpAndSettle();

      // Results and state remain intact
      expect(find.text('Prayer Mat in Closet'), findsOneWidget);
      expect(bloc.state, isA<SearchLoaded>());
    });
  });

  group('SearchScreen Keyboard & Layout Tests', () {
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

    testWidgets('resizes naturally above keyboard and results remain scrollable without overflow', (tester) async {
      final results = List.generate(
        8,
        (i) => SearchResultItem(
          id: 'mem-$i',
          title: 'Memory Result Number $i',
          content: 'Detailed description for test item $i with long content to demonstrate scrolling',
          category: 'Work',
          tags: ['test', 'item-$i'],
          clientCreatedAt: DateTime.now(),
          similarity: 0.90 - (i * 0.02),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc, isActive: true),
        ),
      );

      bloc.emit(SearchLoaded(results: results, query: 'test', isOffline: false));
      await tester.pumpAndSettle();

      expect(find.text('Memory Result Number 0'), findsOneWidget);

      // Simulate Android keyboard opening with 300px height
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() => tester.view.resetViewInsets());
      await tester.pump(const Duration(milliseconds: 50));

      // Top search bar remains visible and usable
      expect(find.byType(TextField), findsOneWidget);

      // First result remains visible above the keyboard
      expect(find.text('Memory Result Number 0'), findsOneWidget);

      // Results remain scrollable above the keyboard
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 50));

      // Later results can be scrolled into view
      expect(find.text('Memory Result Number 3'), findsOneWidget);

      // Reset keyboard
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TextField), findsOneWidget);
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

  group('SemanticRelevanceFilter Unit & Search Flow Relevance Tests', () {
    final now = DateTime.now();

    test('1. 0.56 result excluded (below 0.57 noise floor)', () {
      final items = [
        SearchResultItem(
          id: 'noise-1',
          title: 'Noise Memory',
          content: 'Unrelated noise',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.56,
        ),
        SearchResultItem(
          id: 'noise-2',
          title: 'Weaker Noise',
          content: 'Unrelated content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.51,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(items);

      // 0.56 fails the 0.57 absolute noise floor
      expect(filtered, isEmpty);
    });

    test('2. 0.57 result can be retained when it passes the dynamic cutoff', () {
      // Single 0.57 result meeting the floor (e.g. cross-lingual Roman Urdu query)
      final singleItem = [
        SearchResultItem(
          id: 'roman-urdu-1',
          title: 'chair save ki thi mny?',
          content: 'Ergonomic desk chair receipt',
          category: 'Home',
          clientCreatedAt: now,
          similarity: 0.57,
        ),
      ];
      final filteredSingle = SemanticRelevanceFilter.filter(singleItem);
      expect(filteredSingle.length, 1);
      expect(filteredSingle.first.id, 'roman-urdu-1');
      expect(filteredSingle.first.similarity, 0.57);

      // Moderate top result (0.59) with a 0.57 companion within 0.18 margin
      final pairedItems = [
        SearchResultItem(
          id: 'urdu-notes',
          title: 'urdu k notes',
          content: 'Urdu poetry and literature notes',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.59,
        ),
        SearchResultItem(
          id: 'urdu-grammar',
          title: 'Urdu Grammar Rules',
          content: 'Grammar and vocabulary',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.57,
        ),
        SearchResultItem(
          id: 'noise',
          title: 'Noise Item',
          content: 'Unrelated text',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.54,
        ),
      ];
      final filteredPaired = SemanticRelevanceFilter.filter(pairedItems);
      expect(filteredPaired.length, 2);
      expect(filteredPaired.map((i) => i.id), containsAll(['urdu-notes', 'urdu-grammar']));
      expect(filteredPaired.any((i) => i.id == 'noise'), isFalse);
    });

    test('3. strong top result still filters unrelated 0.48–0.56 results', () {
      final items = [
        SearchResultItem(
          id: '1',
          title: 'Water bottle on desk',
          content: 'Blue reusable thermos',
          category: 'Personal',
          clientCreatedAt: now,
          similarity: 0.82,
        ),
        SearchResultItem(
          id: '2',
          title: 'Urdu poetry notes',
          content: 'Allama Iqbal couplets',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.56,
        ),
        SearchResultItem(
          id: '3',
          title: 'Office chair receipt',
          content: 'Ergonomic mesh chair invoice',
          category: 'Finance',
          clientCreatedAt: now,
          similarity: 0.52,
        ),
        SearchResultItem(
          id: '4',
          title: 'Grocery receipt',
          content: 'Milk and eggs',
          category: 'Finance',
          clientCreatedAt: now,
          similarity: 0.48,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(items);

      expect(filtered.length, 1);
      expect(filtered.first.id, '1');
      expect(filtered.first.title, 'Water bottle on desk');
      expect(filtered.first.similarity, 0.82);
    });

    test('4. multiple genuinely strong results remain', () {
      final items = [
        SearchResultItem(
          id: '1',
          title: 'Flutter Clean Architecture',
          content: 'Core architecture principles',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.88,
        ),
        SearchResultItem(
          id: '2',
          title: 'BLoC State Management',
          content: 'Events and states stream',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.82,
        ),
        SearchResultItem(
          id: '3',
          title: 'Repository Pattern Guide',
          content: 'Abstract interface and impl',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.79,
        ),
        SearchResultItem(
          id: '4',
          title: 'Grocery Store Receipt',
          content: 'Milk and bread',
          category: 'Finance',
          clientCreatedAt: now,
          similarity: 0.50,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(items);

      expect(filtered.length, 3);
      expect(filtered.map((i) => i.id), containsAll(['1', '2', '3']));
      expect(filtered.any((i) => i.id == '4'), isFalse);
    });

    test('5. no relevant results returns empty', () {
      final items = [
        SearchResultItem(
          id: '1',
          title: 'Unrelated Note A',
          content: 'Random content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.55,
        ),
        SearchResultItem(
          id: '2',
          title: 'Unrelated Note B',
          content: 'Another random content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.51,
        ),
        SearchResultItem(
          id: '3',
          title: 'Unrelated Note C',
          content: 'Third random content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.48,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(items);

      expect(filtered, isEmpty);
    });

    test('no hardcoded/query-specific matching — purely similarity score driven', () {
      final itemsA = [
        SearchResultItem(
          id: 'urdu-1',
          title: 'urdu k notes',
          content: 'Urdu language notes',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.81,
        ),
        SearchResultItem(
          id: 'urdu-2',
          title: 'unrelated memory',
          content: 'Some random text',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.52,
        ),
      ];

      final itemsB = [
        SearchResultItem(
          id: 'chair-1',
          title: 'chair save ki thi mny?',
          content: 'Chair query test',
          category: 'Home',
          clientCreatedAt: now,
          similarity: 0.81,
        ),
        SearchResultItem(
          id: 'chair-2',
          title: 'unrelated memory',
          content: 'Some random text',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.52,
        ),
      ];

      final filteredA = SemanticRelevanceFilter.filter(itemsA);
      final filteredB = SemanticRelevanceFilter.filter(itemsB);

      expect(filteredA.length, 1);
      expect(filteredA.first.id, 'urdu-1');
      expect(filteredB.length, 1);
      expect(filteredB.first.id, 'chair-1');
    });

    test('offline keyword search results are preserved without similarity filtering', () {
      final items = [
        SearchResultItem(
          id: 'off-1',
          title: 'Offline Note 1',
          content: 'Keyword match',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.0,
          isOfflineResult: true,
        ),
        SearchResultItem(
          id: 'off-2',
          title: 'Offline Note 2',
          content: 'Another match',
          category: 'Personal',
          clientCreatedAt: now,
          similarity: 0.0,
          isOfflineResult: true,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(items);

      expect(filtered.length, 2);
      expect(filtered.map((i) => i.id), containsAll(['off-1', 'off-2']));
    });

    testWidgets('SearchScreen renders accurate "X memories found" count with filtered results', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: '1',
          title: 'Clean Architecture Guide',
          content: 'Detailed guide',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.88,
        ),
        SearchResultItem(
          id: '2',
          title: 'BLoC State Management',
          content: 'Bloc pattern',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.82,
        ),
        SearchResultItem(
          id: '3',
          title: 'Random Weak Match',
          content: 'Noise',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.51,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('architecture'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Weak match (0.51) was excluded; 2 strong matches retained
      expect(find.text('2 memories found'), findsOneWidget);
      expect(find.text('Clean Architecture Guide'), findsOneWidget);
      expect(find.text('BLoC State Management'), findsOneWidget);
      expect(find.text('Random Weak Match'), findsNothing);

      bloc.close();
    });

    testWidgets('SearchScreen renders empty state when no memories meet relevance threshold', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: '1',
          title: 'Noise 1',
          content: 'Noise content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.56,
        ),
        SearchResultItem(
          id: '2',
          title: 'Noise 2',
          content: 'Noise content',
          category: 'General',
          clientCreatedAt: now,
          similarity: 0.49,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('unrelated topic'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('No memories found'), findsOneWidget);
      expect(find.text('Noise 1'), findsNothing);
      expect(find.text('Noise 2'), findsNothing);

      bloc.close();
    });

    testWidgets('SearchScreen retains 0.57 memory when it meets the 0.57 floor', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: 'mem-chair',
          title: 'Office Chair Receipt',
          content: 'Herman Miller chair',
          category: 'Finance',
          clientCreatedAt: now,
          similarity: 0.57,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('chair save ki thi mny?'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('1 memory found'), findsOneWidget);
      expect(find.text('Office Chair Receipt'), findsOneWidget);
      expect(find.text('57%'), findsOneWidget);

      bloc.close();
    });

    test('REGRESSION 1: "laptop"-style results where strong relevant results remain and unrelated moderate-score results are excluded', () {
      final candidates = [
        SearchResultItem(
          id: '1',
          title: 'Laptop QWERTY Keyboard',
          content: 'Keyboard details',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.68,
        ),
        SearchResultItem(
          id: '2',
          title: 'Laptop Keyboard',
          content: 'Keyboard details',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.66,
        ),
        SearchResultItem(
          id: '3',
          title: 'Dell Latitude Laptop Keyboard',
          content: 'Dell keyboard',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.66,
        ),
        SearchResultItem(
          id: '4',
          title: 'Black Wired HP Computer/Mouse',
          content: 'Mouse accessory',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.60,
        ),
        SearchResultItem(
          id: '5',
          title: 'Letter Advising Brother',
          content: 'Family letter',
          category: 'Personal',
          clientCreatedAt: now,
          similarity: 0.60,
        ),
        SearchResultItem(
          id: '6',
          title: 'Urdu Poetry',
          content: 'Poetry couplets',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.58,
        ),
        SearchResultItem(
          id: '7',
          title: 'Dining Table',
          content: 'Furniture note',
          category: 'Home',
          clientCreatedAt: now,
          similarity: 0.58,
        ),
      ];

      final filtered = SemanticRelevanceFilter.filter(candidates, query: 'laptop');

      expect(filtered.length, 3);
      expect(filtered.map((i) => i.title), containsAll([
        'Laptop QWERTY Keyboard',
        'Laptop Keyboard',
        'Dell Latitude Laptop Keyboard',
      ]));
      expect(filtered.any((i) => i.title == 'Letter Advising Brother'), isFalse);
      expect(filtered.any((i) => i.title == 'Urdu Poetry'), isFalse);
      expect(filtered.any((i) => i.title == 'Dining Table'), isFalse);
      expect(filtered.any((i) => i.title == 'Black Wired HP Computer/Mouse'), isFalse);
    });

    testWidgets('REGRESSION 1 & UI: "3 memories found" accurately reflects final filtered laptop results', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: '1',
          title: 'Laptop QWERTY Keyboard',
          content: 'Keyboard details',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.68,
        ),
        SearchResultItem(
          id: '2',
          title: 'Laptop Keyboard',
          content: 'Keyboard details',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.66,
        ),
        SearchResultItem(
          id: '3',
          title: 'Dell Latitude Laptop Keyboard',
          content: 'Dell keyboard',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.66,
        ),
        SearchResultItem(
          id: '4',
          title: 'Black Wired HP Computer/Mouse',
          content: 'Mouse accessory',
          category: 'Work',
          clientCreatedAt: now,
          similarity: 0.60,
        ),
        SearchResultItem(
          id: '5',
          title: 'Letter Advising Brother',
          content: 'Family letter',
          category: 'Personal',
          clientCreatedAt: now,
          similarity: 0.60,
        ),
        SearchResultItem(
          id: '6',
          title: 'Urdu Poetry',
          content: 'Poetry couplets',
          category: 'Study',
          clientCreatedAt: now,
          similarity: 0.58,
        ),
        SearchResultItem(
          id: '7',
          title: 'Dining Table',
          content: 'Furniture note',
          category: 'Home',
          clientCreatedAt: now,
          similarity: 0.58,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('laptop'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('3 memories found'), findsOneWidget);
      expect(find.text('Laptop QWERTY Keyboard'), findsOneWidget);
      expect(find.text('Laptop Keyboard'), findsOneWidget);
      expect(find.text('Dell Latitude Laptop Keyboard'), findsOneWidget);
      expect(find.text('Letter Advising Brother'), findsNothing);
      expect(find.text('Urdu Poetry'), findsNothing);
      expect(find.text('Dining Table'), findsNothing);

      bloc.close();
    });

    testWidgets('REGRESSION 4 & 5: Search displays real persisted creation timestamp matching SavedScreen (e.g. 4h ago)', (tester) async {
      final fourHoursAgo = DateTime.now().subtract(const Duration(hours: 4));

      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        SearchResultItem(
          id: 'mem-saved-1',
          title: 'Laptop QWERTY Keyboard',
          content: 'Saved 4 hours ago',
          category: 'Work',
          clientCreatedAt: fourHoursAgo,
          similarity: 0.68,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('laptop'));
      await tester.pump();
      await tester.pumpAndSettle();

      // In Saved, it shows '4h ago'; Search must show 'Work • 4h ago' (never 'Just now')
      expect(find.text('Work • 4h ago'), findsOneWidget);
      expect(find.text('Work • Just now'), findsNothing);

      bloc.close();
    });

    testWidgets('REGRESSION 6: Memory with null timestamp does not fabricate "Just now"', (tester) async {
      final mockRepo = MockSearchRepository();
      mockRepo.mockResults = [
        const SearchResultItem(
          id: 'mem-no-time',
          title: 'Existing Memory Without Timestamp',
          content: 'Test content',
          category: 'Work',
          clientCreatedAt: null,
          similarity: 0.70,
        ),
      ];

      final useCase = SearchMemoriesUseCase(mockRepo);
      final bloc = SearchBloc(searchMemoriesUseCase: useCase);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(searchBloc: bloc),
        ),
      );

      bloc.add(const SearchQueryChanged('memory'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Displays category 'Work' without fabricated 'Just now'
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Work • Just now'), findsNothing);

      bloc.close();
    });

    test('REGRESSION 4 & 6: SearchRepositoryImpl resolves persisted timestamp from localDataSource for existing memory', () async {
      final persistedCreatedAt = DateTime.now().subtract(const Duration(hours: 4));

      final mockRemote = MockSearchRemoteDataSource();
      // Remote returns model with null clientCreatedAt
      mockRemote.results = [
        const SearchResultModel(
          id: 'mem-local-1',
          title: 'Dell Latitude Laptop Keyboard',
          content: 'Content',
          category: 'Work',
          tags: ['hardware'],
          clientCreatedAt: null,
          similarity: 0.66,
        ),
      ];

      final mockLocal = MockSearchLocalDataSource();
      // Local Isar cache has the persisted memory with its real timestamp
      final localModel = MemoryModel()
        ..serverId = 'mem-local-1'
        ..userId = 'user-1'
        ..title = 'Dell Latitude Laptop Keyboard'
        ..content = 'Content'
        ..category = 'Work'
        ..tags = ['hardware']
        ..clientCreatedAt = persistedCreatedAt
        ..clientUpdatedAt = persistedCreatedAt
        ..serverUpdatedAt = persistedCreatedAt;
      mockLocal.memoryStore['mem-local-1'] = localModel;

      final repo = SearchRepositoryImpl(
        remoteDataSource: mockRemote,
        localDataSource: mockLocal,
      );

      final response = await repo.search('laptop');
      expect(response.results.length, 1);
      // The resolved timestamp MUST match the persisted local model timestamp
      expect(response.results.first.clientCreatedAt, equals(persistedCreatedAt));
    });
  });
}
