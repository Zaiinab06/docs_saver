import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/google_doc_entity.dart';
import '../../domain/entities/google_integration_status.dart';

abstract class GoogleAuthRemoteDataSource {
  Future<String> startOAuth();
  Future<String> startGooglePicker();
  Future<GoogleIntegrationStatus> getStatus();
  Future<void> disconnect();
  Future<GoogleDocEntity> importDoc(String fileId);
  Future<GoogleDocEntity> importDriveFile(String fileId);
}

class GoogleAuthRemoteDataSourceImpl implements GoogleAuthRemoteDataSource {
  final SupabaseClient? _supabase;

  GoogleAuthRemoteDataSourceImpl({SupabaseClient? client})
    : _supabase = client ?? _resolveClient();

  static SupabaseClient? _resolveClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> startOAuth() async {
    final client = _supabase;
    if (client == null) {
      debugPrint(
        '[Google OAuth] Start failed: Supabase client is not initialized.',
      );
      throw Exception('Supabase client is not initialized.');
    }

    debugPrint('[Google OAuth] Invoking deployed google-auth action=start.');
    final response = await client.functions.invoke(
      'google-auth',
      body: {'action': 'start'},
    );

    if (response.status == 200 &&
        response.data != null &&
        response.data['auth_url'] != null) {
      debugPrint(
        '[Google OAuth] Start succeeded; browser authorization URL received.',
      );
      return response.data['auth_url'] as String;
    }

    final errorMessage =
        response.data?['message'] ??
        response.data?['error'] ??
        'Failed to initiate Google authentication (HTTP ${response.status}).';
    debugPrint('[Google OAuth] Start failed: HTTP ${response.status}.');
    throw Exception(errorMessage);
  }

  @override
  Future<GoogleIntegrationStatus> getStatus() async {
    final client = _supabase;
    if (client == null) {
      return const GoogleIntegrationStatus(
        state: GoogleConnectionState.notConnected,
      );
    }

    try {
      final response = await client.functions.invoke(
        'google-auth',
        body: {'action': 'status'},
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data;
        final isConnected = data['connected'] == true;
        return GoogleIntegrationStatus(
          state: isConnected
              ? GoogleConnectionState.connected
              : GoogleConnectionState.notConnected,
          email: data['email'] as String?,
          name: data['name'] as String?,
          updatedAt: data['updated_at'] != null
              ? DateTime.tryParse(data['updated_at'].toString())
              : null,
        );
      }
    } catch (_) {
      // Fallback: direct table query via Supabase RLS
    }

    final currentUser = client.auth.currentUser;
    if (currentUser != null) {
      try {
        final row = await client
            .from('user_integrations')
            .select('status, account_email, account_name, updated_at')
            .eq('user_id', currentUser.id)
            .eq('provider', 'google_drive')
            .maybeSingle();

        if (row != null && row['status'] == 'connected') {
          return GoogleIntegrationStatus(
            state: GoogleConnectionState.connected,
            email: row['account_email'] as String?,
            name: row['account_name'] as String?,
            updatedAt: row['updated_at'] != null
                ? DateTime.tryParse(row['updated_at'].toString())
                : null,
          );
        }
      } catch (_) {}
    }

    return const GoogleIntegrationStatus(
      state: GoogleConnectionState.notConnected,
    );
  }

  @override
  Future<void> disconnect() async {
    final client = _supabase;
    if (client == null) {
      debugPrint(
        '[Google OAuth] Disconnect failed: Supabase client is not initialized.',
      );
      throw Exception('Supabase client is not initialized.');
    }

    debugPrint(
      '[Google OAuth] Invoking deployed google-auth action=disconnect.',
    );
    final response = await client.functions.invoke(
      'google-auth',
      body: {'action': 'disconnect'},
    );

    if (response.status != 200) {
      debugPrint('[Google OAuth] Disconnect failed: HTTP ${response.status}.');
      final error =
          response.data?['error'] ??
          'Failed to disconnect Google account (HTTP ${response.status}).';
      throw Exception(error);
    }
    debugPrint('[Google OAuth] Disconnect request succeeded.');
  }

