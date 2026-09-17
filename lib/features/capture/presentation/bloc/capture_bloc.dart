import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/isar_service.dart';
import '../../data/models/memory_model.dart';
import '../../domain/entities/memory_entity.dart';
import '../../domain/usecases/get_memories_usecase.dart';
import '../../domain/usecases/save_memory_usecase.dart';
import '../../domain/usecases/subscribe_to_memories_usecase.dart';
import '../../domain/repositories/capture_repository.dart';
import 'capture_event.dart';
import 'capture_state.dart';

class CaptureBloc extends Bloc<CaptureEvent, CaptureState> {
  final SaveMemoryUseCase saveMemoryUseCase;
  final GetMemoriesUseCase getMemoriesUseCase;
  final SubscribeToMemoriesUseCase? subscribeToMemoriesUseCase;
  final CaptureRepository repository;

  StreamSubscription<MemoryEntity>? _realtimeSubscription;
  String? _subscribedUserId;

  CaptureBloc({
    required this.saveMemoryUseCase,
    required this.getMemoriesUseCase,
    this.subscribeToMemoriesUseCase,
    required this.repository,
  }) : super(CaptureInitial()) {
    on<LoadMemoriesEvent>(_onLoadMemories);
    on<AddMemoryEvent>(_onAddMemory);
    on<SyncPendingMemoriesEvent>(_onSyncPendingMemories);
    on<MemoryUpdatedEvent>(_onMemoryUpdated);
  }

  void _initRealtimeSubscription() {
    String? currentUserId;
    try {
      currentUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return;
    }
    if (currentUserId == null) return;
    if (_subscribedUserId == currentUserId && _realtimeSubscription != null) {
      return;
    }

    _realtimeSubscription?.cancel();
    _subscribedUserId = currentUserId;

    final stream = subscribeToMemoriesUseCase != null
        ? subscribeToMemoriesUseCase!(currentUserId)
        : repository.subscribeToMemoryUpdates(currentUserId);

    _realtimeSubscription = stream.listen(
      (updatedMemory) {
        add(MemoryUpdatedEvent(updatedMemory));
      },
      onError: (_) {},
    );
  }

  Future<void> _onLoadMemories(
    LoadMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    _initRealtimeSubscription();
    emit(CaptureLoading());
    try {
      String? currentUserId;
      try {
        currentUserId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}
      final memories = await getMemoriesUseCase(currentUserId);
      emit(CaptureLoaded(memories));
    } catch (e) {
      emit(CaptureFailure(e.toString()));
    }
  }

