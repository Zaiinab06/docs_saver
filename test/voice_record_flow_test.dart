import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:second_brain/core/services/audio_player_service.dart';
import 'package:second_brain/core/services/audio_recorder_service.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_state.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/capture/presentation/screens/voice_record_screen.dart';
import 'package:second_brain/features/capture/presentation/widgets/voice_audio_player_card.dart';
import 'package:second_brain/features/navigation/presentation/screens/main_navigation_shell.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async =>
      List.from(memories);

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index >= 0) {
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
  Future<void> deleteMemory(String memoryId) async {}
}

class FakeAudioRecorderService implements AudioRecorderService {
  bool permissionGranted = true;
  bool recording = false;
  bool paused = false;
  String? currentPath;
  int startCallCount = 0;
  int pauseCallCount = 0;
  int resumeCallCount = 0;
  int stopCallCount = 0;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start({required String path}) async {
    startCallCount++;
    recording = true;
    paused = false;
    currentPath = path;
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumeCallCount++;
    paused = false;
  }

  @override
  Future<String?> stop() async {
    stopCallCount++;
    recording = false;
    paused = false;
    return currentPath;
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<bool> isPaused() async => paused;

  @override
  Future<void> dispose() async {}
}

class FakeAudioPlayerService implements AudioPlayerService {
  PlayerState state = PlayerState.stopped;
  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 45);

  final _stateController = StreamController<PlayerState>.broadcast();
  final _posController = StreamController<Duration>.broadcast();
  final _durController = StreamController<Duration>.broadcast();

  int playCallCount = 0;
  int pauseCallCount = 0;
  int resumeCallCount = 0;
  int stopCallCount = 0;
  int seekCallCount = 0;
  int setSourceCallCount = 0;

  @override
  Future<void> setSource(String source, {required bool isLocal}) async {
    setSourceCallCount++;
    _durController.add(duration);
  }

  @override
  Future<Duration?> getDuration() async => duration;

  @override
  Future<void> play(String source, {required bool isLocal}) async {
    playCallCount++;
    state = PlayerState.playing;
    _stateController.add(state);
    _durController.add(duration);
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    state = PlayerState.paused;
    _stateController.add(state);
  }

  @override
  Future<void> resume() async {
    resumeCallCount++;
    state = PlayerState.playing;
    _stateController.add(state);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    state = PlayerState.stopped;
    _stateController.add(state);
  }

  @override
  Future<void> seek(Duration pos) async {
    seekCallCount++;
    position = pos;
    _posController.add(pos);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _posController.close();
    await _durController.close();
  }

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<Duration> get onPositionChanged => _posController.stream;

  @override
  Stream<Duration> get onDurationChanged => _durController.stream;
}

