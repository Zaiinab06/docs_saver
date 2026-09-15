import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
        unawaited(
          Supabase.instance.client.functions
              .invoke('process-ingestion', body: {
                'memoryId': newMemory.id,
                if (newMemory.aiStatus == 'processed') 'embedding_only': true,
              })
              .then((_) => add(LoadMemoriesEvent()))
              .catchError((_) {}),
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
            if ((mem.aiStatus == 'pending' || needsEmbedding) &&
                hasMeaningfulContent) {
              unawaited(
                Supabase.instance.client.functions
                    .invoke('process-ingestion', body: {
                      'memoryId': mem.id,
                      if (mem.aiStatus == 'processed') 'embedding_only': true,
                    })
                    .then((_) => add(LoadMemoriesEvent()))
                    .catchError((_) {}),
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

    if (state is CaptureLoaded) {
      final currentMemories = (state as CaptureLoaded).memories;
      final index =
          currentMemories.indexWhere((m) => m.id == event.updatedMemory.id);

      if (index != -1) {
        final updatedList = List<MemoryEntity>.from(currentMemories);
        updatedList[index] = event.updatedMemory;
        emit(CaptureLoaded(updatedList));
      } else {
        final memories = await getMemoriesUseCase(currentUserId);
        emit(CaptureLoaded(memories));
      }
    } else {
      final memories = await getMemoriesUseCase(currentUserId);
      emit(CaptureLoaded(memories));
    }
  }

  @override
  Future<void> close() {
    _realtimeSubscription?.cancel();
    return super.close();
  }
}
