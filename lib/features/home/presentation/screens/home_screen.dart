import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/domain/entities/memory_entity.dart';
import '../../../capture/presentation/screens/memory_review_screen.dart';
import '../../../capture/presentation/screens/photo_review_screen.dart';
import '../../../capture/presentation/screens/note_compose_screen.dart';
import '../../../capture/presentation/screens/voice_record_screen.dart';
import '../../../capture/presentation/widgets/add_link_dialog.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import '../../../saved/presentation/screens/saved_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import '../../../../core/network/network_checker.dart';
import '../../../../core/utils/image_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../../../core/services/google_drive_service.dart';
import '../../../../core/utils/google_docs_link_extractor.dart';
import '../../../../core/utils/google_drive_link_extractor.dart';
import '../../../../core/utils/link_metadata_extractor.dart';
import '../../../integrations/data/datasources/google_auth_remote_data_source.dart';
import '../../../integrations/data/repositories/google_auth_repository_impl.dart';
import '../../../integrations/domain/entities/google_doc_entity.dart';
import '../../../integrations/domain/repositories/google_auth_repository.dart';
import '../../../../core/utils/profile_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/category_section.dart';
import 'category_detail_screen.dart';
import '../../../settings/presentation/screens/edit_profile_screen.dart';

// Header/banner gradients built on the single unified AppColors.kDeepSagePine tone.
const LinearGradient _unifiedSageHeaderGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0F3E32), Color(0xFF134E3F), Color(0xFF165948)],
);
const LinearGradient _unifiedSageBannerGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F3E32), Color(0xFF165948)],
);

class _FallbackAiRemoteDataSource implements AiRemoteDataSource {
  @override
  Future<Map<String, dynamic>> invokeIngestion({
    required String content,
    String? title,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
    String? videoBase64,
  }) async {
    return {};
  }
}

class HomeScreen extends StatefulWidget {
  final String? userName;
  final IngestMemoryUseCase? ingestMemoryUseCase;
  final LinkMetadataExtractor? linkMetadataExtractor;
  final FilePickerService? filePickerService;
  final GoogleAuthRepository? googleAuthRepository;
  final VoidCallback? onSearchTap;
  final VoidCallback? onSavedTap;

