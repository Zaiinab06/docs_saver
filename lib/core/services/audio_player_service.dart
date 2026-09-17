import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

abstract class AudioPlayerService {
  Future<void> play(String source, {required bool isLocal});
  Future<void> setSource(String source, {required bool isLocal});
  Future<Duration?> getDuration();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> dispose();
  Stream<PlayerState> get onPlayerStateChanged;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
}

class DefaultAudioPlayerService implements AudioPlayerService {
  final AudioPlayer _player;

  DefaultAudioPlayerService({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  @override
  Future<void> play(String source, {required bool isLocal}) {
    if (isLocal) {
      return _player.play(DeviceFileSource(source));
    } else {
      return _player.play(UrlSource(source));
    }
  }

  @override
  Future<void> setSource(String source, {required bool isLocal}) {
    if (isLocal) {
      return _player.setSource(DeviceFileSource(source));
    } else {
      return _player.setSource(UrlSource(source));
    }
  }

  @override
  Future<Duration?> getDuration() => _player.getDuration();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
}
