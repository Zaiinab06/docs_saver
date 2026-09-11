import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/memory_entity.dart';

abstract class CaptureRemoteDataSource {
  Future<void> upsertMemory(MemoryEntity memory);
  Future<List<Map<String, dynamic>>> fetchRemoteMemories();
}

class CaptureRemoteDataSourceImpl implements CaptureRemoteDataSource {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  Future<void> upsertMemory(MemoryEntity memory) async {
    final payload = {
      'id': memory.id,
      'user_id': memory.userId,
      'title': memory.title,
      'content': memory.content,
      'media_url': memory.mediaUrl,
      'tags': memory.tags,
      'category': memory.category,
      'embedding': memory.embedding,
      'ai_status': memory.aiStatus,
      'is_conflict_copy': memory.isConflictCopy,
      'client_created_at': memory.clientCreatedAt.toIso8601String(),
      'client_updated_at': memory.clientUpdatedAt.toIso8601String(),
    };

    await supabase.from('memories').upsert(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRemoteMemories() async {
    final response = await supabase
        .from('memories')
        .select()
        .order('client_created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}
