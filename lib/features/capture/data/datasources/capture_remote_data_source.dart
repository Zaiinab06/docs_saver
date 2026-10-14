import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/memory_entity.dart';
import '../models/memory_model.dart';

abstract class CaptureRemoteDataSource {
  Future<void> upsertMemory(MemoryEntity memory);
  Future<List<Map<String, dynamic>>> fetchRemoteMemories({String? userId});
  Stream<MemoryModel> subscribeToMemoryUpdates(String userId);
  Future<void> deleteMemory(String id) async {}
}

class CaptureRemoteDataSourceImpl implements CaptureRemoteDataSource {
  final SupabaseClient supabase;

  CaptureRemoteDataSourceImpl({SupabaseClient? client})
    : supabase = client ?? Supabase.instance.client;

  @override
  Future<void> deleteMemory(String id) async {
    await supabase.from('memories').delete().eq('id', id);
  }

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
  Future<List<Map<String, dynamic>>> fetchRemoteMemories({
    String? userId,
  }) async {
    var query = supabase.from('memories').select();
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }
    final response = await query.order('client_created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Stream<MemoryModel> subscribeToMemoryUpdates(String userId) {
    final controller = StreamController<MemoryModel>.broadcast();
    RealtimeChannel? channel;

    try {
      channel = supabase.channel('public:memories:$userId');

      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'memories',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              try {
                final record = payload.newRecord;
                if (record.isNotEmpty) {
                  final memoryModel = MemoryModel.fromMap(record, isSynced: true);
                  if (!controller.isClosed) {
                    controller.add(memoryModel);
                  }
                }
              } catch (e) {
                // Silently skip malformed payloads — do NOT error the stream
                debugPrint('[RealtimeSubscription] Payload parse error (suppressed): $e');
              }
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              debugPrint(
                '[RealtimeSubscription] Channel status=$status for user $userId '
                '(suppressed, will reconnect automatically): $error',
              );
              // Do NOT close or error the stream — Supabase handles reconnection
            }
          });
    } catch (e) {
      // Subscription setup failed (e.g. no internet on first try)
      debugPrint('[RealtimeSubscription] Channel creation failed (suppressed): $e');
    }

    controller.onCancel = () {
      try {
        channel?.unsubscribe();
        if (channel != null) supabase.removeChannel(channel);
      } catch (_) {}
    };

    return controller.stream;
  }
}
