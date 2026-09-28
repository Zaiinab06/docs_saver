import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/supabase_constants.dart';

abstract class AiRemoteDataSource {
  Future<Map<String, dynamic>> invokeIngestion({
    required String content,
    String? title,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
  });
}

class AiRemoteDataSourceImpl implements AiRemoteDataSource {
  final SupabaseClient supabase;

  AiRemoteDataSourceImpl({SupabaseClient? client})
      : supabase = client ?? Supabase.instance.client;

  @override
  Future<Map<String, dynamic>> invokeIngestion({
    required String content,
    String? title,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
  }) async {
    final currentUserId = supabase.auth.currentUser?.id ?? 'anonymous_client';
    final tempId = const Uuid().v4();

    final Map<String, dynamic> recordPayload = {
      'id': tempId,
      'user_id': currentUserId,
      'title': title,
      'content': content,
    };

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      recordPayload['image_base64'] = imageBase64;
    }
    if (documentBase64 != null && documentBase64.isNotEmpty) {
      recordPayload['document_base64'] = documentBase64;
    }
    if (videoBase64 != null && videoBase64.isNotEmpty) {
      recordPayload['video_base64'] = videoBase64;
    }
    if (mimeType != null && mimeType.isNotEmpty) {
      recordPayload['mime_type'] = mimeType;
    }

    final payload = {
      'record': recordPayload,
      'save_to_db': false, // Analysis only mode for review screen
    };

    debugPrint(
      '[AiRemoteDataSource] Invoking process-ingestion: userId=$currentUserId, keys=${recordPayload.keys.toList()}',
    );

    final Map<String, String> headers = {};
    if (SupabaseConstants.geminiApiKey.isNotEmpty) {
      headers['x-goog-api-key'] = SupabaseConstants.geminiApiKey;
    }

    FunctionResponse response;
    try {
      response = await supabase.functions.invoke(
        'process-ingestion',
        body: payload,
        headers: headers.isNotEmpty ? headers : null,
      );
    } on FunctionException catch (fe) {
      debugPrint('❌ SUPABASE EDGE FUNCTION ERROR: ${fe.status} - ${fe.details}');
      debugPrint('❌ FUNCTION EXCEPTION REASON: ${fe.reasonPhrase}');
      rethrow;
    } catch (e) {
      debugPrint('❌ SUPABASE INVOCATION EXCEPTION: $e');
      rethrow;
    }

    if (response.status != 200) {
      debugPrint('❌ SUPABASE EDGE FUNCTION ERROR: ${response.status} - ${response.data}');
      throw Exception(
        'AI ingestion failed with HTTP status ${response.status}: ${response.data}',
      );
    }

    final data = response.data;
    debugPrint(
      '[AiRemoteDataSource] Ingestion success. Status: ${response.status}',
    );

    if (data is Map && data['success'] == false && data['error'] != null) {
      debugPrint('❌ API RESPONSE ERROR BODY: ${data['error']}');
      throw Exception('AI ingestion error: ${data['error']}');
    }

    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception('Unexpected response format from AI ingestion: $data');
    }
  }
}
