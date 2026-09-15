import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/network_checker.dart';
import '../../domain/repositories/search_repository.dart';
import '../datasources/search_local_data_source.dart';
import '../datasources/search_remote_data_source.dart';

class SearchRepositoryImpl implements SearchRepository {
  final SearchRemoteDataSource remoteDataSource;
  final SearchLocalDataSource localDataSource;

  SearchRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  String? _getCurrentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SearchResponse> search(
    String query, {
    double? matchThreshold,
    int? matchCount,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return SearchResponse(
        results: const [],
        isOffline: false,
        query: cleanQuery,
      );
    }

    final isOnline = await NetworkChecker.isConnected();
    final userId = _getCurrentUserId();

    if (isOnline) {
      try {
        final remoteModels = await remoteDataSource.searchMemories(
          cleanQuery,
          matchThreshold: matchThreshold,
          matchCount: matchCount,
        );

        final items =
            remoteModels.map((m) => m.toEntity(isOffline: false)).toList();

        return SearchResponse(
          results: items,
          isOffline: false,
          query: cleanQuery,
        );
      } catch (e) {
        // Never treat authentication or token errors as offline mode
        final errString = e.toString().toLowerCase();
        final isAuthError = e is AuthException ||
            errString.contains('unauthorized') ||
            errString.contains('authentication') ||
            errString.contains('jwt') ||
            errString.contains('bearer token');

        if (isAuthError) {
          rethrow;
        }

        // Verify whether the remote failure was due to genuine network loss/disconnection
        final stillOnline =
            await NetworkChecker.isConnected(forceRefresh: true);
        final isNetworkDisconnect = !stillOnline ||
            errString.contains('socketexception') ||
            errString.contains('connection refused') ||
            errString.contains('network is unreachable') ||
            errString.contains('failed host lookup') ||
            errString.contains('connection closed') ||
            errString.contains('clientexception') ||
            errString.contains('handshakeexception') ||
            errString.contains('timed out');

        if (isNetworkDisconnect) {
          // Genuinely offline or network dropped: fall back to local Isar keyword search
          final localModels = await localDataSource.searchMemoriesLocally(
            cleanQuery,
            userId: userId,
          );
          final items =
              localModels.map((m) => m.toEntity(isOffline: true)).toList();

          return SearchResponse(
            results: items,
            isOffline: true,
            query: cleanQuery,
          );
        }

        // Server-side or auth error while online: rethrow to let UI display error state with retry
        rethrow;
      }
    } else {
      // Genuinely offline: fall back to local Isar keyword search
      final localModels = await localDataSource.searchMemoriesLocally(
        cleanQuery,
        userId: userId,
      );
      final items =
          localModels.map((m) => m.toEntity(isOffline: true)).toList();

      return SearchResponse(
        results: items,
        isOffline: true,
        query: cleanQuery,
      );
    }
  }
}
