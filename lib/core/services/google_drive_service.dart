import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/integrations/domain/entities/google_doc_entity.dart';

class GoogleDriveService {
  static Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  @visibleForTesting
  static set dio(Dio client) => _dio = client;

  @visibleForTesting
  static Dio get dio => _dio;

  /// Cached OAuth access token from recent callback or session
  static String? cachedAccessToken;

  /// Scope constants for Google Drive integration
  static const String driveReadOnlyScope =
      'https://www.googleapis.com/auth/drive.readonly';
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';
  static const String fullDriveScopes =
      'https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file';

  /// Initiates Supabase OAuth with required Google Drive readonly & file scopes
  static Future<bool> signInWithGoogleOAuth({
    SupabaseClient? client,
    String? redirectTo,
  }) async {
    final supabase = client ?? Supabase.instance.client;
    clearSession();
    return await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      scopes: fullDriveScopes,
      queryParams: {
        'access_type': 'offline',
        'prompt': 'consent',
        'scopes': driveReadOnlyScope,
        'scope': fullDriveScopes,
      },
    );
  }

  /// Clears cached OAuth access token to force re-consent and re-authentication
  static void clearSession() {
    cachedAccessToken = null;
  }

  /// Resolves the current access token from cache or Supabase session
  static String? resolveAccessToken() {
    if (cachedAccessToken != null && cachedAccessToken!.isNotEmpty) {
      return cachedAccessToken;
    }
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final providerToken = session?.providerToken;
      if (providerToken != null && providerToken.isNotEmpty) {
        return providerToken;
      }
    } catch (_) {}
    return null;
  }

  /// Direct file metadata fetch from Google Drive REST API
  static Future<Map<String, dynamic>> getFileMetadata(
    String fileId, {
    required String accessToken,
  }) async {
    final response = await _dio.get(
      'https://www.googleapis.com/drive/v3/files/${Uri.encodeComponent(fileId)}',
      queryParameters: {
        'fields': 'id,name,mimeType,webViewLink,size,trashed',
        'supportsAllDrives': 'true',
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': '*/*',
        },
      ),
    );

    if (response.statusCode == 200 && response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    debugPrint('Drive Download Failed: ${response.statusCode} - ${response.data}');
    if (response.statusCode == 401 || response.statusCode == 403) {
      clearSession();
    }
    throw Exception(
      'Google Drive metadata request returned HTTP ${response.statusCode}: ${response.data}',
    );
  }

  /// Direct file download or Google Doc export via Google Drive REST API
  static Future<GoogleDocEntity> importFileDirect({
    required String fileId,
    required String accessToken,
  }) async {
    final meta = await getFileMetadata(fileId, accessToken: accessToken);
    final name = meta['name']?.toString() ?? 'Untitled Google Drive File';
    final mimeType = meta['mimeType']?.toString() ?? 'application/octet-stream';
    final webViewLink = meta['webViewLink']?.toString() ??
        'https://drive.google.com/file/d/$fileId/view';

    // Check File MimeType:
    // Native Google Workspace files must use the /export endpoint
    final isGoogleDoc = mimeType == 'application/vnd.google-apps.document';
    final isGoogleSheet = mimeType == 'application/vnd.google-apps.spreadsheet';
    final isGoogleSlide = mimeType == 'application/vnd.google-apps.presentation';
    final isGoogleWorkspace = isGoogleDoc || isGoogleSheet || isGoogleSlide;

    String content = '';
    String? mediaBase64;
    String? mediaType;
    String resolvedMime = mimeType;

    if (isGoogleWorkspace) {
      // 1. Export as PDF (rich document for multimodal viewing and processing)
      // https://www.googleapis.com/drive/v3/files/$fileId/export?mimeType=application/pdf
      Response<List<int>> pdfResponse;
      try {
        pdfResponse = await _dio.get<List<int>>(
          'https://www.googleapis.com/drive/v3/files/${Uri.encodeComponent(fileId)}/export',
          queryParameters: {'mimeType': 'application/pdf'},
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': '*/*',
            },
            responseType: ResponseType.bytes,
          ),
        );
      } on DioException catch (dioErr) {
        final bodyStr = dioErr.response?.data != null
            ? (dioErr.response!.data is List<int>
                ? utf8.decode(dioErr.response!.data as List<int>, allowMalformed: true)
                : dioErr.response!.data.toString())
            : (dioErr.message ?? 'Unknown Dio error');
        debugPrint('Drive Download Failed: ${dioErr.response?.statusCode} - $bodyStr');
        if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
          clearSession();
        }
        rethrow;
      }

      if (pdfResponse.statusCode != 200 || pdfResponse.data == null) {
        final bodyStr = pdfResponse.data != null
            ? (pdfResponse.data is List<int>
                ? utf8.decode(pdfResponse.data as List<int>, allowMalformed: true)
                : pdfResponse.data.toString())
            : 'null';
        debugPrint('Drive Download Failed: ${pdfResponse.statusCode} - $bodyStr');
        if (pdfResponse.statusCode == 401 || pdfResponse.statusCode == 403) {
          clearSession();
        }
        throw Exception(
          'Failed to export Google Workspace file (HTTP ${pdfResponse.statusCode}): $bodyStr',
        );
      }

      mediaBase64 = base64Encode(pdfResponse.data!);
      mediaType = 'pdf';
      resolvedMime = 'application/pdf';

      // 2. Also export as plain text / CSV for direct searchable plain text
      try {
        final textMime = isGoogleSheet ? 'text/csv' : 'text/plain';
        final textResponse = await _dio.get<String>(
          'https://www.googleapis.com/drive/v3/files/${Uri.encodeComponent(fileId)}/export',
          queryParameters: {'mimeType': textMime},
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': '*/*',
            },
            responseType: ResponseType.plain,
          ),
        );

        if (textResponse.statusCode == 200 && textResponse.data != null) {
          content = textResponse.data!.trim();
        }
      } catch (_) {
        // Optional text export failure is non-fatal since PDF is available
      }
    } else {
      // Standard binary file download via alt=media
      // For non-Google Docs (e.g. application/pdf):
      // Endpoint: https://www.googleapis.com/drive/v3/files/$fileId?alt=media&supportsAllDrives=true
      // Headers:
      //   'Authorization': 'Bearer $accessToken',
      //   'Accept': '*/*'
      Response<List<int>> fileResponse;
      try {
        fileResponse = await _dio.get<List<int>>(
          'https://www.googleapis.com/drive/v3/files/${Uri.encodeComponent(fileId)}',
          queryParameters: {
            'alt': 'media',
            'supportsAllDrives': 'true',
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': '*/*',
            },
            responseType: ResponseType.bytes,
          ),
        );
      } on DioException catch (dioErr) {
        final bodyStr = dioErr.response?.data != null
            ? (dioErr.response!.data is List<int>
                ? utf8.decode(dioErr.response!.data as List<int>, allowMalformed: true)
                : dioErr.response!.data.toString())
            : (dioErr.message ?? 'Unknown Dio error');
        debugPrint('Drive Download Failed: ${dioErr.response?.statusCode} - $bodyStr');
        if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
          clearSession();
        }
        rethrow;
      }

      if (fileResponse.statusCode != 200 || fileResponse.data == null) {
        final bodyStr = fileResponse.data != null
            ? (fileResponse.data is List<int>
                ? utf8.decode(fileResponse.data as List<int>, allowMalformed: true)
                : fileResponse.data.toString())
            : 'null';
        debugPrint('Drive Download Failed: ${fileResponse.statusCode} - $bodyStr');
        if (fileResponse.statusCode == 401 || fileResponse.statusCode == 403) {
          clearSession();
        }
        throw Exception(
          'Failed to download file (HTTP ${fileResponse.statusCode}): $bodyStr',
        );
      }

      final bytes = fileResponse.data!;
      final lowerName = name.toLowerCase();

      if (mimeType == 'application/pdf' || lowerName.endsWith('.pdf')) {
        mediaBase64 = base64Encode(bytes);
        mediaType = 'pdf';
        resolvedMime = 'application/pdf';
      } else if (mimeType.startsWith('image/') ||
          lowerName.endsWith('.png') ||
          lowerName.endsWith('.jpg') ||
          lowerName.endsWith('.jpeg')) {
        mediaBase64 = base64Encode(bytes);
        mediaType = 'image';
        resolvedMime = mimeType.startsWith('image/') ? mimeType : 'image/jpeg';
      } else if (mimeType.startsWith('text/') ||
          mimeType == 'application/json' ||
          mimeType == 'text/csv' ||
          lowerName.endsWith('.txt') ||
          lowerName.endsWith('.json') ||
          lowerName.endsWith('.csv') ||
          lowerName.endsWith('.md')) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else {
        mediaBase64 = base64Encode(bytes);
        mediaType = 'document';
      }
    }

    return GoogleDocEntity(
      success: true,
      fileId: fileId,
      title: name,
      content: content,
      mimeType: resolvedMime,
      webViewLink: webViewLink,
      extractionMethod: 'google_drive_direct',
      mediaBase64: mediaBase64,
      mediaType: mediaType,
    );
  }
}