  const HomeScreen({
    super.key,
    this.userName,
    this.ingestMemoryUseCase,
    this.linkMetadataExtractor,
    this.filePickerService,
    this.googleAuthRepository,
    this.onSearchTap,
    this.onSavedTap,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  /// Opens the capture options bottom sheet modal
  void openCaptureBottomSheet() {
    _showCaptureBottomSheet(context);
  }

  late final LinkMetadataExtractor _linkMetadataExtractor;

  IngestMemoryUseCase get _effectiveIngestMemoryUseCase {
    if (widget.ingestMemoryUseCase != null) {
      return widget.ingestMemoryUseCase!;
    }
    try {
      return IngestMemoryUseCase(
        AiRepositoryImpl(remoteDataSource: AiRemoteDataSourceImpl()),
      );
    } catch (_) {
      return IngestMemoryUseCase(
        AiRepositoryImpl(remoteDataSource: _FallbackAiRemoteDataSource()),
      );
    }
  }

  GoogleAuthRepository get _effectiveGoogleAuthRepository =>
      widget.googleAuthRepository ??
      GoogleAuthRepositoryImpl(
        remoteDataSource: GoogleAuthRemoteDataSourceImpl(),
      );

  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<Uri>? _deepLinkSubscription;
  AppLinks? _appLinks;
  bool _isProBannerVisible = true;

  @override
  void initState() {
    super.initState();
    _linkMetadataExtractor =
        widget.linkMetadataExtractor ?? LinkMetadataExtractor();
    context.read<CaptureBloc>().add(LoadMemoriesEvent());
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) {
            if (mounted) {
              context.read<CaptureBloc>().add(LoadMemoriesEvent());
              setState(() {});
            }
          });
    } catch (_) {}
    _initDeepLinks();
    _loadStoredName();
  }

  Future<void> _loadStoredName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedName = prefs.getString('user_full_name');
      if (storedName != null && storedName.isNotEmpty) {
        ProfileNotifier.nameNotifier.value = storedName;
      }
      final storedImage = prefs.getString('user_profile_image');
      if (storedImage != null && storedImage.isNotEmpty) {
        ProfileNotifier.imagePathNotifier.value = storedImage;
      }
    } catch (_) {}
  }

  void _initDeepLinks() {
    try {
      _appLinks = AppLinks();
      _deepLinkSubscription = _appLinks?.uriLinkStream.listen((uri) {
        if (uri.scheme == 'secondbrain' && uri.host == 'oauth') {
          final status = uri.queryParameters['status'];
          final error = uri.queryParameters['error'];
          final reason = uri.queryParameters['reason'];
          final pickedFileId = uri.queryParameters['picked_file_id'];

          if (status == 'cancelled') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Google Drive file selection was cancelled.'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          if (status == 'error') {
            if (mounted) {
              final errorDetail = reason ?? error ?? 'unknown error';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Google Drive authorization failed ($errorDetail).',
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          final accessToken = uri.queryParameters['access_token'];
          if (accessToken != null && accessToken.isNotEmpty) {
            GoogleDriveService.cachedAccessToken = accessToken;
          }

          if (pickedFileId != null && pickedFileId.isNotEmpty) {
            _handleGoogleDocsImport(
              pickedFileId,
              GoogleDriveLinkExtractor.toCanonicalUrl(pickedFileId),
              accessToken: accessToken,
            );
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _openGooglePicker() async {
    // Clear any cached access token to force re-consent for updated Drive scopes
    GoogleDriveService.clearSession();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecting to Google Drive...'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final authUrl = await _effectiveGoogleAuthRepository.startGooglePicker();
      final uri = Uri.parse(authUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch browser to open Google Drive.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ GOOGLE DRIVE IMPORT ERROR: $e \n$stackTrace');
      if (mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open Google Drive: $cleanMsg'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  String _getUserName() {
    if (widget.userName != null && widget.userName!.trim().isNotEmpty) {
      return widget.userName!.trim();
    }
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated &&
          authState.user.fullName != null &&
          authState.user.fullName!.trim().isNotEmpty) {
        return authState.user.fullName!.trim();
      }
      if (authState is AuthSuccess &&
          authState.user.fullName != null &&
          authState.user.fullName!.trim().isNotEmpty) {
        return authState.user.fullName!.trim();
      }
    } catch (_) {}
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final metadataName = user?.userMetadata?['full_name'] as String?;
      if (metadataName != null && metadataName.trim().isNotEmpty) {
        return metadataName.trim();
      }
      final rawName = user?.userMetadata?['name'] as String?;
      if (rawName != null && rawName.trim().isNotEmpty) {
        return rawName.trim();
      }
      if (user?.email != null && user!.email!.isNotEmpty) {
        final emailPrefix = user.email!.split('@').first;
        if (emailPrefix.isNotEmpty) {
          return emailPrefix[0].toUpperCase() + emailPrefix.substring(1);
        }
      }
    } catch (_) {}
    return AppStrings.homeDefaultUser;
  }

  String _getUserInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'there') {
      return 'S';
    }
    return trimmed[0].toUpperCase();
  }

  List<MemoryEntity> _memoriesFromState(CaptureState state) {
    if (state is CaptureLoaded) return state.memories;
    return const [];
  }

  void _showUnavailableFeature(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is not available yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, List<MemoryEntity> memories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        // 2. Quick Actions Card Container
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildQuickActions(context),
        ),
        const SizedBox(height: 12),

        // 3. Pro Upgrade Banner
        if (_isProBannerVisible) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildUpgradeBanner(context),
          ),
          const SizedBox(height: 12),
        ],

        // 4. Categories Section (Compact Row)
        _buildCategoriesSection(context, memories),
        const SizedBox(height: 12),

        // 5. Recent Memories Section
        _buildRecentMemoriesSection(context, memories),
      ],
    );
  }

  Widget _buildCategoriesSection(
    BuildContext context,
    List<MemoryEntity> memories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildSectionTitle(context, 'Categories'),
        ),
        const SizedBox(height: 8),
        _buildCategorySectionsList(context, memories),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : AppColors.textPrimaryOf(context),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildUpgradeBanner(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: _unifiedSageBannerGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.kDeepSagePine.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CustomPaint(
                  size: Size(32, 28),
                  painter: _GoldenCrownPainter(),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Upgrade to DocsSaver Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Unlock smart reminders and other features',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showUnavailableFeature('DocsSaver Pro'),
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAA61E),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Go Pro',
                          style: TextStyle(
                            color: Color(0xFF241400),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('pro_banner_close_btn'),
              onTap: () => setState(() => _isProBannerVisible = false),
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final actions = [
      (
        'Take Photo',
        Icons.camera_alt_rounded,
        const Color(0xFFD97706),
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFF2DC),
        _handleTakePhoto,
      ),
      (
        'Add Link',
        Icons.link_rounded,
        const Color(0xFF1E5E48),
        isDark ? const Color(0xFF23332F) : const Color(0xFFE5EFE9),
        _handleAddLink,
      ),
      (
        'Add Video',
        Icons.videocam_rounded,
        const Color(0xFFE76535),
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFEBE3),
        _handleAddVideo,
      ),
      (
        'Add Note',
        Icons.edit_note_rounded,
        const Color(0xFFD97706),
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFF2DC),
        _handleAddNote,
      ),
      (
        'Smart Scan',
        Icons.document_scanner_rounded,
        const Color(0xFFE76535),
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFEBE3),
        _handleScanDocument,
      ),
      (
        'Choose File',
        Icons.description_rounded,
        const Color(0xFF2B5EA7),
        isDark ? const Color(0xFF23332F) : const Color(0xFFE8EEF8),
        _handleChooseFile,
      ),
      (
        'Voice Note',
        Icons.mic_rounded,
        const Color(0xFFD97706),
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFF2DC),
        _handleRecordVoice,
      ),
      (
        'Google Drive',
        Icons.add_to_drive_rounded,
        Colors.white,
        isDark ? const Color(0xFF23332F) : const Color(0xFFFFF2DC),
        _openGooglePicker,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 82,
          mainAxisSpacing: 10,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final action = actions[index];
          final label = action.$1;
          return InkWell(
            key: Key('home_quick_action_$label'),
            onTap: action.$5,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: action.$4,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: label == 'Google Drive'
                      ? Image.asset(
                          'assets/images/google_drive.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        )
                      : Icon(action.$2, color: action.$3, size: 24),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentMemoriesSection(
    BuildContext context,
    List<MemoryEntity> memories,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSectionTitle(context, 'Recent memories'),
              InkWell(
                key: const Key('home_recent_memories_see_all_btn'),
                onTap: () {
                  if (widget.onSavedTap != null) {
                    widget.onSavedTap!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SavedScreen()),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (memories.isEmpty)
            _buildEmptyRecentMemoriesCard(context)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: memories.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final memory = memories[index];
                return _buildRecentMemoryCard(context, memory);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyRecentMemoriesCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderOf(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceTintOf(context),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_stories_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No recent memories yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap any quick action above to start capturing your ideas and files.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMemoryCard(BuildContext context, MemoryEntity memory) {
    final cleanSnippet = memory.content
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .trim();

    final timeAgo = _formatDate(memory.clientCreatedAt);
    final categoryText = memory.category.isNotEmpty
        ? memory.category
        : 'General';
    final (icon, iconBg, iconColor) = _memoryIconAndColor(context, memory);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MemoryDetailScreen(memoryId: memory.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardBackgroundOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      memory.title.isNotEmpty
                          ? memory.title
                          : 'Untitled Memory',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          categoryText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ' • $timeAgo',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                    if (cleanSnippet.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cleanSnippet,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondaryOf(context),
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textSecondaryOf(context),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  if (value == 'open') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MemoryDetailScreen(memoryId: memory.id),
                      ),
                    );
                  } else if (value == 'delete') {
                    context.read<CaptureBloc>().add(
                      DeleteMemoryEvent(memory.id),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Memory deleted'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Open'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, Color) _memoryIconAndColor(BuildContext context, MemoryEntity memory) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const darkBg = Color(0xFF23332F);
    final cat = memory.category.toLowerCase();
    final media = memory.mediaUrl?.toLowerCase() ?? '';

    if (media.endsWith('.mp4') || media.endsWith('.mov') || cat == 'video') {
      return (
        Icons.videocam_rounded,
        isDark ? darkBg : const Color(0xFFFFEBE3),
        const Color(0xFFE76535),
      );
    }
    if (media.endsWith('.jpg') ||
        media.endsWith('.jpeg') ||
        media.endsWith('.png') ||
        cat == 'photo') {
      return (
        Icons.image_rounded,
        isDark ? darkBg : const Color(0xFFEEF2FF),
        const Color(0xFF4F46E5),
      );
    }
    if (cat == 'audio' || cat == 'voice') {
      return (
        Icons.mic_rounded,
        isDark ? darkBg : const Color(0xFFECFDF5),
        const Color(0xFF059669),
      );
    }
    if (cat == 'link') {
      return (
        Icons.link_rounded,
        isDark ? darkBg : const Color(0xFFFFFBEB),
        const Color(0xFFD97706),
      );
    }
    if (cat == 'document' ||
        cat == 'note' ||
        cat == 'notes' ||
        media.endsWith('.pdf')) {
      return (
        Icons.description_outlined,
        isDark ? darkBg : const Color(0xFFE5EFE9),
        const Color(0xFF1E5E48),
      );
    }
    if (cat == 'work' || cat == 'study') {
      return (
        Icons.folder_open_rounded,
        isDark ? darkBg : const Color(0xFFF5F3FF),
        const Color(0xFF7C3AED),
      );
    }
    return (
      Icons.description_outlined,
      isDark ? darkBg : const Color(0xFFE5EFE9),
      const Color(0xFF1E5E48),
    );
  }

  String _formatDate(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) return 'Just now';
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final userName = _getUserName();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBgColor = isDark ? const Color(0xFF0F1715) : AppColors.backgroundOf(context);
    final bodyBgColor = isDark ? const Color(0xFF0F1715) : const Color(0xFFF8F8FC);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: scaffoldBgColor,
        body: Stack(
          children: [
            Container(
              color: scaffoldBgColor,
              child: SafeArea(
                top: false,
                bottom: true,
                child: BlocBuilder<CaptureBloc, CaptureState>(
                  builder: (context, state) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<String?>(
                            valueListenable: ProfileNotifier.nameNotifier,
                            builder: (context, newName, _) {
                              final nameToUse = (newName != null && newName.trim().isNotEmpty) ? newName.trim() : userName;
                              return _buildHeader(context, nameToUse, _getUserInitial(nameToUse));
                            },
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: MediaQuery.sizeOf(context).height,
                            ),
                            child: Container(
                              width: double.infinity,
                              color: bodyBgColor,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDashboard(
                                    context,
                                    _memoriesFromState(state),
                                  ),
                                  SizedBox(
                                    height:
                                        80 +
                                        MediaQuery.paddingOf(context).bottom,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: MediaQuery.of(context).padding.top,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? const Color(0xFF0C1412) 
                    : const Color(0xFF0F3E32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCaptureBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackgroundOf(context),
      barrierColor: Colors.black.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderOf(sheetContext),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'What do you want to save?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(sheetContext),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.camera_alt_rounded,
                        title: 'Take Photo',
                        isTakePhoto: true,
                        iconColor: const Color(0xFFD97706),
                        iconBackground: const Color(0xFFFFF2DC),
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.document_scanner_rounded,
                        title: 'Scan Document',
                        isTakePhoto: false,
                        iconColor: const Color(0xFFE76535),
                        iconBackground: const Color(0xFFFFEBE3),
                        aliasKey: 'capture_option_Scan Document',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.edit_note_rounded,
                        title: 'Add Note',
                        isTakePhoto: false,
                        iconColor: const Color(0xFFD97706),
                        iconBackground: const Color(0xFFFFF2DC),
                        aliasKey: 'capture_option_Add Note',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.mic_rounded,
                        title: 'Voice Note',
                        isTakePhoto: false,
                        iconColor: const Color(0xFFD97706),
                        iconBackground: const Color(0xFFFFF2DC),
                        aliasKey: 'capture_option_Record Voice',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.description_rounded,
                        title: 'Choose File',
                        isTakePhoto: false,
                        iconColor: const Color(0xFF2B5EA7),
                        iconBackground: const Color(0xFFE8EEF8),
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.link_rounded,
                        title: 'Add Link',
                        isTakePhoto: false,
                        iconColor: const Color(0xFF1E5E48),
                        iconBackground: const Color(0xFFE5EFE9),
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.add_to_drive_rounded,
                        title: 'Google Drive',
                        isTakePhoto: false,
                        iconColor: const Color(0xFFD97706),
                        iconBackground: const Color(0xFFFFF2DC),
                        iconAsset: 'assets/images/google_drive.png',
                      ),
                      _buildCaptureOption(
                        context: sheetContext,
                        icon: Icons.videocam_rounded,
                        title: 'Add Video',
                        isTakePhoto: false,
                        iconColor: const Color(0xFFE76535),
                        iconBackground: const Color(0xFFFFEBE3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleTakePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Add Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose an option to capture or upload',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('photo_option_camera'),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F7FC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4E3985).withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4E3985,
                            ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Color(0xFF4E3985),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Take Picture',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Open camera to snap a new photo',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('photo_option_gallery'),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F7FC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4E3985).withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4E3985,
                            ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.photo_library_rounded,
                            color: Color(0xFF4E3985),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Choose from Gallery',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Select an existing photo from device',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;
    if (!mounted) return;

    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photo == null) return;
      if (!mounted) return;

      // Handle Scoped Storage & Image Bytes for Gallery/Camera:
      // Ensure the picked XFile is properly read as bytes: await photo.readAsBytes()
      // and compress / resize images (target max 1024-1280px / quality 80)
      final localImageFile = await ImageUtils.processAndPersistImageXFile(
        photo,
        maxDimension: 1280,
        quality: 80,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoReviewScreen(
            imageFile: localImageFile,
            ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
          ),
        ),
      );

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message =
            errorMsg.contains('permission') || errorMsg.contains('denied')
            ? (source == ImageSource.camera
                  ? 'Camera permission denied. Please enable camera access in Settings.'
                  : 'Gallery access denied. Please enable photos permission in Settings.')
            : 'Unable to open image picker: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _handleAddVideo() async {
    try {
      final picker = ImagePicker();
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppColors.cardBackgroundOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Capture Video',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(sheetCtx),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE4EC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.videocam_outlined,
                      color: Color(0xFFE91E63),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    'Record Video',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(sheetCtx),
                    ),
                  ),
                  subtitle: const Text('Use camera to record a video'),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE7FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.video_library_outlined,
                      color: Color(0xFF6D35E8),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(sheetCtx),
                    ),
                  ),
                  subtitle: const Text(
                    'Pick an existing video from your device',
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        ),
      );

      if (source == null) return;
      if (!mounted) return;

      final video = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 45),
      );

      if (video == null) return;
      if (!mounted) return;

      final videoFile = File(video.path);
      if (!videoFile.existsSync()) return;

      final videoName = video.name.isNotEmpty ? video.name : 'Video Note';
      if (mounted) {
        context.read<CaptureBloc>().add(
          AddMemoryEvent(
            title: 'Video Note (${DateFormat('MMM d').format(DateTime.now())})',
            content: '', // Truthful: empty until Gemini video analysis finishes
            category: 'General',
            tags: const ['video'],
            mediaUrl: videoFile.path,
            aiStatus: 'pending',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video saved: $videoName (AI analyzing...)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message =
            errorMsg.contains('permission') || errorMsg.contains('denied')
            ? 'Camera / Gallery permission denied. Please enable access in Settings.'
            : 'Unable to capture video: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _handleScanDocument() async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        scannerSource: ScannerSource.camera,
        androidScannerMode: AndroidScannerMode.full,
      );

      if (pictures == null || pictures.isEmpty) {
        return;
      }

      if (!mounted) return;

      final scannedFile = File(pictures.first);
      if (!scannedFile.existsSync()) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoReviewScreen(
            imageFile: scannedFile,
            isDocumentScan: true,
            ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
          ),
        ),
      );

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message =
            errorMsg.contains('permission') || errorMsg.contains('denied')
            ? 'Camera permission denied. Please enable camera access in Settings.'
            : 'Unable to scan document: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _handleAddLink() async {
    final url = await AddLinkBottomSheet.show(context);
    if (url == null || url.isEmpty || !mounted) return;

    final driveFileId =
        GoogleDocsLinkExtractor.extractFileId(url) ??
        GoogleDriveLinkExtractor.extractFileId(url);
    if (driveFileId != null) {
      await _handleGoogleDocsImport(driveFileId, url);
      return;
    }

    final isOnline = await NetworkChecker.isConnected();
    final parsedUri = Uri.tryParse(url) ?? Uri();
    final detectedProvider = LinkProviderDetector.detect(parsedUri);

    LinkMetadata metadata = LinkMetadata(url: url, provider: detectedProvider);
    AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');

    if (isOnline) {
      if (!mounted) return;
      String loadingStatus = 'Fetching link details...';
      StateSetter? dialogSetState;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              dialogSetState = setModalState;
              return PopScope(
                canPop: false,
                child: AlertDialog(
                  backgroundColor: AppColors.background,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  content: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          loadingStatus,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      try {
        metadata = await _linkMetadataExtractor.extract(url);
      } catch (_) {}

      if (dialogSetState != null && mounted) {
        dialogSetState!(() {
          loadingStatus = 'Analyzing with AI...';
        });
      }

      try {
        final buffer = StringBuffer();
        buffer.writeln('URL: ${metadata.url}');
        if (metadata.provider == LinkProvider.youtube) {
          buffer.writeln('Platform: YouTube');
          if (metadata.creator != null && metadata.creator!.isNotEmpty) {
            buffer.writeln('Channel: ${metadata.creator}');
          }
        } else if (metadata.provider == LinkProvider.tiktok) {
          buffer.writeln('Platform: TikTok');
          if (metadata.creator != null && metadata.creator!.isNotEmpty) {
            buffer.writeln('Creator: ${metadata.creator}');
          }
        } else if (metadata.provider == LinkProvider.instagram) {
          buffer.writeln('Platform: Instagram');
          if (metadata.creator != null && metadata.creator!.isNotEmpty) {
            buffer.writeln('Creator: ${metadata.creator}');
          }
        }
        if (metadata.title != null && metadata.title!.isNotEmpty) {
          if (metadata.provider == LinkProvider.tiktok ||
              metadata.provider == LinkProvider.instagram) {
            buffer.writeln('Caption: ${metadata.title}');
          } else {
            buffer.writeln('Title: ${metadata.title}');
          }
        }
        if (metadata.description != null &&
            metadata.description!.isNotEmpty &&
            metadata.description != metadata.title) {
          buffer.writeln('Description: ${metadata.description}');
        }
        if (metadata.transcript != null && metadata.transcript!.isNotEmpty) {
          buffer.writeln('\nTranscript:\n${metadata.transcript}');
        } else if (metadata.readableContent != null &&
            metadata.readableContent!.isNotEmpty) {
          if (metadata.provider == LinkProvider.genericWeb) {
            buffer.writeln('\nContent:\n${metadata.readableContent}');
          }
        }
        final contentForAi = buffer.toString().trim();

        aiResult = await _effectiveIngestMemoryUseCase(ocrText: contentForAi);
      } catch (_) {
        aiResult = AiIngestionResult.empty(aiStatus: 'pending');
      }

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    final initialTitle = aiResult.title.isNotEmpty
        ? aiResult.title
        : (metadata.title?.isNotEmpty == true
              ? metadata.title!
              : (metadata.provider == LinkProvider.youtube
                    ? 'YouTube Video (${DateFormat('MMM d').format(DateTime.now())})'
                    : (metadata.provider == LinkProvider.tiktok
                          ? 'TikTok Video (${DateFormat('MMM d').format(DateTime.now())})'
                          : (metadata.provider == LinkProvider.instagram
                                ? (metadata.extraMetadata?['postType'] == 'reel'
                                      ? 'Instagram Reel (${DateFormat('MMM d').format(DateTime.now())})'
                                      : 'Instagram Post (${DateFormat('MMM d').format(DateTime.now())})')
                                : (metadata.siteName?.isNotEmpty == true
                                      ? '${metadata.siteName} Link'
                                      : 'Web Link (${DateFormat('MMM d').format(DateTime.now())})')))));

    final initialTags = List<String>.from(aiResult.tags);
    if (!initialTags.contains('link')) {
      initialTags.add('link');
    }
    if (metadata.provider == LinkProvider.youtube &&
        !initialTags.contains('youtube')) {
      initialTags.add('youtube');
    }
    if (metadata.provider == LinkProvider.tiktok &&
        !initialTags.contains('tiktok')) {
      initialTags.add('tiktok');
    }
    if (metadata.provider == LinkProvider.instagram &&
        !initialTags.contains('instagram')) {
      initialTags.add('instagram');
    }

    final rawTextBuffer = StringBuffer();
    rawTextBuffer.writeln(metadata.url);
    if (metadata.creator != null && metadata.creator!.isNotEmpty) {
      if (metadata.provider == LinkProvider.youtube) {
        rawTextBuffer.writeln('\nChannel: ${metadata.creator}');
      } else {
        rawTextBuffer.writeln('\nCreator: ${metadata.creator}');
      }
    }
    if (metadata.title != null && metadata.title!.isNotEmpty) {
      rawTextBuffer.writeln('\n${metadata.title}');
    }
    if (metadata.description != null &&
        metadata.description!.isNotEmpty &&
        metadata.description != metadata.title) {
      rawTextBuffer.writeln('\n${metadata.description}');
    }
    if (metadata.readableContent != null &&
        metadata.readableContent!.isNotEmpty) {
      rawTextBuffer.writeln('\n\n${metadata.readableContent}');
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryReviewScreen(
          imageFile: null,
          linkUrl: metadata.url,
          readableContent: metadata.readableContent,
          previewImageUrl: metadata.imageUrl,
          initialTitle: initialTitle,
          initialContent: metadata.url,
          rawOcrText: metadata.readableContent?.isNotEmpty == true
              ? metadata.readableContent!
              : rawTextBuffer.toString().trim(),
          initialCategory: aiResult.category,
          initialTags: initialTags,
          initialSummary: aiResult.summary.isNotEmpty
              ? aiResult.summary
              : (metadata.description ?? ''),
          entities: aiResult.entities,
          aiStatus: aiResult.aiStatus,
          createdAt: DateTime.now(),
          isOffline: !isOnline,
          ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
        ),
      ),
    );

    if (mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleGoogleDocsImport(
    String fileId,
    String rawUrl, {
    String? accessToken,
  }) async {
    if (!mounted) return;
    if (accessToken != null && accessToken.isNotEmpty) {
      GoogleDriveService.cachedAccessToken = accessToken;
    }

    String loadingStatus = 'Importing Google Doc...';
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            dialogSetState = setModalState;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        loadingStatus,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    GoogleDocEntity doc;
    try {
      doc = await _effectiveGoogleAuthRepository.importDoc(fileId);
    } on GoogleDocsImportException catch (e, stackTrace) {
      debugPrint('❌ GOOGLE DRIVE IMPORT ERROR: $e \n$stackTrace');
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        String userMessage;
        switch (e.code) {
          case 'FILE_NOT_FOUND':
            userMessage =
                'File not found or not accessible under current Google Drive permissions. Please use "Choose from Google Drive" to select and authorize the file.';
            break;
          case 'PERMISSION_DENIED':
            GoogleDriveService.clearSession();
            userMessage =
                'Permission denied. Your Google account does not have access to this document.';
            break;
          case 'TOKEN_REVOKED':
            GoogleDriveService.clearSession();
            userMessage =
                'Google authorization expired or was revoked. Please reconnect in Settings.';
            break;
          case 'GOOGLE_NOT_CONNECTED':
          case 'NOT_CONNECTED':
            userMessage =
                'Google Drive is not connected. Please connect your Google account in Settings.';
            break;
          case 'UNSUPPORTED_ARCHIVE':
            userMessage =
                'ZIP archives cannot be imported directly. Please extract and import individual files.';
            break;
          case 'UNSUPPORTED_BINARY':
            userMessage =
                'Executable and binary system files are not supported.';
            break;
          case 'UNSUPPORTED_MIME_TYPE':
            userMessage = e.message.isNotEmpty
                ? e.message
                : 'File format is not supported for import.';
            break;
          case 'EMPTY_DOCUMENT':
            userMessage =
                'The selected file contains no readable text or supported media.';
            break;
          case 'DOCUMENT_TOO_LARGE':
            userMessage = e.message.isNotEmpty
                ? e.message
                : 'The file is too large to import.';
            break;
          default:
            userMessage = e.message.isNotEmpty
                ? e.message
                : 'Failed to import Google Drive file.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: e.code == 'FILE_NOT_FOUND'
                ? SnackBarAction(
                    label: 'Choose File',
                    onPressed: _openGooglePicker,
                  )
                : null,
          ),
        );
      }
      return;
    } catch (e, stackTrace) {
      debugPrint('❌ GOOGLE DRIVE IMPORT ERROR: $e \n$stackTrace');
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import Google Drive file: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (dialogSetState != null && mounted) {
      dialogSetState!(() {
        loadingStatus = 'Analyzing file with AI...';
      });
    }

    AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');
    try {
      if (doc.mediaBase64 != null && doc.mediaBase64!.isNotEmpty) {
        if (doc.mediaType == 'pdf') {
          aiResult = await _effectiveIngestMemoryUseCase(
            ocrText: doc.content,
            documentBase64: doc.mediaBase64,
            mimeType: 'application/pdf',
          );
        } else if (doc.mediaType == 'image') {
          aiResult = await _effectiveIngestMemoryUseCase(
            ocrText: doc.content,
            imageBase64: doc.mediaBase64,
            mimeType: doc.mimeType,
          );
        } else {
          aiResult = await _effectiveIngestMemoryUseCase(ocrText: doc.content);
        }
      } else {
        aiResult = await _effectiveIngestMemoryUseCase(ocrText: doc.content);
      }
    } catch (_) {
      aiResult = AiIngestionResult.empty(aiStatus: 'pending');
    }

    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;

    final initialTitle = (aiResult.title.isNotEmpty)
        ? aiResult.title
        : doc.title;
    final initialTags = List<String>.from(aiResult.tags);
    if (!initialTags.contains('google-drive')) {
      initialTags.add('google-drive');
    }
    if (!initialTags.contains('document')) {
      initialTags.add('document');
    }

    final effectiveContent =
        (aiResult.documentText != null &&
            aiResult.documentText!.trim().isNotEmpty)
        ? aiResult.documentText!.trim()
        : doc.content;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryReviewScreen(
          imageFile: null,
          linkUrl: doc.webViewLink.isNotEmpty ? doc.webViewLink : rawUrl,
          readableContent: effectiveContent,
          initialTitle: initialTitle,
          initialContent: effectiveContent,
          rawOcrText: effectiveContent,
          initialCategory: aiResult.category.isNotEmpty
              ? aiResult.category
              : AppStrings.categoryWork,
          initialTags: initialTags,
          initialSummary: aiResult.summary,
          entities: aiResult.entities,
          aiStatus: aiResult.aiStatus,
          createdAt: DateTime.now(),
          isOffline: false,
          ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
        ),
      ),
    );

    if (mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleAddNote() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const NoteComposeScreen()));

    if (saved == true && mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleRecordVoice() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VoiceRecordScreen()));

    if (saved == true && mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleChooseFile({FilePickerService? filePickerService}) async {
    try {
      final service =
          filePickerService ??
          widget.filePickerService ??
          const DefaultFilePickerService();
      const supportedExtensions = [
        'pdf',
        'txt',
        'md',
        'csv',
        'json',
        'png',
        'jpg',
        'jpeg',
        'webp',
      ];

      final picked = await service.pickFile(
        allowedExtensions: supportedExtensions,
      );

      if (picked == null) return;

      const maxFileSize = 15 * 1024 * 1024;
      if (picked.size > maxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected file exceeds the 15 MB size limit.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final sourcePath = picked.path;
      if (sourcePath == null) return;
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) return;

      final ext = (picked.extension ?? sourcePath.split('.').last)
          .toLowerCase()
          .replaceAll('.', '')
          .trim();
      if (!supportedExtensions.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Unsupported file format (.$ext). Supported: PDF, TXT, MD, CSV, JSON, PNG, JPG, WEBP.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();

      if (const ['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
        final copyPath =
            '${appDir.path}/memory_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final localImageFile = sourceFile.copySync(copyPath);

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhotoReviewScreen(
              imageFile: localImageFile,
              ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
            ),
          ),
        );
        if (mounted) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
        }
        return;
      }

      final docDir = Directory('${appDir.path}/documents');
      if (!docDir.existsSync()) {
        docDir.createSync(recursive: true);
      }
      final persistentPath =
          '${docDir.path}/doc_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final persistentFile = sourceFile.copySync(persistentPath);

      final isOnline = await NetworkChecker.isConnected();

      if (const ['txt', 'md', 'csv', 'json'].contains(ext)) {
        final rawText = sourceFile.readAsStringSync();
        AiIngestionResult aiResult = AiIngestionResult.empty(
          aiStatus: 'pending',
        );

        if (isOnline) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Analyzing document with AI...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          try {
            aiResult = await _effectiveIngestMemoryUseCase(ocrText: rawText);
          } catch (_) {
            aiResult = AiIngestionResult.empty(aiStatus: 'pending');
          }

          if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        }

        if (!mounted) return;

        final tags = List<String>.from(aiResult.tags);
        if (!tags.contains('document')) {
          tags.add('document');
        }

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemoryReviewScreen(
              documentFile: persistentFile,
              initialTitle: aiResult.title.isNotEmpty
                  ? aiResult.title
                  : picked.name,
              initialContent: rawText,
              rawOcrText: rawText,
              initialCategory: aiResult.category,
              initialTags: tags,
              initialSummary: aiResult.summary,
              entities: aiResult.entities,
              aiStatus: aiResult.aiStatus,
              createdAt: DateTime.now(),
              isOffline: !isOnline,
              ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
            ),
          ),
        );

        if (mounted) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
        }
        return;
      }

      if (ext == 'pdf') {
        AiIngestionResult aiResult = AiIngestionResult.empty(
          aiStatus: 'pending',
        );

        if (isOnline) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Extracting PDF and analyzing with AI...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          try {
            final pdfBytes = persistentFile.readAsBytesSync();
            final pdfBase64 = base64Encode(pdfBytes);
            aiResult = await _effectiveIngestMemoryUseCase(
              ocrText: '',
              documentBase64: pdfBase64,
              mimeType: 'application/pdf',
            );
          } catch (_) {
            aiResult = AiIngestionResult.empty(aiStatus: 'pending');
          }

          if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        }

        if (!mounted) return;

        final extractedText = (aiResult.documentText ?? '').trim();
        final bool isAiSuccess =
            isOnline &&
            aiResult.aiStatus == 'processed' &&
            extractedText.isNotEmpty;

        final effectiveAiStatus = isOnline
            ? (isAiSuccess ? 'processed' : 'failed')
            : 'pending';

        final effectiveTitle = (isAiSuccess && aiResult.title.isNotEmpty)
            ? aiResult.title
            : picked.name;

        final effectiveSummary = isAiSuccess ? aiResult.summary : '';
        final effectiveCategory = isAiSuccess
            ? aiResult.category
            : AppStrings.categoryWork;
        final effectiveEntities = isAiSuccess
            ? aiResult.entities
            : const <LivingEntityItem>[];

        final tags = isAiSuccess
            ? List<String>.from(aiResult.tags)
            : <String>['document', 'pdf'];
        if (!tags.contains('document')) tags.add('document');
        if (!tags.contains('pdf')) tags.add('pdf');

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemoryReviewScreen(
              documentFile: persistentFile,
              initialTitle: effectiveTitle,
              initialContent: extractedText,
              rawOcrText: extractedText.isNotEmpty ? extractedText : null,
              initialCategory: effectiveCategory,
              initialTags: tags,
              initialSummary: effectiveSummary,
              entities: effectiveEntities,
              aiStatus: effectiveAiStatus,
              createdAt: DateTime.now(),
              isOffline: !isOnline,
              ingestMemoryUseCase: _effectiveIngestMemoryUseCase,
            ),
          ),
        );

        if (mounted) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to process file: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCaptureOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool isTakePhoto,
    Color? iconColor,
    Color? iconBackground,
    String? iconAsset,
    String? aliasKey,
  }) {
    final inkWell = InkWell(
      key: Key('capture_option_$title'),
      onTap: () async {
        Navigator.of(context).pop();
        if (isTakePhoto || title == 'Take Photo') {
          await _handleTakePhoto();
        } else if (title == 'Scan Document' || title == 'Scan Doc') {
          await _handleScanDocument();
        } else if (title == 'Add Link' || title == 'Save Link') {
          await _handleAddLink();
        } else if (title == 'Add Note') {
          await _handleAddNote();
        } else if (title == 'Record Voice' || title == 'Voice Note') {
          await _handleRecordVoice();
        } else if (title == 'Choose File' || title == 'Import File') {
          await _handleChooseFile();
        } else if (title == 'Google Drive') {
          await _openGooglePicker();
        } else if (title == 'Add Video') {
          await _handleAddVideo();
        } else {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text('$title capture flow will be available soon.'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context), width: 1.0),
        ),
        child: Row(
          children: [
            iconAsset == null
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBackground ?? AppColors.surfaceTintOf(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor ?? AppColors.primary,
                      size: 19,
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBackground ?? const Color(0xFFFFF2DC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    // Shrinks the drive logo to match the ~18-20px icon footprint of siblings
                    padding: const EdgeInsets.all(12.0),
                    child: Image.asset(iconAsset, fit: BoxFit.contain),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (aliasKey != null && aliasKey != 'capture_option_$title') {
      return Material(
        color: Colors.transparent,
        child: KeyedSubtree(key: Key(aliasKey), child: inkWell),
      );
    }

    return Material(color: Colors.transparent, child: inkWell);
  }

  Widget _buildHeader(
    BuildContext context,
    String userName,
    String userInitial,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 36,
          child: ColoredBox(color: AppColors.backgroundOf(context)),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, topPadding + 6, 20, 18),
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0C1412), Color(0xFF0C1412)],
                  )
                : _unifiedSageHeaderGradient,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(36),
              bottomRight: Radius.circular(36),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.kDeepSagePine.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Greeting and account actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Hey $userName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text('👋', style: TextStyle(fontSize: 20)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Let's capture more ideas today",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bell Icon Button
                      _buildHeaderIconButton(
                        key: const Key('home_bell_btn'),
                        icon: Icons.notifications_none_rounded,
                        hasBadge: true,
                        onTap: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No new notifications'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // User Profile Avatar Button with letter 'S'
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const Key('home_profile_avatar_btn'),
                          onTap: () {
                            String email = '';
                            try {
                              final user = Supabase.instance.client.auth.currentUser;
                              if (user?.email != null) {
                                email = user!.email!;
                              }
                            } catch (_) {}
                            final initialImage = ProfileNotifier.imagePathNotifier.value != null 
                                ? File(ProfileNotifier.imagePathNotifier.value!) 
                                : null;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(
                              initialName: userName,
                              initialEmail: email,
                              initialProfileImage: initialImage,
                            )));
                          },
                          borderRadius: BorderRadius.circular(100),
                          child: ValueListenableBuilder<String?>(
                            valueListenable: ProfileNotifier.imagePathNotifier,
                            builder: (context, imagePath, _) {
                              return Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryOf(context),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryOf(
                                        context,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  image: (imagePath != null && imagePath.isNotEmpty)
                                      ? DecorationImage(
                                          image: imagePath.startsWith('http')
                                              ? NetworkImage(imagePath) as ImageProvider
                                              : FileImage(File(imagePath)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: (imagePath == null || imagePath.isEmpty)
                                    ? Center(
                                        child: Text(
                                          userInitial.isNotEmpty ? userInitial : 'S',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Search bar
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('home_search_btn'),
                  onTap: () {
                    if (widget.onSearchTap != null) {
                      widget.onSearchTap!();
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    padding: const EdgeInsets.fromLTRB(16, 5, 6, 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF13201D)
                          : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(28),
                      border: isDark
                          ? Border.all(color: const Color(0x14FFFFFF), width: 1.0)
                          : Border.all(color: Colors.white, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.30 : 0.07,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF64748B),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search your memories',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1B2C27)
                                : const Color(0xFFE5EFE9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: isDark
                                ? const Color(0xFFA8C9B5)
                                : const Color(0xFF0F3E32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderIconButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
    bool hasBadge = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : const Color(0xFFFCFBF7),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                color: isDark ? Colors.white : const Color(0xFF0F3E32),
                size: 20,
              ),
              if (hasBadge)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF9B78),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySectionsList(
    BuildContext context,
    List<MemoryEntity> memories,
  ) {
    return SizedBox(
      height: 116,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: CategorySectionsData.sections.length,
        itemBuilder: (context, index) {
          final section = CategorySectionsData.sections[index];
          final itemCount = memories.where((memory) {
            final memoryCategory = memory.category.trim().toLowerCase();
            return section.categories.any((category) {
              final categoryName = category.name.toLowerCase();
              return categoryName == memoryCategory ||
                  categoryName.startsWith('$memoryCategory &');
            });
          }).length;
          final isLast = index == CategorySectionsData.sections.length - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: SizedBox(
              width: 106,
              child: _buildCategorySectionCard(context, section, itemCount),
            ),
          );
        },
      ),
    );
  }

  ({IconData icon, Color iconColor, Color circleBg, Color border})
  _categoryStyle(String sectionId) {
    return switch (sectionId) {
      'documents_records' => (
        icon: Icons.folder_rounded,
        iconColor: const Color(0xFF2B5EA7),
        circleBg: const Color(0xFFE8EEF8),
        border: AppColors.border,
      ),
      'work_learning' => (
        icon: Icons.school_rounded,
        iconColor: const Color(0xFFD98A00),
        circleBg: const Color(0xFFFFF4D9),
        border: AppColors.border,
      ),
      'home_utilities' => (
        icon: Icons.home_rounded,
        iconColor: const Color(0xFFE25574),
        circleBg: const Color(0xFFFFEEF2),
        border: AppColors.gold100,
      ),
      'personal_life' => (
        icon: Icons.person_rounded,
        iconColor: const Color(0xFFE76535),
        circleBg: const Color(0xFFFFEBE3),
        border: AppColors.border,
      ),
      _ => (
        icon: Icons.folder_rounded,
        iconColor: AppColors.primary,
        circleBg: AppColors.toggleBackground,
        border: AppColors.border,
      ),
    };
  }

  Widget _buildCategorySectionCard(
    BuildContext context,
    CategorySectionItem section,
    int itemCount,
  ) {
    final style = _categoryStyle(section.id);
    final displayTitle = switch (section.id) {
      'documents_records' => 'Docs & Records',
      'work_learning' => 'Work & Learning',
      'home_utilities' => 'Home & Utilities',
      'personal_life' => 'Personal',
      _ => section.title,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('home_category_section_${section.id}'),
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 240),
              pageBuilder: (_, __, ___) => CategoryDetailScreen(
                section: section,
                onCaptureTap: openCaptureBottomSheet,
              ),
              transitionsBuilder: (_, animation, __, child) {
                final curvedSlide = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                final curvedFade = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                  reverseCurve: Curves.easeIn,
                );

                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0.0),
                    end: Offset.zero,
                  ).animate(curvedSlide),
                  child: FadeTransition(
                    opacity: Tween<double>(
                      begin: 0.0,
                      end: 1.0,
                    ).animate(curvedFade),
                    child: child,
                  ),
                );
              },
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardBackgroundOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.circleBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: style.iconColor.withValues(alpha: 0.18),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Icon(style.icon, color: style.iconColor, size: 20),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textPrimaryOf(context),
                  letterSpacing: -0.2,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$itemCount items',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : const Color(0xFF71827B),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldenCrownPainter extends CustomPainter {
  const _GoldenCrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    final gradient = const LinearGradient(
      colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(rect);

    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Crown body
    final path = Path()
      ..moveTo(w * 0.10, h * 0.76)
      ..lineTo(w * 0.08, h * 0.36)
      ..lineTo(w * 0.32, h * 0.54)
      ..lineTo(w * 0.50, h * 0.20)
      ..lineTo(w * 0.68, h * 0.54)
      ..lineTo(w * 0.92, h * 0.36)
      ..lineTo(w * 0.90, h * 0.76)
      ..close();

    canvas.drawPath(path, paint);

    // Peak jewels
    canvas.drawCircle(Offset(w * 0.08, h * 0.32), w * 0.065, paint);
    canvas.drawCircle(Offset(w * 0.50, h * 0.16), w * 0.075, paint);
    canvas.drawCircle(Offset(w * 0.92, h * 0.32), w * 0.065, paint);

    // Base decorative band
    final bandPaint = Paint()
      ..color = const Color(0xFFFDE68A)
      ..style = PaintingStyle.fill;
    final bandRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.76, w * 0.84, h * 0.10),
      const Radius.circular(3),
    );
    canvas.drawRRect(bandRRect, bandPaint);

    // Base band jewel dots
    final dotPaint = Paint()
      ..color = const Color(0xFFB45309)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.28, h * 0.81), 1.5, dotPaint);
    canvas.drawCircle(Offset(w * 0.50, h * 0.81), 2.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.72, h * 0.81), 1.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
