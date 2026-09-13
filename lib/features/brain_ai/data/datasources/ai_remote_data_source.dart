import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract class AiRemoteDataSource {
  Future<Map<String, dynamic>> invokeIngestion({
    required String content,
    String? title,
    String? imageBase64,
    String? mimeType,
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
    if (mimeType != null && mimeType.isNotEmpty) {
      recordPayload['mime_type'] = mimeType;
    }

    final payload = {
      'record': recordPayload,
      'save_to_db': false, // Analysis only mode for review screen
    };

    final response = await supabase.functions.invoke(
      'process-ingestion',
      body: payload,
    );

    if (response.status != 200) {
      throw Exception(
        'AI ingestion failed with HTTP status ${response.status}: ${response.data}',
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception('Unexpected response format from AI ingestion: $data');
    }
  }
}
