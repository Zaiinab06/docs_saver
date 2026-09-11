import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/memory_entity.dart';
import '../../domain/usecases/get_memories_usecase.dart';
import '../../domain/usecases/save_memory_usecase.dart';
import '../../domain/repositories/capture_repository.dart';
import 'capture_event.dart';
import 'capture_state.dart';

class CaptureBloc extends Bloc<CaptureEvent, CaptureState> {
  final SaveMemoryUseCase saveMemoryUseCase;
  final GetMemoriesUseCase getMemoriesUseCase;
  final CaptureRepository repository;

  CaptureBloc({
    required this.saveMemoryUseCase,
    required this.getMemoriesUseCase,
    required this.repository,
  }) : super(CaptureInitial()) {
    on<LoadMemoriesEvent>(_onLoadMemories);
    on<AddMemoryEvent>(_onAddMemory);
    on<SyncPendingMemoriesEvent>(_onSyncPendingMemories);
  }

  Future<void> _onLoadMemories(
    LoadMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    emit(CaptureLoading());
    try {
      final memories = await getMemoriesUseCase();
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
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User is not authenticated');
      }
      final now = DateTime.now();

      final newMemory = MemoryEntity(
        id: const Uuid().v4(),
        userId: currentUserId,
        title: event.title.trim().isEmpty ? 'Quick Note' : event.title.trim(),
        content: event.content.trim(),
        tags: event.tags,
        mediaUrl: event.mediaUrl,
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await saveMemoryUseCase(newMemory);
      emit(const CaptureSuccess('Memory saved locally!'));
      add(LoadMemoriesEvent());
    } catch (e) {
      emit(CaptureFailure(e.toString()));
    }
  }

  Future<void> _onSyncPendingMemories(
    SyncPendingMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    try {
      await repository.syncPendingMemories();
      add(LoadMemoriesEvent());
    } catch (_) {}
  }
}