  Future<void> _onAddMemory(
    AddMemoryEvent event,
    Emitter<CaptureState> emit,
  ) async {
    try {
      String currentUserId = 'local_user';
      try {
        currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? 'local_user';
      } catch (_) {}

      final now = DateTime.now();

      final newMemory = MemoryEntity(
        id: const Uuid().v4(),
        userId: currentUserId,
        title: event.title.trim().isEmpty ? 'Quick Note' : event.title.trim(),
        content: event.content.trim(),
        tags: event.tags,
        category: event.category,
        mediaUrl: event.mediaUrl,
        aiStatus: event.aiStatus,
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await saveMemoryUseCase(newMemory);
      emit(const CaptureSuccess('Memory saved locally!'));
      add(LoadMemoriesEvent());

      // If memory requires AI analysis or is missing an embedding, trigger background enrichment/embedding
      bool isSupabaseAvailable = false;
      try {
        isSupabaseAvailable =
            Supabase.instance.client.auth.currentUser != null;
      } catch (_) {}

      final needsEmbedding =
          newMemory.embedding == null || newMemory.embedding!.isEmpty;
      final hasMeaningfulContent =
          newMemory.content.trim().isNotEmpty || newMemory.title.trim().isNotEmpty;

      if ((newMemory.aiStatus == 'pending' || needsEmbedding) &&
          hasMeaningfulContent &&
          isSupabaseAvailable) {
        final isNote = newMemory.mediaUrl == null || newMemory.mediaUrl!.isEmpty;
        unawaited(
          _triggerBackgroundIngestion(
            newMemory,
            isNote: isNote,
            isEmbeddingOnly: newMemory.aiStatus == 'processed',
          ),
        );
      }
    } catch (e) {
      emit(CaptureFailure(e.toString()));
    }
  }

  Future<void> _onSyncPendingMemories(
    SyncPendingMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    try {
      String? currentUserId;
      try {
        currentUserId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}
      await repository.syncPendingMemories(userId: currentUserId);
      add(LoadMemoriesEvent());

      // Trigger background enrichment/embedding for synced memories lacking embeddings
      if (currentUserId != null && currentUserId != 'local_user') {
        try {
          final memories = await repository.getMemories(userId: currentUserId);
          for (final mem in memories) {
            final needsEmbedding =
                mem.embedding == null || mem.embedding!.isEmpty;
            final hasMeaningfulContent =
                mem.content.trim().isNotEmpty || mem.title.trim().isNotEmpty;
            final isNote = mem.mediaUrl == null || mem.mediaUrl!.isEmpty;
            if ((mem.aiStatus == 'pending' || needsEmbedding) &&
                hasMeaningfulContent) {
              unawaited(
                _triggerBackgroundIngestion(
                  mem,
                  isNote: isNote,
                  isEmbeddingOnly: mem.aiStatus == 'processed',
                ),
              );
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _onMemoryUpdated(
    MemoryUpdatedEvent event,
    Emitter<CaptureState> emit,
  ) async {
    String? currentUserId;
    try {
      currentUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}

    // Enforce data isolation: ignore update if it doesn't belong to current user
    if (currentUserId != null &&
        event.updatedMemory.userId != currentUserId &&
        event.updatedMemory.userId != 'local_user') {
      return;
    }

    final currentMemories = state is CaptureLoaded
        ? (state as CaptureLoaded).memories
        : await getMemoriesUseCase(currentUserId);

    final index =
        currentMemories.indexWhere((m) => m.id == event.updatedMemory.id);

    final updatedList = List<MemoryEntity>.from(currentMemories);
    if (index != -1) {
      updatedList[index] = event.updatedMemory;
    } else {
      updatedList.insert(0, event.updatedMemory);
    }
    emit(CaptureLoaded(updatedList));
  }

  Future<void> _triggerBackgroundIngestion(
    MemoryEntity memory, {
    required bool isNote,
    required bool isEmbeddingOnly,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'process-ingestion',
        body: {
          'memoryId': memory.id,
          if (isNote) 'preserve_content': true,
          if (isEmbeddingOnly) 'embedding_only': true,
        },
      );

      await _handleIngestionComplete(
        memory.id,
        response,
        fallbackMemory: memory,
      );
    } catch (_) {
      // Background ingestion failed or network dropped — note remains in pending queue
    }
  }

  Future<void> _handleIngestionComplete(
    String memoryId,
    dynamic response, {
    required MemoryEntity fallbackMemory,
  }) async {
    try {
      // 1. Fetch freshly updated row directly from Supabase DB
      Map<String, dynamic>? remoteRow;
      try {
        final res = await Supabase.instance.client
            .from('memories')
            .select()
            .eq('id', memoryId)
            .maybeSingle();
        if (res != null) {
          remoteRow = Map<String, dynamic>.from(res);
        }
      } catch (_) {}

      // 2. Fallback to response.data if remote query didn't return
      Map<String, dynamic>? resData;
      if (response != null && response.data != null) {
        if (response.data is Map) {
          resData = Map<String, dynamic>.from(response.data as Map);
        } else if (response.data is String) {
          try {
            resData =
                Map<String, dynamic>.from(jsonDecode(response.data as String));
          } catch (_) {}
        }
      }

      // 3. Update local Isar database cache immediately
      MemoryEntity? updatedEntity;
      try {
        final isar = IsarService.instance;
        final existing = await isar.memoryModels
            .filter()
            .serverIdEqualTo(memoryId)
            .findFirst();

        if (existing != null) {
          if (remoteRow != null) {
            final remoteModel = MemoryModel.fromMap(remoteRow, isSynced: true);
            existing.title = remoteModel.title;
            existing.category = remoteModel.category;
            existing.tags = remoteModel.tags;
            existing.aiStatus = remoteModel.aiStatus;
            if (remoteModel.embedding != null) {
              existing.embedding = remoteModel.embedding;
            }
            existing.serverUpdatedAt = remoteModel.serverUpdatedAt;
            existing.isSynced = true;
          } else if (resData != null) {
            if (resData['title'] != null) {
              existing.title = resData['title'].toString();
            }
            if (resData['category'] != null) {
              existing.category = resData['category'].toString();
            }
            if (resData['tags'] != null) {
              existing.tags = List<String>.from(resData['tags'] as List);
            }
            existing.aiStatus =
                (resData['ai_status'] ?? 'processed').toString();
            existing.serverUpdatedAt = DateTime.now();
            existing.isSynced = true;
          }

          await isar.writeTxn(() async {
            await isar.memoryModels.put(existing);
          });

          updatedEntity = existing.toEntity();
        }
      } catch (_) {}

      // 4. Construct updated MemoryEntity if Isar was not open
      if (updatedEntity == null) {
        if (remoteRow != null) {
          updatedEntity =
              MemoryModel.fromMap(remoteRow, isSynced: true).toEntity();
        } else if (resData != null) {
          updatedEntity = MemoryEntity(
            id: memoryId,
            userId: fallbackMemory.userId,
            title: (resData['title'] ?? fallbackMemory.title).toString(),
            content: fallbackMemory.content,
            mediaUrl: fallbackMemory.mediaUrl,
            tags: resData['tags'] != null
                ? List<String>.from(resData['tags'] as List)
                : fallbackMemory.tags,
            category:
                (resData['category'] ?? fallbackMemory.category).toString(),
            embedding: fallbackMemory.embedding,
            aiStatus: (resData['ai_status'] ?? 'processed').toString(),
            isConflictCopy: fallbackMemory.isConflictCopy,
            clientCreatedAt: fallbackMemory.clientCreatedAt,
            clientUpdatedAt: fallbackMemory.clientUpdatedAt,
            serverUpdatedAt: DateTime.now(),
            isSynced: true,
          );
        }
      }

      // 5. Notify BLoC listeners immediately
      if (updatedEntity != null) {
        add(MemoryUpdatedEvent(updatedEntity));
      } else {
        add(LoadMemoriesEvent());
      }
    } catch (_) {
      add(LoadMemoriesEvent());
    }
  }

  @override
  Future<void> close() {
    _realtimeSubscription?.cancel();
    return super.close();
  }
}