  @override
  Future<GoogleDocEntity> importDoc(String fileId) async {
    final client = _supabase;
    if (client == null) {
      throw const GoogleDocsImportException(
        code: 'CLIENT_NOT_INITIALIZED',
        message: 'Supabase client is not initialized.',
      );
    }

    try {
      final response = await client.functions.invoke(
        'google-auth',
        body: {'action': 'import_doc', 'fileId': fileId},
      );

      final statusCode = response.status;
      final data = response.data;

      if (statusCode == 200 && data != null && data['success'] == true) {
        if (data is Map<String, dynamic>) {
          return GoogleDocEntity.fromJson(data);
        } else if (data is Map) {
          return GoogleDocEntity.fromJson(Map<String, dynamic>.from(data));
        }
      }

      // Handle non-200 or unexpected response
      final errorCode = data is Map
          ? (data['error']?.toString() ?? 'IMPORT_FAILED')
          : 'IMPORT_FAILED';
      final errorMessage = data is Map
          ? (data['message']?.toString() ?? 'Failed to import Google Doc.')
          : 'Failed to import Google Doc.';
      throw GoogleDocsImportException(
        code: errorCode,
        message: errorMessage,
        statusCode: statusCode,
      );
    } on GoogleDocsImportException {
      rethrow;
    } catch (e) {
      // In supabase_flutter, non-200 responses may throw FunctionException
      if (e is FunctionException) {
        final details = e.details;
        String errorCode = 'IMPORT_FAILED';
        String errorMessage =
            e.reasonPhrase ?? 'Google Docs import failed (HTTP ${e.status}).';

        if (details is Map) {
          errorCode = details['error']?.toString() ?? errorCode;
          errorMessage = details['message']?.toString() ?? errorMessage;
        } else if (details is String && details.isNotEmpty) {
          try {
            final parsed = jsonDecode(details);
            if (parsed is Map) {
              errorCode = parsed['error']?.toString() ?? errorCode;
              errorMessage = parsed['message']?.toString() ?? errorMessage;
            }
          } catch (_) {
            errorMessage = details;
          }
        }

        throw GoogleDocsImportException(
          code: errorCode,
          message: errorMessage,
          statusCode: e.status,
        );
      }

      throw GoogleDocsImportException(
        code: 'UNKNOWN_ERROR',
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Future<String> startGooglePicker() async {
    final client = _supabase;
    if (client == null) {
      throw Exception('Supabase client is not initialized.');
    }

    try {
      final response = await client.functions.invoke(
        'google-auth',
        body: {'action': 'start_picker'},
      );

      if (response.status == 200 &&
          response.data != null &&
          response.data['auth_url'] != null) {
        return response.data['auth_url'] as String;
      }

      final errorMessage =
          response.data?['message'] ??
          response.data?['error'] ??
          'Failed to initiate Google Picker (HTTP ${response.status}).';
      throw Exception(errorMessage);
    } on FunctionException catch (e) {
      final details = e.details;
      String errorMessage =
          e.reasonPhrase ?? 'Failed to open Google Drive (HTTP ${e.status}).';
      if (details is Map) {
        errorMessage =
            details['message']?.toString() ??
            details['error']?.toString() ??
            errorMessage;
      } else if (details is String && details.isNotEmpty) {
        try {
          final parsed = jsonDecode(details);
          if (parsed is Map) {
            errorMessage =
                parsed['message']?.toString() ??
                parsed['error']?.toString() ??
                errorMessage;
          }
        } catch (_) {
          errorMessage = details;
        }
      }
      throw Exception(errorMessage);
    }
  }

  @override
  Future<GoogleDocEntity> importDriveFile(String fileId) async {
    return importDoc(fileId);
  }
}