void main() {
  group('Record Voice Feature & Audio Architecture Tests', () {
    late FakeCaptureRepository repo;
    late CaptureBloc captureBloc;
    late FakeAudioRecorderService fakeRecorder;
    late FakeAudioPlayerService fakePlayer;
    late Directory tempDir;

    setUp(() async {
      repo = FakeCaptureRepository([]);
      captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );
      fakeRecorder = FakeAudioRecorderService();
      fakePlayer = FakeAudioPlayerService();
      VoiceAudioPlayerCard.playerServiceFactory = () => fakePlayer;
      tempDir = await Directory.systemTemp.createTemp('voice_test_');
    });

    tearDown(() async {
      VoiceAudioPlayerCard.playerServiceFactory = null;
      await captureBloc.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Widget createTestApp(Widget homeWidget, {WidgetTester? tester}) {
      if (tester != null) {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      return MultiBlocProvider(
        providers: [BlocProvider<CaptureBloc>.value(value: captureBloc)],
        child: MaterialApp(home: homeWidget),
      );
    }

    testWidgets(
      '1. Record Voice option is present and opens from capture bottom sheet',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const MainNavigationShell(), tester: tester),
        );
        await tester.pumpAndSettle();

        // Open capture bottom sheet
        await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
        await tester.pumpAndSettle();

        // Verify Record Voice option exists
        final recordVoiceFinder = find.byKey(const Key('capture_option_Record Voice'));
        expect(recordVoiceFinder, findsOneWidget);

        // Tap Record Voice
        await tester.tap(recordVoiceFinder);
        await tester.pumpAndSettle();

        // Verify VoiceRecordScreen is pushed
        expect(find.byType(VoiceRecordScreen), findsOneWidget);
        expect(find.text('Record Voice'), findsAtLeastNWidgets(1));
        expect(find.text('Tap microphone to start recording'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Microphone permission denial shows clear error message and halts recording',
      (tester) async {
        fakeRecorder.permissionGranted = false;

        await tester.pumpWidget(
          createTestApp(
            VoiceRecordScreen(
              recorderService: fakeRecorder,
              customDocumentsDirectory: tempDir,
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        // Tap microphone button
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pumpAndSettle();

        // Verify permission error banner and recorder was never started
        expect(
          find.text(
            'Microphone permission denied. Please enable microphone access in Settings.',
          ),
          findsWidgets,
        );
        expect(fakeRecorder.startCallCount, 0);
        expect(fakeRecorder.recording, false);
      },
    );

    testWidgets(
      '3. Recording start, pause, resume, stop state transitions work correctly',
      (tester) async {
        fakeRecorder.permissionGranted = true;

        await tester.pumpWidget(
          createTestApp(
            VoiceRecordScreen(
              recorderService: fakeRecorder,
              playerService: fakePlayer,
              customDocumentsDirectory: tempDir,
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        // Initial state: Idle
        expect(find.text('Tap microphone to start recording'), findsOneWidget);

        // Start recording
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeRecorder.startCallCount, 1);
        expect(fakeRecorder.recording, true);
        expect(find.text('Recording audio...'), findsOneWidget);

        // Pause recording
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await tester.pumpAndSettle();

        expect(fakeRecorder.pauseCallCount, 1);
        expect(fakeRecorder.paused, true);
        expect(find.text('Recording paused'), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Resume recording
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeRecorder.resumeCallCount, 1);
        expect(fakeRecorder.paused, false);

        // Stop recording
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(fakeRecorder.stopCallCount, 1);
        expect(fakeRecorder.recording, false);
        // Mode switches to review
        expect(find.text('Review Voice Note'), findsOneWidget);
        expect(find.text('Save Memory'), findsOneWidget);
        expect(find.byType(VoiceAudioPlayerCard), findsOneWidget);
      },
    );

    testWidgets(
      '4. Real file path is passed into the memory flow and saved with #voice tag',
      (tester) async {
        fakeRecorder.permissionGranted = true;

        await tester.pumpWidget(
          createTestApp(
            VoiceRecordScreen(
              recorderService: fakeRecorder,
              playerService: fakePlayer,
              customDocumentsDirectory: tempDir,
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        // Start and stop
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        // Verify file path contains .m4a and belongs to the custom documents directory
        expect(fakeRecorder.currentPath, isNotNull);
        expect(fakeRecorder.currentPath!.endsWith('.m4a'), isTrue);
        expect(fakeRecorder.currentPath!.startsWith(tempDir.path), isTrue);

        // Enter a custom title and custom tag
        await tester.enterText(
          find.byType(TextField).first,
          'Meeting with Architecture Team',
        );
        await tester.pumpAndSettle();

        // Tap Work category
        await tester.tap(find.text('Work'));
        await tester.pumpAndSettle();

        // Save memory
        await tester.tap(find.text('Save Memory'));
        await tester.pumpAndSettle();

        // Verify saved in repository
        expect(repo.memories.length, 1);
        final saved = repo.memories.first;
        expect(saved.title, 'Meeting with Architecture Team');
        expect(saved.category, 'Work');
        expect(saved.mediaUrl, fakeRecorder.currentPath);
        expect(saved.tags, contains('voice'));
        expect(saved.aiStatus, 'pending');
      },
    );

    testWidgets(
      '5. Offline voice memory contains no fake transcript and truthful pending state',
      (tester) async {
        fakeRecorder.permissionGranted = true;

        await tester.pumpWidget(
          createTestApp(
            VoiceRecordScreen(
              recorderService: fakeRecorder,
              playerService: fakePlayer,
              customDocumentsDirectory: tempDir,
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save Memory'));
        await tester.pumpAndSettle();

        expect(repo.memories.isNotEmpty, isTrue);
        final voiceMemory = repo.memories.first;

        // CRITICAL INTEGRITY CHECK: content must be empty, not fake or mock text
        expect(voiceMemory.content, isEmpty);
        expect(voiceMemory.aiStatus, 'pending');
        expect(voiceMemory.mediaUrl, isNotNull);
        expect(voiceMemory.tags, contains('voice'));
      },
    );

    testWidgets(
      '6. MemoryDetailScreen displays VoiceAudioPlayerCard and truthful offline pending banner',
      (tester) async {
        final offlineVoiceMemory = MemoryEntity(
          id: 'voice_123',
          userId: 'local_user',
          title: 'Voice Note (Sep 17)',
          content: '', // Truthful: empty before transcription
          category: 'Personal',
          tags: const ['voice'],
          mediaUrl: '${tempDir.path}/test_recording.m4a',
          aiStatus: 'pending',
          isSynced: false,
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );
        repo.memories.add(offlineVoiceMemory);
        captureBloc.add(LoadMemoriesEvent());
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          createTestApp(
            MemoryDetailScreen(
              memoryId: offlineVoiceMemory.id,
              initialMemory: offlineVoiceMemory,
            ),
            tester: tester,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify VoiceAudioPlayerCard is rendered and no Image widgets attempt to render audio
        expect(find.byType(VoiceAudioPlayerCard), findsOneWidget);
        expect(find.text('Voice Recording'), findsOneWidget);
        expect(find.byType(Image), findsNothing);

        // Verify truthful offline pending banner
        expect(
          find.text(
            'Audio saved offline. Transcription will begin when online.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '7. Transcription result updates memory to AI Organized and displays transcript',
      (tester) async {
        final offlineVoiceMemory = MemoryEntity(
          id: 'voice_456',
          userId: 'local_user',
          title: 'Voice Note (Sep 17)',
          content: '',
          category: 'Personal',
          tags: const ['voice'],
          mediaUrl: '${tempDir.path}/test_recording.m4a',
          aiStatus: 'pending',
          isSynced: false,
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );
        repo.memories.add(offlineVoiceMemory);
        captureBloc.add(LoadMemoriesEvent());
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          createTestApp(
            MemoryDetailScreen(
              memoryId: offlineVoiceMemory.id,
              initialMemory: offlineVoiceMemory,
            ),
            tester: tester,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Initially pending
        expect(
          find.text(
            'Audio saved offline. Transcription will begin when online.',
          ),
          findsOneWidget,
        );
        expect(find.text('AI Organized'), findsNothing);

        // Simulate completed ingestion response arriving from backend
        final processedMemory = MemoryEntity(
          id: offlineVoiceMemory.id,
          userId: offlineVoiceMemory.userId,
          title: 'Team Roadmap Discussion',
          content:
              'We reviewed the Q4 roadmap and agreed to prioritize the voice feature first.',
          category: 'Work',
          tags: const ['voice', 'roadmap', 'q4', 'planning'],
          mediaUrl: offlineVoiceMemory.mediaUrl,
          aiStatus: 'processed',
          isSynced: true,
          clientCreatedAt: offlineVoiceMemory.clientCreatedAt,
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.runAsync(() async {
          final future = captureBloc.stream.firstWhere(
            (state) =>
                state is CaptureLoaded &&
                state.memories.any(
                  (m) =>
                      m.id == offlineVoiceMemory.id &&
                      m.aiStatus == 'processed',
                ),
          );
          captureBloc.add(MemoryUpdatedEvent(processedMemory));
          await future;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify MemoryDetail dynamically updated without home refresh
        expect(find.text('AI Organized'), findsOneWidget);
        expect(find.text('Team Roadmap Discussion'), findsOneWidget);
        expect(find.text('Voice Transcript'), findsOneWidget);
        expect(
          find.text('Spoken words transcribed from audio'),
          findsOneWidget,
        );

        // Expand collapsible card to see full transcript
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'We reviewed the Q4 roadmap and agreed to prioritize the voice feature first.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '8. VoiceAudioPlayerCard play, pause, seek interactions behave properly',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VoiceAudioPlayerCard(
                audioSource: '${tempDir.path}/audio.m4a',
                isLocal: true,
                playerService: fakePlayer,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initial state: play button visible
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Tap play
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pumpAndSettle();

        expect(fakePlayer.playCallCount, 1);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        // Tap pause
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await tester.pumpAndSettle();

        expect(fakePlayer.pauseCallCount, 1);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Scrub slider
        final slider = find.byType(Slider);
        expect(slider, findsOneWidget);
        await tester.drag(slider, const Offset(50, 0));
        await tester.pumpAndSettle();

        expect(fakePlayer.seekCallCount, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      '9. VoiceAudioPlayerCard preloads audio source and resolves duration before Play',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VoiceAudioPlayerCard(
                audioSource: '${tempDir.path}/preload_audio.m4a',
                isLocal: true,
                playerService: fakePlayer,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Source must have been preloaded via setSource without pressing play
        expect(fakePlayer.setSourceCallCount, greaterThanOrEqualTo(1));
        expect(fakePlayer.playCallCount, 0);
        // Duration is resolved to fakePlayer.duration (00:45)
        expect(find.text('00:00 / 00:45'), findsOneWidget);
      },
    );

    testWidgets(
      '10. MemoryDetailScreen displays truthful Transcription failed state when transcript empty',
      (tester) async {
        final failedVoiceMemory = MemoryEntity(
          id: 'failed-voice-123',
          userId: 'user_1',
          title: 'Voice Note (Sep 17)',
          content: '', // Empty transcript
          tags: const ['voice'],
          category: 'Personal',
          mediaUrl: '${tempDir.path}/voice_failed.m4a',
          aiStatus: 'failed',
          isSynced: true,
          clientCreatedAt: DateTime(2026, 9, 17, 10, 0),
          clientUpdatedAt: DateTime(2026, 9, 17, 10, 0),
          serverUpdatedAt: DateTime(2026, 9, 17, 10, 0),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: captureBloc,
              child: MemoryDetailScreen(
                memoryId: failedVoiceMemory.id,
                initialMemory: failedVoiceMemory,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must display truthful failed state
        expect(
          find.text('Transcription failed — audio preserved'),
          findsWidgets,
        );
        // Must NOT display "AI Organized"
        expect(find.text('AI Organized'), findsNothing);
        // Must NOT display Voice Transcript card
        expect(find.text('Voice Transcript'), findsNothing);
        // Audio player is still preserved and playable
        expect(find.byType(VoiceAudioPlayerCard), findsOneWidget);
      },
    );
  });
}
