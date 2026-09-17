import 'dart:async';
import 'package:record/record.dart';

abstract class AudioRecorderService {
  Future<bool> hasPermission();
  Future<void> start({required String path});
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<bool> isRecording();
  Future<bool> isPaused();
  Future<void> dispose();
}

class RecordAudioRecorderService implements AudioRecorderService {
  final AudioRecorder _recorder;

  RecordAudioRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start({required String path}) => _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<bool> isRecording() => _recorder.isRecording();

  @override
  Future<bool> isPaused() => _recorder.isPaused();

  @override
  Future<void> dispose() => _recorder.dispose();
}
