import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/search_result_model.dart';

abstract class SearchRemoteDataSource {
  Future<List<SearchResultModel>> searchMemories(
    String query, {
    double? matchThreshold,
    int? matchCount,
  });
}

class SearchRemoteDataSourceImpl implements SearchRemoteDataSource {
  final SupabaseClient? client;
  final Future<String?> Function()? tokenProvider;
  final Future<FunctionResponse> Function(
    String functionName, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  })? functionsInvoker;

  SearchRemoteDataSourceImpl({
    this.client,
    this.tokenProvider,
    this.functionsInvoker,
  });

  SupabaseClient? get supabase {
    if (client != null) return client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Securely retrieves the current valid access token.
  ///
  /// Handles in-progress session restoration and automatically refreshes expired tokens.
  Future<String?> getValidAccessToken() async {
    if (tokenProvider != null) {
      return await tokenProvider!();
    }

    final clientInstance = supabase;
    if (clientInstance == null) return null;

    // 1. Check if currentSession is already present
    var session = clientInstance.auth.currentSession;
    if (session != null) {
      if (session.isExpired) {
        try {
          final refreshRes = await clientInstance.auth.refreshSession();
          session = refreshRes.session ?? session;
        } catch (_) {
          // Token may still be valid within clock skew/margin
        }
      }
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty) {
        return token;
      }
    }

    // 2. If session is null, wait briefly for auth restoration if it's currently in progress
    try {
      final authData = await clientInstance.auth.onAuthStateChange
          .firstWhere((data) =>
              data.event == AuthChangeEvent.initialSession ||
              data.event == AuthChangeEvent.signedIn ||
              data.event == AuthChangeEvent.tokenRefreshed)
          .timeout(const Duration(milliseconds: 1500));
      var restoredSession = authData.session;
      if (restoredSession != null && restoredSession.isExpired) {
        try {
          final refreshRes = await clientInstance.auth.refreshSession();
          restoredSession = refreshRes.session ?? restoredSession;
        } catch (_) {}
      }
      final token = restoredSession?.accessToken;
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (_) {
      // Timeout or no initial session event
    }

    return clientInstance.auth.currentSession?.accessToken;
  }

  @override
  Future<List<SearchResultModel>> searchMemories(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) async {
    final clientInstance = supabase;
    if (clientInstance == null && functionsInvoker == null) {
      throw const AuthException('Supabase client is not initialized');
    }

    final token = await getValidAccessToken();
    if (token == null || token.isEmpty) {
      throw const AuthException(
        'Authentication required. Please sign in to use semantic search.',
      );
    }

    final payload = <String, dynamic>{
      'query': query,
      if (matchThreshold != null) 'match_threshold': matchThreshold,
      if (matchCount != null) 'match_count': matchCount,
    };

    final FunctionResponse response;
    try {
      if (functionsInvoker != null) {
        response = await functionsInvoker!(
          'semantic-search',
          headers: {
            'Authorization': 'Bearer $token',
          },
          body: payload,
        );
      } else {
        response = await clientInstance!.functions.invoke(
          'semantic-search',
          headers: {
            'Authorization': 'Bearer $token',
          },
          body: payload,
        );
      }
    } on FunctionsHttpException catch (e) {
      final details = e.details;
      final errorMsg = details is Map
          ? (details['error'] ?? 'Search failed with HTTP ${e.status}')
          : (details?.toString() ?? 'Search failed with HTTP ${e.status}');
      if (e.status == 401) {
        throw AuthException(errorMsg);
      }
      throw Exception(errorMsg);
    }

    if (response.status != 200) {
      final errorMsg = response.data is Map
          ? (response.data['error'] ??
              'Search failed with HTTP ${response.status}')
          : 'Search failed with HTTP ${response.status}';
      throw Exception(errorMsg);
    }

    final data = response.data;
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list
          .whereType<Map>()
          .map((item) =>
              SearchResultModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    return [];
  }
}
