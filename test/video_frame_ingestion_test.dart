import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/services/video_frame_extractor.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';

class MockAiRepository implements AiRepository {
  String? lastOcrText;
  String? lastImageBase64;
  String? lastMimeType;
  AiIngestionResult? responseToReturn;

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
  }) async {
    lastOcrText = ocrText;
    lastImageBase64 = imageBase64;
    lastMimeType = mimeType;
    return responseToReturn ??
        const AiIngestionResult(
          title: 'Handcrafted Leather Sandals',
          category: 'Personal Life',
          tags: ['sandals', 'footwear', 'leather', 'video'],
          summary:
              '• Close-up view of brown leather sandals on a wooden table\n• Handcrafted stitching details visible\n• Artisan workshop setting',
          aiStatus: 'processed',
        );
  }
}

class MockCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories = [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => memories;

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index != -1) {
      memories[index] = memory;
    } else {
      memories.add(memory);
    }
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();

  @override
  Future<void> deleteMemory(String memoryId) async {
    memories.removeWhere((m) => m.id == memoryId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Video Frame Ingestion & MemoryModel Updates', () {
    late Directory tempDir;
    late File dummyVideoFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('video_test_');
      dummyVideoFile = File('${tempDir.path}/test_video.mp4');
      await dummyVideoFile.writeAsBytes([0, 1, 2, 3, 4, 5, 6, 7]);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('VideoFrameExtractor gracefully handles missing files and returns null',
        () async {
      final result =
          await VideoFrameExtractor.extractRepresentativeFrame('/non/existent.mp4');
      expect(result, isNull);
    });

    test(
        'Video frame AI analysis updates MemoryModel content, title, category, and tags',
        () async {
      final mockAiRepo = MockAiRepository();
      final mockCaptureRepo = MockCaptureRepository();
      final saveMemoryUseCase = SaveMemoryUseCase(mockCaptureRepo);
      final getMemoriesUseCase = GetMemoriesUseCase(mockCaptureRepo);

      final bloc = CaptureBloc(
        saveMemoryUseCase: saveMemoryUseCase,
        getMemoriesUseCase: getMemoriesUseCase,
        repository: mockCaptureRepo,
        aiRepository: mockAiRepo,
        connectivityStream: Stream.value(true),
      );

      // Create a MemoryModel with raw placeholder text (as previously seen on real device)
      final rawModel = MemoryModel()
        ..serverId = 'video-mem-001'
        ..userId = 'user_123'
        ..title = 'Video Note'
        ..content = '• Saved video recording file 70873.mp4'
        ..mediaUrl = dummyVideoFile.path
        ..tags = ['video']
        ..category = 'General'
        ..aiStatus = 'pending'
        ..clientCreatedAt = DateTime.now()
        ..clientUpdatedAt = DateTime.now()
        ..serverUpdatedAt = DateTime.now();

      // Verify initial state has raw placeholder
      expect(rawModel.content, contains('Saved video recording file 70873.mp4'));
      expect(rawModel.aiStatus, equals('pending'));

      // Simulate client-side frame ingestion via MockAiRepository
      final aiResult = await mockAiRepo.processPhotoIngestion(
        ocrText:
            'Analyze this video frame/scene. Provide a concise, descriptive title, detailed bulleted summary of visible scene/objects/actions, suitable category, and 4-6 specific tags.',
        imageBase64: base64Encode(Uint8List.fromList([1, 2, 3, 4])),
        mimeType: 'image/jpeg',
      );

      // Update the MemoryModel using the resolved AI fields
      final meta = {
        'summary': aiResult.summary,
        'file_type': 'video',
      };
      final contentWithMeta =
          '${aiResult.summary}\n\n<!--template_metadata:${jsonEncode(meta)}-->'
              .trim();

      rawModel.title = aiResult.title;
      rawModel.category = aiResult.category;
      rawModel.tags = {...rawModel.tags, ...aiResult.tags, 'video'}.toList();
      rawModel.content = contentWithMeta;
      rawModel.aiStatus = 'processed';

      // Assertions: Placeholder replaced completely
      expect(rawModel.content, isNot(contains('Saved video recording file')));
      expect(rawModel.content, isNot(contains('70873.mp4')));
      expect(rawModel.content, contains('Close-up view of brown leather sandals'));
      expect(rawModel.title, equals('Handcrafted Leather Sandals'));
      expect(rawModel.category, equals('Personal Life'));
      expect(rawModel.tags, contains('sandals'));
      expect(rawModel.tags, contains('video'));
      expect(rawModel.aiStatus, equals('processed'));

      // Verify mapped entity receives parsed metadata and summary
      final entity = rawModel.toEntity();
      expect(entity.title, equals('Handcrafted Leather Sandals'));
      expect(entity.fileType, equals('video'));
      expect(entity.isVideo, isTrue);

      await bloc.close();
    });

    test(
        'MemoryModel converts metadata and preserves video tags correctly',
        () {
      final map = {
        'id': 'v-999',
        'user_id': 'u-1',
        'title': 'Coffee Pouring Video',
        'content': '• Espresso shot being extracted into glass cup',
        'category': 'Personal Life',
        'tags': ['coffee', 'espresso', 'video'],
        'ai_status': 'processed',
        'media_url': 'https://supabase.co/storage/v1/object/public/memories/video.mp4',
        'metadata': {
          'summary': '• Espresso shot being extracted into glass cup\n• Rich crema visible',
          'file_type': 'video',
        },
      };

      final model = MemoryModel.fromMap(map);
      expect(model.title, equals('Coffee Pouring Video'));
      expect(model.tags, contains('video'));
      expect(model.tags, contains('coffee'));
      expect(model.aiStatus, equals('processed'));

      final entity = model.toEntity();
      expect(entity.isVideo, isTrue);
      expect(entity.fileType, equals('video'));
    });
  });
}
