import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/audio_player_service.dart';
import '../../../../core/services/audio_recorder_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';
import '../widgets/voice_audio_player_card.dart';

enum VoiceRecordState { idle, recording, paused, review }

class _CategoryChoice {
  final String name;
  final IconData icon;

  const _CategoryChoice({required this.name, required this.icon});
}

class VoiceRecordScreen extends StatefulWidget {
  final AudioRecorderService? recorderService;
  final AudioPlayerService? playerService;
  final Directory? customDocumentsDirectory;

  const VoiceRecordScreen({
    super.key,
    this.recorderService,
    this.playerService,
    this.customDocumentsDirectory,
  });

  @override
  State<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends State<VoiceRecordScreen>
    with SingleTickerProviderStateMixin {
  late final AudioRecorderService _recorderService;
  late final AudioPlayerService? _playerService;

  VoiceRecordState _recordState = VoiceRecordState.idle;
  int _secondsRecorded = 0;
  Timer? _recordTimer;
  String? _recordedFilePath;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();
  String? _selectedCategory;
  final List<String> _tags = ['voice'];
  bool _isSaving = false;
  String? _permissionError;

  static const List<_CategoryChoice> _categories = [
    _CategoryChoice(
      name: AppStrings.categoryPersonal,
      icon: Icons.favorite_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryWork,
      icon: Icons.work_outline_rounded,
    ),
    _CategoryChoice(name: AppStrings.categoryStudy, icon: Icons.school_rounded),
    _CategoryChoice(
      name: AppStrings.categoryTravel,
      icon: Icons.flight_takeoff_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFashion,
      icon: Icons.shopping_bag_outlined,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFood,
      icon: Icons.restaurant_rounded,
    ),
    _CategoryChoice(
      name: AppStrings.categoryFinance,
      icon: Icons.account_balance_wallet_outlined,
    ),
    _CategoryChoice(
      name: AppStrings.categoryHealth,
      icon: Icons.fitness_center_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _recorderService = widget.recorderService ?? RecordAudioRecorderService();
    _playerService = widget.playerService;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _titleController.dispose();
    _tagInputController.dispose();
    _recorderService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() => _permissionError = null);
    try {
      final hasPermission = await _recorderService.hasPermission();
      if (!hasPermission) {
        setState(() {
          _permissionError =
              'Microphone permission denied. Please enable microphone access in Settings.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_permissionError!),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final Directory appDir =
          widget.customDocumentsDirectory ??
          await getApplicationDocumentsDirectory();
      final String filePath =
          '${appDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorderService.start(path: filePath);

      _secondsRecorded = 0;
      _recordedFilePath = filePath;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _secondsRecorded++);
        }
      });

      _pulseController.repeat(reverse: true);
      setState(() {
        _recordState = VoiceRecordState.recording;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _recorderService.pause();
      _pulseController.stop();
      _recordTimer?.cancel();
      setState(() => _recordState = VoiceRecordState.paused);
    } catch (_) {}
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorderService.resume();
      _pulseController.repeat(reverse: true);
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _secondsRecorded++);
        }
      });
      setState(() => _recordState = VoiceRecordState.recording);
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _pulseController.stop();
    try {
      final stoppedPath = await _recorderService.stop();
      if (stoppedPath != null && stoppedPath.isNotEmpty) {
        _recordedFilePath = stoppedPath;
      }
      setState(() => _recordState = VoiceRecordState.review);
    } catch (_) {
      setState(() => _recordState = VoiceRecordState.review);
    }
  }

  void _discardAndReset() {
    _recordTimer?.cancel();
    _pulseController.stop();
    try {
      if (_recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (_) {}

    setState(() {
      _recordState = VoiceRecordState.idle;
      _secondsRecorded = 0;
      _recordedFilePath = null;
      _titleController.clear();
      _tagInputController.clear();
      _selectedCategory = null;
      _tags.clear();
      _tags.add('voice');
    });
  }

  void _addCustomTag() {
    final rawTag = _tagInputController.text
        .trim()
        .replaceAll('#', '')
        .toLowerCase();
    if (rawTag.isNotEmpty && !_tags.contains(rawTag)) {
      setState(() {
        _tags.add(rawTag);
        _tagInputController.clear();
      });
    }
  }

  Future<void> _saveMemory() async {
    if (_recordedFilePath == null) return;

    setState(() => _isSaving = true);

    try {
      final defaultTitle =
          'Voice Note (${DateFormat('MMM d').format(DateTime.now())})';
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : defaultTitle;

      final category = _selectedCategory ?? 'General';
      final tags = List<String>.from(_tags);
      if (!tags.contains('voice')) {
        tags.add('voice');
      }

      context.read<CaptureBloc>().add(
        AddMemoryEvent(
          title: title,
          content:
              '', // Truthful: empty until real Gemini speech-to-text finishes
          category: category,
          tags: tags,
          mediaUrl: _recordedFilePath,
          aiStatus: 'pending',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice memory saved!'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save voice memory: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatSeconds(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _recordState == VoiceRecordState.review
              ? 'Review Voice Note'
              : 'Record Voice',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppColors.headerGradientOf(context),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? AppColors.darkPrimary : AppColors.primary)
                    .withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: _recordState == VoiceRecordState.review
            ? _buildReviewView()
            : _buildRecordingView(),
      ),
    );
  }

  Widget _buildRecordingView() {
    final isRecording = _recordState == VoiceRecordState.recording;
    final isPaused = _recordState == VoiceRecordState.paused;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_permissionError != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.categoryPersonalBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.errorBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mic_off_rounded,
                      color: AppColors.errorText,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _permissionError!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.errorText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Timer display
            Text(
              _formatSeconds(_secondsRecorded),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1.0,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),

            const SizedBox(height: 12),

            // State label
            Text(
              isRecording
                  ? 'Recording audio...'
                  : isPaused
                  ? 'Recording paused'
                  : 'Tap microphone to start recording',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isRecording
                    ? const Color(0xFF134E3F)
                    : AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 50),

            // Main Microphone Button with Pulsing Wave
            Stack(
              alignment: Alignment.center,
              children: [
                if (isRecording)
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF134E3F).withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                InkWell(
                  onTap: () {
                    if (_recordState == VoiceRecordState.idle) {
                      _startRecording();
                    } else if (isRecording) {
                      _pauseRecording();
                    } else if (isPaused) {
                      _resumeRecording();
                    }
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF134E3F),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF134E3F).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      isRecording
                          ? Icons.pause_rounded
                          : isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.mic_rounded,
                      color: AppColors.textWhite,
                      size: 46,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 60),

            // Bottom controls when active
            if (isRecording || isPaused)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Discard button
                  IconButton.filledTonal(
                    onPressed: _discardAndReset,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.errorText,
                    ),
                    tooltip: 'Discard',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.categoryPersonalBackground,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  // Done / Stop button
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textWhite,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Audio Player Card
          if (_recordedFilePath != null)
            VoiceAudioPlayerCard(
              audioSource: _recordedFilePath!,
              isLocal: true,
              playerService: _playerService,
            ),

          const SizedBox(height: 24),

          // 2. Title Field
          const Text(
            'Title (Optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText:
                  'Voice Note (${DateFormat('MMM d').format(DateTime.now())})',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppColors.cardBackground,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.chipInactiveBorder,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.chipInactiveBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 3. Category Selector
          const Text(
            'Category (Optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: 1 + _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isAuto = index == 0;
                final cat = isAuto ? null : _categories[index - 1];
                final name = isAuto ? 'Auto (AI)' : cat!.name;
                final icon = isAuto ? Icons.auto_awesome_rounded : cat!.icon;
                final isSelected = isAuto
                    ? (_selectedCategory == null)
                    : (_selectedCategory == name);

                const selectedBgColor = Color(0xFF134E3F);
                const unselectedBgColor = Color(0xFFF1F5F3);
                const unselectedBorderColor = Color(0xFFE2E8F0);
                const unselectedTextColor = Color(0xFF2D3748);
                const unselectedIconColor = Color(0xFF134E3F);

                return InkWell(
                  key: Key(
                    isAuto
                        ? 'category_chip_auto'
                        : 'category_chip_${name.toLowerCase()}',
                  ),
                  onTap: () {
                    setState(() {
                      _selectedCategory = isAuto ? null : name;
                    });
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedBgColor : unselectedBgColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isSelected
                            ? selectedBgColor
                            : unselectedBorderColor,
                        width: 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: selectedBgColor.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : unselectedIconColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isAuto
                                      ? const Color(0xFF134E3F)
                                      : unselectedTextColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // 4. Tags Input & Chips
          const Text(
            'Tags (Optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  decoration: InputDecoration(
                    hintText: 'Add a tag (e.g. meeting, ideas)',
                    hintStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.chipInactiveBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.chipInactiveBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addCustomTag,
                icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                tooltip: 'Add tag',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.lightCyanTint,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((t) {
                final isVoiceTag = t == 'voice';
                return Chip(
                  label: Text(
                    '#$t',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  backgroundColor: AppColors.lightCyanTint,
                  side: const BorderSide(color: AppColors.chipInactiveBorder),
                  deleteIcon: isVoiceTag
                      ? null
                      : const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                  onDeleted: isVoiceTag
                      ? null
                      : () {
                          setState(() => _tags.remove(t));
                        },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 36),

          // 5. Actions: Record Again & Save Memory
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _discardAndReset,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Record Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.chipInactiveBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveMemory,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.textWhite,
                            ),
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Memory',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textWhite,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
