import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/services/audio_player_service.dart';
import '../../../../core/theme/app_colors.dart';

class VoiceAudioPlayerCard extends StatefulWidget {
  final String audioSource;
  final bool? isLocal;
  final AudioPlayerService? playerService;
  static AudioPlayerService Function()? playerServiceFactory;

  const VoiceAudioPlayerCard({
    super.key,
    required this.audioSource,
    this.isLocal,
    this.playerService,
  });

  @override
  State<VoiceAudioPlayerCard> createState() => _VoiceAudioPlayerCardState();
}

class _VoiceAudioPlayerCardState extends State<VoiceAudioPlayerCard> {
  late final AudioPlayerService _playerService;
  String _effectiveAudioSource = '';
  bool _isLocalSource = true;

  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  @override
  void initState() {
    super.initState();
    _playerService = widget.playerService ??
        (VoiceAudioPlayerCard.playerServiceFactory?.call() ??
            DefaultAudioPlayerService());
    _initSource(widget.audioSource);

    _stateSub = _playerService.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
          }
        });
      }
    });

    _posSub = _playerService.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });

    _durSub = _playerService.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() => _duration = dur);
      }
    });
  }

  @override
  void didUpdateWidget(covariant VoiceAudioPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioSource != widget.audioSource) {
      _initSource(widget.audioSource);
    }
  }

  Future<void> _initSource(String rawSource) async {
    final trimmed = rawSource.trim();
    if (trimmed.isEmpty) return;

    String resolvedSource = trimmed;
    bool isLocal = widget.isLocal ??
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'));

    // Prefer existing local .m4a file if it exists on disk
    if (!isLocal) {
      try {
        final uri = Uri.tryParse(trimmed);
        final fileName = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : null;
        if (fileName != null && fileName.isNotEmpty) {
          final Directory appDir =
              await getApplicationDocumentsDirectory().catchError((_) => Directory(''));
          if (appDir.path.isNotEmpty) {
            final localFile = File('${appDir.path}/$fileName');
            if (localFile.existsSync()) {
              resolvedSource = localFile.path;
              isLocal = true;
            }
          }
        }
      } catch (_) {}
    } else {
      resolvedSource = trimmed;
      isLocal = true;
    }

    if (mounted) {
      setState(() {
        _effectiveAudioSource = resolvedSource;
        _isLocalSource = isLocal;
      });
    } else {
      _effectiveAudioSource = resolvedSource;
      _isLocalSource = isLocal;
    }

    try {
      await _playerService.setSource(_effectiveAudioSource, isLocal: _isLocalSource);
      final d = await _playerService.getDuration();
      if (mounted && d != null && d > Duration.zero) {
        setState(() => _duration = d);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_playerState == PlayerState.playing) {
        await _playerService.pause();
      } else if (_playerState == PlayerState.paused) {
        await _playerService.resume();
      } else {
        final sourceToPlay = _effectiveAudioSource.isNotEmpty
            ? _effectiveAudioSource
            : widget.audioSource;
        await _playerService.play(sourceToPlay, isLocal: _isLocalSource);
      }
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs =
        _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.chipInactiveBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play/Pause circular button
              InkWell(
                onTap: _togglePlayPause,
                borderRadius: BorderRadius.circular(50),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppColors.textWhite,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Track information & duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Voice Recording',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Scrubbing slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.lightCyanTint,
              thumbColor: AppColors.primary,
            ),
            child: Slider(
              value: posMs,
              max: maxMs,
              onChanged: (val) {
                _playerService.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
        ],
      ),
    );
  }
}
