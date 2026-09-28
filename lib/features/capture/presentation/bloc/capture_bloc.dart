import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/network_checker.dart';
import '../../../../core/services/gemini_direct_service.dart';
import '../../../../core/services/isar_service.dart';
import '../../../../core/services/video_frame_extractor.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/repositories/ai_repository.dart';
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
  final AiRepository? aiRepository;
  final Duration syncDebounceDuration;

  StreamSubscription<MemoryEntity>? _realtimeSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _connectivityDebounceTimer;
  String? _subscribedUserId;
  bool _wasOffline = false;
  bool _isSyncing = false;

  CaptureBloc({
    required this.saveMemoryUseCase,
    required this.getMemoriesUseCase,
    this.subscribeToMemoriesUseCase,
    required this.repository,
    this.aiRepository,
    this.syncDebounceDuration = const Duration(milliseconds: 500),
    Stream<bool>? connectivityStream,
  }) : super(CaptureInitial()) {
    on<LoadMemoriesEvent>(_onLoadMemories);
    on<ClearMemoriesEvent>(_onClearMemories);
    on<AddMemoryEvent>(_onAddMemory);
    on<DeleteMemoryEvent>(_onDeleteMemory);
    on<SyncPendingMemoriesEvent>(_onSyncPendingMemories);
    on<MemoryUpdatedEvent>(_onMemoryUpdated);
    on<RetryMemoryIngestionEvent>(_onRetryMemoryIngestion);

    _initConnectivityListener(
      connectivityStream ?? NetworkChecker.onConnectivityChanged,
    );
  }

  void _initConnectivityListener(Stream<bool> connectivityStream) {
    _connectivitySubscription = connectivityStream.listen((isOnline) {
      if (!isOnline) {
        _wasOffline = true;
        _connectivityDebounceTimer?.cancel();
        return;
      }

      // Transition to online: debounce to prevent rapid-fire sync bursts
      if (_wasOffline || isOnline) {
        _wasOffline = false;
        _connectivityDebounceTimer?.cancel();
        if (syncDebounceDuration == Duration.zero) {
          if (!isClosed) {
            add(SyncPendingMemoriesEvent());
          }
        } else {
          _connectivityDebounceTimer = Timer(syncDebounceDuration, () {
            if (!isClosed) {
              add(SyncPendingMemoriesEvent());
            }
          });
        }
      }
    });
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

    _realtimeSubscription = stream.listen((updatedMemory) {
      add(MemoryUpdatedEvent(updatedMemory));
    }, onError: (_) {});
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

  Future<void> _onClearMemories(
    ClearMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _subscribedUserId = null;
    emit(const CaptureLoaded([]));
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
        metadata: event.metadata,
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      await saveMemoryUseCase(newMemory);
      emit(const CaptureSuccess('Memory saved locally!'));
      add(LoadMemoriesEvent());

      // If memory requires AI analysis or is missing an embedding, trigger background enrichment/embedding
      bool isNetworkAvailable = false;
      try {
        isNetworkAvailable = await NetworkChecker.isConnected();
      } catch (_) {}

      final needsEmbedding =
          newMemory.embedding == null || newMemory.embedding!.isEmpty;
      final isVoice =
          newMemory.tags.any((t) => t.toLowerCase() == 'voice') ||
          (newMemory.mediaUrl != null &&
              (newMemory.mediaUrl!.endsWith('.m4a') ||
                  newMemory.mediaUrl!.endsWith('.aac') ||
                  newMemory.mediaUrl!.endsWith('.mp3') ||
                  newMemory.mediaUrl!.endsWith('.wav')));
      final isPdf =
          (newMemory.mediaUrl != null &&
              newMemory.mediaUrl!.toLowerCase().endsWith('.pdf')) ||
          newMemory.tags.any((t) => t.toLowerCase() == 'pdf');
      final isVideo =
          newMemory.isVideo ||
          newMemory.fileType == 'video' ||
          newMemory.tags.any((t) => t.toLowerCase() == 'video') ||
          (newMemory.metadata != null &&
              newMemory.metadata!['file_type'] == 'video') ||
          (newMemory.mediaUrl != null &&
              (newMemory.mediaUrl!.toLowerCase().endsWith('.mp4') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.mov') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.avi') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.mkv') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.webm') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.3gp') ||
                  newMemory.mediaUrl!.toLowerCase().endsWith('.m4v')));
      final isImage =
          !isVideo &&
          !isVoice &&
          !isPdf &&
          ((newMemory.mediaUrl != null &&
                  (newMemory.mediaUrl!.toLowerCase().endsWith('.jpg') ||
                      newMemory.mediaUrl!.toLowerCase().endsWith('.jpeg') ||
                      newMemory.mediaUrl!.toLowerCase().endsWith('.png') ||
                      newMemory.mediaUrl!.toLowerCase().endsWith('.webp') ||
                      newMemory.mediaUrl!.toLowerCase().endsWith('.heic'))) ||
              newMemory.tags.any(
                (t) =>
                    t.toLowerCase() == 'photo' ||
                    t.toLowerCase() == 'image' ||
                    t.toLowerCase() == 'document',
              ) ||
              newMemory.fileType == 'image' ||
              newMemory.fileType == 'photo');
      final hasMeaningfulContent =
          newMemory.content.trim().isNotEmpty ||
          newMemory.title.trim().isNotEmpty ||
          isVoice ||
          isPdf ||
          isVideo ||
          isImage;

      if ((newMemory.aiStatus == 'pending' || needsEmbedding) &&
          hasMeaningfulContent &&
          isNetworkAvailable) {
        final isNote =
            (newMemory.mediaUrl == null || newMemory.mediaUrl!.isEmpty) &&
            !isVoice &&
            !isPdf &&
            !isVideo &&
            !isImage;
        unawaited(
          _triggerBackgroundIngestion(
            newMemory,
            isNote: isNote,
            isVoice: isVoice,
            isPdf: isPdf,
            isVideo: isVideo,
            isImage: isImage,
            isEmbeddingOnly: newMemory.aiStatus == 'processed',
          ),
        );
      }
    } catch (e) {
      emit(CaptureFailure(e.toString()));
    }
  }

  Future<void> _onDeleteMemory(
    DeleteMemoryEvent event,
    Emitter<CaptureState> emit,
  ) async {
    try {
      await repository.deleteMemory(event.memoryId);
      add(LoadMemoriesEvent());
    } catch (e) {
      emit(CaptureFailure(e.toString()));
    }
  }

  Future<void> _onSyncPendingMemories(
    SyncPendingMemoriesEvent event,
    Emitter<CaptureState> emit,
  ) async {
    if (_isSyncing) return;
    _isSyncing = true;
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
            final isVoice =
                mem.tags.any((t) => t.toLowerCase() == 'voice') ||
                (mem.mediaUrl != null &&
                    (mem.mediaUrl!.endsWith('.m4a') ||
                        mem.mediaUrl!.endsWith('.aac') ||
                        mem.mediaUrl!.endsWith('.mp3') ||
                        mem.mediaUrl!.endsWith('.wav')));
            final isPdf =
                (mem.mediaUrl != null &&
                    mem.mediaUrl!.toLowerCase().endsWith('.pdf')) ||
                mem.tags.any((t) => t.toLowerCase() == 'pdf');
            final isVideo =
                mem.isVideo ||
                mem.fileType == 'video' ||
                mem.tags.any((t) => t.toLowerCase() == 'video') ||
                (mem.mediaUrl != null &&
                    (mem.mediaUrl!.toLowerCase().endsWith('.mp4') ||
                        mem.mediaUrl!.toLowerCase().endsWith('.mov') ||
                        mem.mediaUrl!.toLowerCase().endsWith('.avi') ||
                        mem.mediaUrl!.toLowerCase().endsWith('.mkv') ||
                        mem.mediaUrl!.toLowerCase().endsWith('.webm')));
            final isImage =
                !isVideo &&
                !isVoice &&
                !isPdf &&
                ((mem.mediaUrl != null &&
                        (mem.mediaUrl!.toLowerCase().endsWith('.jpg') ||
                            mem.mediaUrl!.toLowerCase().endsWith('.jpeg') ||
                            mem.mediaUrl!.toLowerCase().endsWith('.png') ||
                            mem.mediaUrl!.toLowerCase().endsWith('.webp') ||
                            mem.mediaUrl!.toLowerCase().endsWith('.heic'))) ||
                    mem.tags.any(
                      (t) =>
                          t.toLowerCase() == 'photo' ||
                          t.toLowerCase() == 'image' ||
                          t.toLowerCase() == 'document',
                    ) ||
                    mem.fileType == 'image' ||
                    mem.fileType == 'photo');
            final hasMeaningfulContent =
                mem.content.trim().isNotEmpty ||
                mem.title.trim().isNotEmpty ||
                isVoice ||
                isPdf ||
                isVideo ||
                isImage;
            final isNote =
                (mem.mediaUrl == null || mem.mediaUrl!.isEmpty) &&
                !isVoice &&
                !isPdf &&
                !isVideo &&
                !isImage;
            if ((mem.aiStatus == 'pending' || needsEmbedding) &&
                hasMeaningfulContent) {
              unawaited(
                _triggerBackgroundIngestion(
                  mem,
                  isNote: isNote,
                  isVoice: isVoice,
                  isPdf: isPdf,
                  isVideo: isVideo,
                  isImage: isImage,
                  isEmbeddingOnly: mem.aiStatus == 'processed',
                ),
              );
            }
          }
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
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

    final index = currentMemories.indexWhere(
      (m) => m.id == event.updatedMemory.id,
    );

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
    bool isVoice = false,
    bool isPdf = false,
    bool isVideo = false,
    bool isImage = false,
    required bool isEmbeddingOnly,
  }) async {
    try {
      String? audioBase64;
      String? documentBase64;
      String? mimeType;

      if (isVoice && memory.mediaUrl != null && memory.mediaUrl!.isNotEmpty) {
        debugPrint('🎙️ AUDIO PROCESSING STARTED');
        final stopwatch = Stopwatch()..start();
        try {
          final file = File(memory.mediaUrl!);
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            final isMp3 = memory.mediaUrl!.toLowerCase().endsWith('.mp3');
            mimeType = isMp3 ? 'audio/mp3' : 'audio/m4a';
            audioBase64 = await Isolate.run(() => base64Encode(bytes));

            // Background cloud storage upload if authenticated (unawaited so transcription starts immediately)
            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
            if (currentUserId != null && currentUserId != 'local_user') {
              final ext = isMp3 ? 'mp3' : 'm4a';
              final fileName =
                  'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final storageKey = '$currentUserId/$fileName';
              unawaited(() async {
                try {
                  await Supabase.instance.client.storage
                      .from('memories')
                      .uploadBinary(
                        storageKey,
                        bytes,
                        fileOptions: FileOptions(contentType: mimeType!),
                      );
                  final publicUrl = Supabase.instance.client.storage
                      .from('memories')
                      .getPublicUrl(storageKey);
                  if (publicUrl.isNotEmpty) {
                    final isar = IsarService.instance;
                    final existing = await isar.memoryModels
                        .filter()
                        .serverIdEqualTo(memory.id)
                        .findFirst();
                    if (existing != null) {
                      existing.mediaUrl = publicUrl;
                      await isar.writeTxn(() async {
                        await isar.memoryModels.put(existing);
                      });
                    }
                    await Supabase.instance.client
                        .from('memories')
                        .update({'media_url': publicUrl})
                        .eq('id', memory.id);
                  }
                } catch (e) {
                  debugPrint('[VoiceAI Warning] Cloud storage upload failed: $e');
                }
              }());
            }

            debugPrint(
              '[VoiceAI] Invoking GeminiDirectService with audio (${bytes.lengthInBytes} bytes, mimeType=$mimeType)...',
            );
            Map<String, dynamic> data = {};
            try {
              data = await GeminiDirectService.analyzeDirect(
                ocrText:
                    'Transcribe all spoken words and extract structured metadata with title, category, summary, and tags.',
                audioBase64: audioBase64,
                mimeType: mimeType,
              );
            } catch (e) {
              debugPrint('[VoiceAI Warning] Direct Gemini audio analysis failed: $e');
            }

            if (data.isNotEmpty) {
              final rawTitle = (data['title'] ?? '').toString().trim();
              final rawCategory = (data['category'] ?? '').toString().trim();
              final rawSummary = (data['summary'] ?? '').toString().trim();
              final rawTranscript =
                  (data['transcript'] ?? '').toString().trim();
              final List<String> tags = [];
              if (data['tags'] is List) {
                tags.addAll(
                  (data['tags'] as List).map(
                    (t) => t.toString().toLowerCase().replaceAll('#', ''),
                  ),
                );
              }

              final aiResult = AiIngestionResult(
                title: rawTitle.isNotEmpty ? rawTitle : 'Voice Note',
                category: rawCategory.isNotEmpty ? rawCategory : 'Personal',
                tags: tags,
                summary: rawSummary,
                aiStatus: 'processed',
                rawOcrText: rawTranscript,
              );

              debugPrint(
                '🎙️ AUDIO PROCESSING COMPLETED in ${stopwatch.elapsedMilliseconds}ms: title="${aiResult.title}", transcript="${aiResult.rawOcrText}"',
              );

              await _updateMemoryWithVoiceAiResult(
                memoryId: memory.id,
                aiResult: aiResult,
                originalMemory: memory,
              );
              return;
            }
          }
        } catch (e, stack) {
          debugPrint('❌ [VoiceAI Error] Audio processing failed: $e\n$stack');
        }
      } else if (isPdf &&
          memory.mediaUrl != null &&
          memory.mediaUrl!.isNotEmpty) {
        try {
          final file = File(memory.mediaUrl!);
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            documentBase64 = await Isolate.run(() => base64Encode(bytes));
            mimeType = 'application/pdf';

            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
            if (currentUserId != null && currentUserId != 'local_user') {
              final fileName =
                  'doc_${DateTime.now().millisecondsSinceEpoch}.pdf';
              final storageKey = '$currentUserId/$fileName';
              await Supabase.instance.client.storage
                  .from('memories')
                  .uploadBinary(
                    storageKey,
                    bytes,
                    fileOptions: const FileOptions(
                      contentType: 'application/pdf',
                    ),
                  );
              final publicUrl = Supabase.instance.client.storage
                  .from('memories')
                  .getPublicUrl(storageKey);
              if (publicUrl.isNotEmpty) {
                final isar = IsarService.instance;
                final existing = await isar.memoryModels
                    .filter()
                    .serverIdEqualTo(memory.id)
                    .findFirst();
                if (existing != null) {
                  existing.mediaUrl = publicUrl;
                  await isar.writeTxn(() async {
                    await isar.memoryModels.put(existing);
                  });
                }
                await Supabase.instance.client
                    .from('memories')
                    .update({'media_url': publicUrl})
                    .eq('id', memory.id);
              }
            }
          }
        } catch (_) {}
      } else if (isVideo &&
          memory.mediaUrl != null &&
          memory.mediaUrl!.isNotEmpty) {
        debugPrint(
          '[VideoAI] Processing video memory with Gemini Vision: id=${memory.id}, mediaUrl=${memory.mediaUrl}',
        );

        // 1. Storage Upload for cloud playback (if authenticated)
        String? storagePublicUrl;
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null && currentUserId != 'local_user') {
          try {
            final file = File(memory.mediaUrl!);
            if (file.existsSync()) {
              final isMov = memory.mediaUrl!.toLowerCase().endsWith('.mov');
              final ext = isMov ? 'mov' : 'mp4';
              final mime = isMov ? 'video/quicktime' : 'video/mp4';
              final fileName =
                  'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final storageKey = '$currentUserId/$fileName';
              debugPrint('[VideoAI] Uploading video binary to storage: $storageKey');
              final bytes = await file.readAsBytes();
              await Supabase.instance.client.storage
                  .from('memories')
                  .uploadBinary(
                    storageKey,
                    bytes,
                    fileOptions: FileOptions(contentType: mime),
                  );
              storagePublicUrl = Supabase.instance.client.storage
                  .from('memories')
                  .getPublicUrl(storageKey);
              debugPrint('[VideoAI] Video storage upload success: $storagePublicUrl');
            }
          } catch (e) {
            debugPrint('[VideoAI Warning] Video storage upload failed: $e');
          }
        }

        // 2. Extract representative frame(s) using VideoFrameExtractor
        Uint8List? frameBytes;
        try {
          frameBytes = await VideoFrameExtractor.extractRepresentativeFrame(
            memory.mediaUrl!,
          );
        } catch (e) {
          debugPrint('[VideoAI Warning] Frame extraction failed: $e');
        }

        if (frameBytes != null && frameBytes.isNotEmpty) {
          // 3. Client-Side AI Ingestion via Gemini Vision pipeline (same as Photo)
          final frameBase64 = await Isolate.run(() => base64Encode(frameBytes!));
          const videoPrompt =
              'Analyze this video frame/scene. Provide a concise, descriptive title, detailed bulleted summary of visible scene/objects/actions, suitable category, and 4-6 specific tags.';

          final effectiveAiRepo = aiRepository ??
              AiRepositoryImpl(
                remoteDataSource: AiRemoteDataSourceImpl(),
              );

          debugPrint(
            '[VideoAI] Invoking Gemini Vision pipeline with frame (${frameBytes.lengthInBytes} bytes)...',
          );
          final aiResult = await effectiveAiRepo.processPhotoIngestion(
            ocrText: videoPrompt,
            imageBase64: frameBase64,
            mimeType: 'image/jpeg',
          );
          debugPrint(
            '[VideoAI] Gemini Vision response: title="${aiResult.title}", category="${aiResult.category}", tags=${aiResult.tags}, summary="${aiResult.summary}"',
          );

          if (aiResult.title.isNotEmpty || aiResult.summary.isNotEmpty) {
            await _updateMemoryWithVideoAiResult(
              memoryId: memory.id,
              aiResult: aiResult,
              originalMemory: memory,
              mediaUrl: storagePublicUrl,
            );
            return;
          }
        } else {
          debugPrint(
            '[VideoAI Warning] Frame extraction returned null. Proceeding to fallback.',
          );
        }
      } else if (isImage &&
          memory.mediaUrl != null &&
          memory.mediaUrl!.isNotEmpty) {
        debugPrint(
          '[PhotoAI] Processing photo memory with Gemini Vision: id=${memory.id}, mediaUrl=${memory.mediaUrl}',
        );

        // 1. Storage Upload for cloud backup (if authenticated)
        String? storagePublicUrl;
        String? currentUserId;
        try {
          currentUserId = Supabase.instance.client.auth.currentUser?.id;
        } catch (_) {}
        final file = File(memory.mediaUrl!);
        if (currentUserId != null && currentUserId != 'local_user' && file.existsSync()) {
          try {
            final isPng = memory.mediaUrl!.toLowerCase().endsWith('.png');
            final ext = isPng ? 'png' : 'jpg';
            final mime = isPng ? 'image/png' : 'image/jpeg';
            final fileName =
                'photo_${DateTime.now().millisecondsSinceEpoch}.$ext';
            final storageKey = '$currentUserId/$fileName';
            debugPrint('[PhotoAI] Uploading photo binary to storage: $storageKey');
            final bytes = await file.readAsBytes();
            await Supabase.instance.client.storage
                .from('memories')
                .uploadBinary(
                  storageKey,
                  bytes,
                  fileOptions: FileOptions(contentType: mime),
                );
            storagePublicUrl = Supabase.instance.client.storage
                .from('memories')
                .getPublicUrl(storageKey);
            debugPrint('[PhotoAI] Photo storage upload success: $storagePublicUrl');
          } catch (e) {
            debugPrint('[PhotoAI Warning] Photo storage upload failed: $e');
          }
        }

        // 2. Read local image bytes and encode to base64
        if (file.existsSync()) {
          try {
            final fileSize = await file.length();
            if (fileSize < 12 * 1024 * 1024) {
              final bytes = await file.readAsBytes();
              final imageBase64 = base64Encode(bytes);
              final isPng = memory.mediaUrl!.toLowerCase().endsWith('.png');
              final mime = isPng ? 'image/png' : 'image/jpeg';

              final effectiveAiRepo = aiRepository ??
                  AiRepositoryImpl(
                    remoteDataSource: AiRemoteDataSourceImpl(),
                  );

              final promptText = memory.content.isNotEmpty &&
                      memory.content != 'Captured Visual Memory'
                  ? memory.content
                  : 'Analyze this photo/document. Extract all visible text accurately, provide a concise descriptive title, detailed summary, suitable category, and 4-6 specific tags.';

              debugPrint(
                '[PhotoAI] Invoking Gemini Vision pipeline (${bytes.lengthInBytes} bytes)...',
              );
              final aiResult = await effectiveAiRepo.processPhotoIngestion(
                ocrText: promptText,
                imageBase64: imageBase64,
                mimeType: mime,
              );
              debugPrint(
                '[PhotoAI] Gemini Vision response: title="${aiResult.title}", category="${aiResult.category}", tags=${aiResult.tags}, summary="${aiResult.summary}"',
              );

              if (aiResult.title.isNotEmpty ||
                  aiResult.summary.isNotEmpty ||
                  aiResult.aiStatus == 'processed') {
                await _updateMemoryWithPhotoAiResult(
                  memoryId: memory.id,
                  aiResult: aiResult,
                  originalMemory: memory,
                  mediaUrl: storagePublicUrl,
                );
                return;
              }
            } else {
              debugPrint('[PhotoAI Warning] Photo file exceeds 12MB limit.');
            }
          } catch (e, stack) {
            debugPrint('[PhotoAI Error] Photo AI ingestion failed: $e\n$stack');
          }
        }
      }

      final payload = {
        'memoryId': memory.id,
        if (isNote) 'preserve_content': true,
        if (isEmbeddingOnly) 'embedding_only': true,
        if (audioBase64 != null) 'audio_base64': audioBase64,
        if (documentBase64 != null) 'document_base64': documentBase64,
        if (mimeType != null) 'mime_type': mimeType,
      };

      debugPrint(
        '[AI Ingestion] Invoking process-ingestion for ${memory.id}, keys=${payload.keys.toList()}',
      );
      SupabaseClient? client;
      try {
        client = Supabase.instance.client;
      } catch (_) {}

      if (client == null) {
        debugPrint('[AI Ingestion] Supabase not initialized. Skipping cloud ingestion.');
        return;
      }

      final response = await client.functions.invoke(
        'process-ingestion',
        body: payload,
      );
      debugPrint(
        '[AI Ingestion] Ingestion response received: status=${response.status}, data=${response.data}',
      );

      await _handleIngestionComplete(
        memory.id,
        response,
        fallbackMemory: memory,
      );
    } catch (e, stack) {
      debugPrint('[VideoAI Error] Background ingestion failed: $e\n$stack');
    }
  }

  Future<void> _updateMemoryWithVideoAiResult({
    required String memoryId,
    required AiIngestionResult aiResult,
    required MemoryEntity originalMemory,
    String? mediaUrl,
  }) async {
    try {
      final isar = IsarService.instance;
      final existing = await isar.memoryModels
          .filter()
          .serverIdEqualTo(memoryId)
          .findFirst();

      final effectiveTitle = aiResult.title.isNotEmpty
          ? aiResult.title
          : originalMemory.title;
      final effectiveCategory = aiResult.category.isNotEmpty
          ? aiResult.category
          : (originalMemory.category.isNotEmpty &&
                  originalMemory.category != 'General'
              ? originalMemory.category
              : 'General');
      final effectiveContent = aiResult.summary.isNotEmpty
          ? aiResult.summary
          : (aiResult.title.isNotEmpty
              ? aiResult.title
              : originalMemory.content);

      final mergedTagsSet = <String>{};
      if (existing != null) {
        mergedTagsSet.addAll(existing.tags);
      } else {
        mergedTagsSet.addAll(originalMemory.tags);
      }
      mergedTagsSet.addAll(aiResult.tags);
      mergedTagsSet.add('video');
      final effectiveTags = mergedTagsSet.toList();

      final meta = Map<String, dynamic>.from(
        originalMemory.metadata ?? {},
      );
      if (aiResult.summary.isNotEmpty) {
        meta['summary'] = aiResult.summary;
      }
      meta['file_type'] = 'video';

      // 1. Update Isar cache
      if (existing != null) {
        existing.title = effectiveTitle;
        existing.category = effectiveCategory;
        existing.tags = effectiveTags;
        existing.content = effectiveContent;
        existing.metadata = meta;
        existing.aiStatus = 'processed';
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          existing.mediaUrl = mediaUrl;
        }
        await isar.writeTxn(() async {
          await isar.memoryModels.put(existing);
        });
        debugPrint('[VideoAI] Isar MemoryModel updated for $memoryId');
      }

      // 2. Update Supabase DB if user is logged in
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && currentUserId != 'local_user') {
        try {
          await Supabase.instance.client.from('memories').update({
            'title': effectiveTitle,
            'category': effectiveCategory,
            'tags': effectiveTags,
            'content': effectiveContent,
            'ai_status': 'processed',
            'metadata': meta,
            if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
          }).eq('id', memoryId);
          debugPrint('[VideoAI] Supabase DB updated for $memoryId');
        } catch (e) {
          debugPrint('[VideoAI Warning] Supabase DB update error: $e');
        }
      }

      // 3. Emit updated state to all listeners
      final updatedEntity = (existing?.toEntity() ?? originalMemory).copyWith(
        title: effectiveTitle,
        category: effectiveCategory,
        tags: effectiveTags,
        content: effectiveContent,
        aiStatus: 'processed',
        metadata: meta,
        mediaUrl: mediaUrl ?? (existing?.mediaUrl ?? originalMemory.mediaUrl),
      );
      add(MemoryUpdatedEvent(updatedEntity));
      add(LoadMemoriesEvent());
    } catch (e, stack) {
      debugPrint(
        '[VideoAI Error] _updateMemoryWithVideoAiResult error: $e\n$stack',
      );
    }
  }

  Future<void> _updateMemoryWithPhotoAiResult({
    required String memoryId,
    required AiIngestionResult aiResult,
    required MemoryEntity originalMemory,
    String? mediaUrl,
  }) async {
    try {
      final isar = IsarService.instance;
      final existing = await isar.memoryModels
          .filter()
          .serverIdEqualTo(memoryId)
          .findFirst();

      final effectiveTitle = aiResult.title.isNotEmpty
          ? aiResult.title
          : originalMemory.title;
      final effectiveCategory = aiResult.category.isNotEmpty
          ? aiResult.category
          : (originalMemory.category.isNotEmpty &&
                  originalMemory.category != 'General'
              ? originalMemory.category
              : 'General');
      final effectiveContent = aiResult.summary.isNotEmpty
          ? aiResult.summary
          : (aiResult.documentText != null && aiResult.documentText!.isNotEmpty
              ? aiResult.documentText!
              : (originalMemory.content.isNotEmpty &&
                      originalMemory.content != 'Captured Visual Memory'
                  ? originalMemory.content
                  : (aiResult.title.isNotEmpty
                      ? aiResult.title
                      : 'Captured Visual Memory')));

      final mergedTagsSet = <String>{};
      if (existing != null) {
        mergedTagsSet.addAll(existing.tags);
      } else {
        mergedTagsSet.addAll(originalMemory.tags);
      }
      mergedTagsSet.addAll(aiResult.tags);
      if (!mergedTagsSet.contains('photo') && !mergedTagsSet.contains('document')) {
        mergedTagsSet.add('photo');
      }
      final effectiveTags = mergedTagsSet.toList();

      final meta = Map<String, dynamic>.from(
        originalMemory.metadata ?? {},
      );
      if (aiResult.summary.isNotEmpty) {
        meta['summary'] = aiResult.summary;
      }
      if (aiResult.documentText != null && aiResult.documentText!.isNotEmpty) {
        meta['document_text'] = aiResult.documentText!;
      }
      meta['file_type'] = 'image';

      // 1. Update Isar cache
      if (existing != null) {
        existing.title = effectiveTitle;
        existing.category = effectiveCategory;
        existing.tags = effectiveTags;
        existing.content = effectiveContent;
        existing.metadata = meta;
        existing.aiStatus = 'processed';
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          existing.mediaUrl = mediaUrl;
        }
        await isar.writeTxn(() async {
          await isar.memoryModels.put(existing);
        });
        debugPrint('[PhotoAI] Isar MemoryModel updated for $memoryId');
      }

      // 2. Update Supabase DB if user is logged in
      String? currentUserId;
      try {
        currentUserId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}
      if (currentUserId != null && currentUserId != 'local_user') {
        try {
          await Supabase.instance.client.from('memories').update({
            'title': effectiveTitle,
            'category': effectiveCategory,
            'tags': effectiveTags,
            'content': effectiveContent,
            'ai_status': 'processed',
            'metadata': meta,
            if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
          }).eq('id', memoryId);
          debugPrint('[PhotoAI] Supabase DB updated for $memoryId');
        } catch (e) {
          debugPrint('[PhotoAI Warning] Supabase DB update error: $e');
        }
      }

      // 3. Emit updated state to all listeners
      final updatedEntity = (existing?.toEntity() ?? originalMemory).copyWith(
        title: effectiveTitle,
        category: effectiveCategory,
        tags: effectiveTags,
        content: effectiveContent,
        aiStatus: 'processed',
        metadata: meta,
        mediaUrl: mediaUrl ?? (existing?.mediaUrl ?? originalMemory.mediaUrl),
      );
      add(MemoryUpdatedEvent(updatedEntity));
      add(LoadMemoriesEvent());
    } catch (e, stack) {
      debugPrint(
        '[PhotoAI Error] _updateMemoryWithPhotoAiResult error: $e\n$stack',
      );
    }
  }

  Future<void> _updateMemoryWithVoiceAiResult({
    required String memoryId,
    required AiIngestionResult aiResult,
    required MemoryEntity originalMemory,
  }) async {
    try {
      final isar = IsarService.instance;
      final existing = await isar.memoryModels
          .filter()
          .serverIdEqualTo(memoryId)
          .findFirst();

      final effectiveTitle = aiResult.title.isNotEmpty
          ? aiResult.title
          : originalMemory.title;
      final effectiveCategory = aiResult.category.isNotEmpty
          ? aiResult.category
          : (originalMemory.category.isNotEmpty &&
                  originalMemory.category != 'General'
              ? originalMemory.category
              : 'Personal');

      final List<String> effectiveTags = List.from(originalMemory.tags);
      for (final tag in aiResult.tags) {
        if (!effectiveTags.contains(tag)) {
          effectiveTags.add(tag);
        }
      }
      if (!effectiveTags.contains('voice')) {
        effectiveTags.add('voice');
      }

      final effectiveContent = (aiResult.rawOcrText != null &&
              aiResult.rawOcrText!.trim().isNotEmpty)
          ? aiResult.rawOcrText!.trim()
          : originalMemory.content;

      final summary = aiResult.summary.trim();
      final meta = Map<String, dynamic>.from(
        existing?.metadata ?? originalMemory.metadata ?? {},
      );
      if (summary.isNotEmpty) {
        meta['summary'] = summary;
      }
      meta['file_type'] = 'voice';
      if (aiResult.entities.isNotEmpty) {
        meta['entities'] = aiResult.entities.map((e) => e.toMap()).toList();
      }

      if (existing != null) {
        existing.title = effectiveTitle;
        existing.category = effectiveCategory;
        existing.tags = effectiveTags;
        existing.content = effectiveContent;
        existing.aiStatus = 'processed';
        existing.metadata = meta;
        existing.serverUpdatedAt = DateTime.now();
        existing.isSynced = true;

        await isar.writeTxn(() async {
          await isar.memoryModels.put(existing);
        });
      }

      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && currentUserId != 'local_user') {
        try {
          await Supabase.instance.client.from('memories').update({
            'title': effectiveTitle,
            'category': effectiveCategory,
            'tags': effectiveTags,
            'content': effectiveContent,
            'ai_status': 'processed',
            'metadata': meta,
            'server_updated_at': DateTime.now().toIso8601String(),
          }).eq('id', memoryId);
          debugPrint('[VoiceAI] Supabase DB updated for $memoryId');
        } catch (e) {
          debugPrint('[VoiceAI Warning] Supabase DB update error: $e');
        }
      }

      final updatedEntity = (existing?.toEntity() ?? originalMemory).copyWith(
        title: effectiveTitle,
        category: effectiveCategory,
        tags: effectiveTags,
        content: effectiveContent,
        aiStatus: 'processed',
        metadata: meta,
      );
      add(MemoryUpdatedEvent(updatedEntity));
      add(LoadMemoriesEvent());
    } catch (e, stack) {
      debugPrint('[VoiceAI Error] _updateMemoryWithVoiceAiResult error: $e\n$stack');
    }
  }

  Future<void> _onRetryMemoryIngestion(
    RetryMemoryIngestionEvent event,
    Emitter<CaptureState> emit,
  ) async {
    try {
      final isar = IsarService.instance;
      final existing = await isar.memoryModels
          .filter()
          .serverIdEqualTo(event.memoryId)
          .findFirst();
      if (existing != null) {
        final memory = existing.toEntity();
        final isVoice = memory.tags.any((t) => t.toLowerCase() == 'voice') ||
            (memory.mediaUrl != null &&
                (memory.mediaUrl!.endsWith('.m4a') ||
                    memory.mediaUrl!.endsWith('.aac') ||
                    memory.mediaUrl!.endsWith('.mp3') ||
                    memory.mediaUrl!.endsWith('.wav')));
        final isPdf = (memory.mediaUrl != null &&
                memory.mediaUrl!.toLowerCase().endsWith('.pdf')) ||
            memory.tags.any((t) => t.toLowerCase() == 'pdf');
        final isVideo = memory.isVideo ||
            memory.fileType == 'video' ||
            memory.tags.any((t) => t.toLowerCase() == 'video') ||
            (memory.metadata != null &&
                memory.metadata!['file_type'] == 'video') ||
            (memory.mediaUrl != null &&
                (memory.mediaUrl!.toLowerCase().endsWith('.mp4') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.mov') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.avi') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.mkv') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.webm') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.3gp') ||
                    memory.mediaUrl!.toLowerCase().endsWith('.m4v')));
        final isImage =
            !isVideo && !isVoice && !isPdf && memory.mediaUrl != null;

        unawaited(
          _triggerBackgroundIngestion(
            memory,
            isNote: false,
            isVoice: isVoice,
            isPdf: isPdf,
            isVideo: isVideo,
            isImage: isImage,
            isEmbeddingOnly: false,
          ),
        );
      }
    } catch (_) {}
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
            resData = Map<String, dynamic>.from(
              jsonDecode(response.data as String),
            );
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
            if (remoteModel.content.isNotEmpty &&
                !remoteModel.content.startsWith('Video recording saved:') &&
                !remoteModel.content.toLowerCase().startsWith('saved video recording')) {
              existing.content = remoteModel.content;
            }
            if (remoteModel.mediaUrl != null &&
                remoteModel.mediaUrl!.isNotEmpty) {
              existing.mediaUrl = remoteModel.mediaUrl;
            }
            if (remoteModel.embedding != null) {
              existing.embedding = remoteModel.embedding;
            }
            existing.serverUpdatedAt = remoteModel.serverUpdatedAt;
            existing.isSynced = true;
          }
          if (resData != null) {
            if (resData['title'] != null) {
              existing.title = resData['title'].toString();
            }
            if (resData['category'] != null) {
              existing.category = resData['category'].toString();
            }
            if (resData['tags'] != null) {
              existing.tags = List<String>.from(resData['tags'] as List);
            }
            final returnedContent = resData['content']?.toString() ??
                resData['transcript']?.toString() ??
                resData['summary']?.toString();
            if (returnedContent != null &&
                returnedContent.trim().isNotEmpty &&
                !returnedContent.startsWith('Video recording saved:') &&
                !returnedContent.toLowerCase().startsWith('saved video recording')) {
              existing.content = returnedContent.trim();
            }
            if (resData['summary'] != null &&
                resData['summary'].toString().trim().isNotEmpty) {
              final summaryStr = resData['summary'].toString().trim();
              final meta = Map<String, dynamic>.from(existing.metadata ?? {});
              meta['summary'] = summaryStr;
              if (existing.tags.contains('video')) {
                meta['file_type'] = 'video';
              }
              existing.metadata = meta;
            }
            existing.aiStatus = (resData['ai_status'] ?? 'processed')
                .toString();
            existing.serverUpdatedAt = DateTime.now();
            existing.isSynced = true;
          }

          await isar.writeTxn(() async {
            await isar.memoryModels.put(existing);
          });

          debugPrint(
            '[VideoAI] Memory $memoryId updated in Isar: title="${existing.title}", category="${existing.category}", tags=${existing.tags}, content="${existing.content}"',
          );

          updatedEntity = existing.toEntity();
        }
      } catch (isarErr, isarStack) {
        debugPrint(
          '[VideoAI Error] Failed writing updated memory to Isar: $isarErr\n$isarStack',
        );
      }

      // 4. Construct updated MemoryEntity if Isar was not open
      if (updatedEntity == null) {
        if (remoteRow != null) {
          updatedEntity = MemoryModel.fromMap(
            remoteRow,
            isSynced: true,
          ).toEntity();
        } else if (resData != null) {
          updatedEntity = MemoryEntity(
            id: memoryId,
            userId: fallbackMemory.userId,
            title: (resData['title'] ?? fallbackMemory.title).toString(),
            content: (resData['content'] ?? fallbackMemory.content).toString(),
            mediaUrl: fallbackMemory.mediaUrl,
            tags: resData['tags'] != null
                ? List<String>.from(resData['tags'] as List)
                : fallbackMemory.tags,
            category: (resData['category'] ?? fallbackMemory.category)
                .toString(),
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
    _connectivitySubscription?.cancel();
    _connectivityDebounceTimer?.cancel();
    _realtimeSubscription?.cancel();
    return super.close();
  }
}
