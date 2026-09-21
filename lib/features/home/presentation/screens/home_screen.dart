import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../capture/presentation/screens/memory_review_screen.dart';
import '../../../capture/presentation/screens/photo_review_screen.dart';
import '../../../capture/presentation/screens/note_compose_screen.dart';
import '../../../capture/presentation/screens/voice_record_screen.dart';
import '../../../capture/presentation/widgets/add_link_dialog.dart';
import '../../../brain_ai/data/datasources/ai_remote_data_source.dart';
import '../../../brain_ai/data/repositories/ai_repository_impl.dart';
import '../../../brain_ai/domain/entities/ai_ingestion_result.dart';
import '../../../brain_ai/domain/usecases/ingest_memory_usecase.dart';
import '../../../search/presentation/screens/search_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import '../../../../core/network/network_checker.dart';
// ignore: depend_on_referenced_packages
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../../../core/utils/google_docs_link_extractor.dart';
import '../../../../core/utils/google_drive_link_extractor.dart';
import '../../../../core/utils/link_metadata_extractor.dart';
import '../../../integrations/data/datasources/google_auth_remote_data_source.dart';
import '../../../integrations/data/repositories/google_auth_repository_impl.dart';
import '../../../integrations/domain/entities/google_doc_entity.dart';
import '../../../integrations/domain/entities/google_integration_status.dart';
import '../../../integrations/domain/repositories/google_auth_repository.dart';
import '../../domain/models/category_section.dart';
import 'category_detail_screen.dart';


class _FallbackAiRemoteDataSource implements AiRemoteDataSource {
  @override
  Future<Map<String, dynamic>> invokeIngestion({
    required String content,
    String? title,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
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

  const HomeScreen({
    super.key,
    this.userName,
    this.ingestMemoryUseCase,
    this.linkMetadataExtractor,
    this.filePickerService,
    this.googleAuthRepository,
    this.onSearchTap,
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
        AiRepositoryImpl(
          remoteDataSource: AiRemoteDataSourceImpl(),
        ),
      );
    } catch (_) {
      return IngestMemoryUseCase(
        AiRepositoryImpl(
          remoteDataSource: _FallbackAiRemoteDataSource(),
        ),
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

  @override
  void initState() {
    super.initState();
    _linkMetadataExtractor =
        widget.linkMetadataExtractor ?? LinkMetadataExtractor();
    context.read<CaptureBloc>().add(LoadMemoriesEvent());
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (mounted) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
          setState(() {});
        }
      });
    } catch (_) {}
    _initDeepLinks();
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
                  content: Text('Google Drive authorization failed ($errorDetail).'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          if (pickedFileId != null && pickedFileId.isNotEmpty) {
            _handleGoogleDocsImport(
              pickedFileId,
              GoogleDriveLinkExtractor.toCanonicalUrl(pickedFileId),
            );
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _openGooglePicker() async {
    final isOnline = await NetworkChecker.isConnected();
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Internet connection required for Google Drive.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

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
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch browser to open Google Drive.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
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
      return 'U';
    }
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final userName = _getUserName();
    final userInitial = _getUserInitial(userName);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        body: SafeArea(
          top: false,
          bottom: true,
          child: BlocBuilder<CaptureBloc, CaptureState>(
          builder: (context, state) {
            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.cardBackgroundOf(context),
              onRefresh: () async {
                context.read<CaptureBloc>().add(LoadMemoriesEvent());
                context.read<CaptureBloc>().add(SyncPendingMemoriesEvent());
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. Header with Straight Bottom and Search Bar Inside
                  SliverToBoxAdapter(
                    child: _buildHeaderWithSearch(context, userName, userInitial),
                  ),

                  // 2. Categories Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                      child: _buildCategoriesHeader(context),
                    ),
                  ),

                  // 3. Four Premium Category Navigation Section Cards
                  SliverToBoxAdapter(
                    child: _buildCategorySectionsList(context),
                  ),

                  // 4. Bottom spacing below category cards
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 24),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

  // Capture Bottom Sheet Modal
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
                      icon: Icons.camera_alt_outlined,
                      title: 'Take Photo',
                      isTakePhoto: true,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.document_scanner_outlined,
                      title: 'Scan Document',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.link_rounded,
                      title: 'Add Link',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.edit_note_rounded,
                      title: 'Add Note',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.mic_none_rounded,
                      title: 'Record Voice',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.attach_file_rounded,
                      title: 'Choose File',
                      isTakePhoto: false,
                    ),
                    _buildCaptureOption(
                      context: sheetContext,
                      icon: Icons.cloud_download_outlined,
                      title: 'Google Drive',
                      isTakePhoto: false,
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
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1800,
      );

      if (photo == null) return; // User cancelled camera safely
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoReviewScreen(
            imageFile: File(photo.path),
          ),
        ),
      );

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message = errorMsg.contains('permission') || errorMsg.contains('denied')
            ? 'Camera permission denied. Please enable camera access in Settings.'
            : 'Unable to open camera: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
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
        return; // User cancelled scanning safely
      }

      if (!mounted) return;

      final scannedFile = File(pictures.first);
      if (!scannedFile.existsSync()) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoReviewScreen(
            imageFile: scannedFile,
            isDocumentScan: true,
          ),
        ),
      );

      if (mounted) {
        context.read<CaptureBloc>().add(LoadMemoriesEvent());
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        final message = errorMsg.contains('permission') || errorMsg.contains('denied')
            ? 'Camera permission denied. Please enable camera access in Settings.'
            : 'Unable to scan document: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleAddLink() async {
    final url = await AddLinkBottomSheet.show(context);
    if (url == null || url.isEmpty || !mounted) return;

    // Detect Google Docs and Drive URLs before generic web-link extraction
    final driveFileId = GoogleDocsLinkExtractor.extractFileId(url) ??
        GoogleDriveLinkExtractor.extractFileId(url);
    if (driveFileId != null) {
      await _handleGoogleDocsImport(driveFileId, url);
      return;
    }

    final isOnline = await NetworkChecker.isConnected();
    final parsedUri = Uri.tryParse(url) ?? Uri();
    final detectedProvider = LinkProviderDetector.detect(parsedUri);

    LinkMetadata metadata = LinkMetadata(
      url: url,
      provider: detectedProvider,
    );
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
      } catch (_) {
        // Graceful fallback: original URL remains usable
      }

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
        } else if (metadata.readableContent != null && metadata.readableContent!.isNotEmpty) {
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
    if (metadata.provider == LinkProvider.youtube && !initialTags.contains('youtube')) {
      initialTags.add('youtube');
    }
    if (metadata.provider == LinkProvider.tiktok && !initialTags.contains('tiktok')) {
      initialTags.add('tiktok');
    }
    if (metadata.provider == LinkProvider.instagram && !initialTags.contains('instagram')) {
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
    if (metadata.readableContent != null && metadata.readableContent!.isNotEmpty) {
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

  Future<void> _handleGoogleDocsImport(String fileId, String rawUrl) async {
    final isOnline = await NetworkChecker.isConnected();
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Internet connection required to import Google Docs.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    String loadingStatus = 'Connecting to Google Drive...';
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
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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

    // 1. Verify Google integration status first
    try {
      final status = await _effectiveGoogleAuthRepository.getStatus();
      if (status.state != GoogleConnectionState.connected) {
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google Drive is not connected. Please connect your Google account in Settings.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    } catch (_) {
      // Proceed to importDoc; backend will validate integration as well
    }

    if (dialogSetState != null && mounted) {
      dialogSetState!(() {
        loadingStatus = 'Importing Google Drive file...';
      });
    }

    // 2. Call backend import_doc action
    GoogleDocEntity doc;
    try {
      doc = await _effectiveGoogleAuthRepository.importDoc(fileId);
    } on GoogleDocsImportException catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        String userMessage;
        switch (e.code) {
          case 'FILE_NOT_FOUND':
            userMessage = 'File not found or not accessible under current Google Drive permissions. Please use "Choose from Google Drive" to select and authorize the file.';
            break;
          case 'PERMISSION_DENIED':
            userMessage = 'Permission denied. Your Google account does not have access to this document.';
            break;
          case 'TOKEN_REVOKED':
            userMessage = 'Google authorization expired or was revoked. Please reconnect in Settings.';
            break;
          case 'GOOGLE_NOT_CONNECTED':
            userMessage = 'Google Drive is not connected. Please connect your Google account in Settings.';
            break;
          case 'UNSUPPORTED_ARCHIVE':
            userMessage = 'ZIP archives cannot be imported directly. Please extract and import individual files.';
            break;
          case 'UNSUPPORTED_BINARY':
            userMessage = 'Executable and binary system files are not supported.';
            break;
          case 'UNSUPPORTED_MIME_TYPE':
            userMessage = e.message.isNotEmpty ? e.message : 'File format is not supported for import.';
            break;
          case 'EMPTY_DOCUMENT':
            userMessage = 'The selected file contains no readable text or supported media.';
            break;
          case 'DOCUMENT_TOO_LARGE':
            userMessage = e.message.isNotEmpty ? e.message : 'The file is too large to import.';
            break;
          default:
            userMessage = e.message.isNotEmpty ? e.message : 'Failed to import Google Drive file.';
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
    } catch (e) {
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

    // 3. AI Ingestion using actual exported document content or media
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

    final initialTitle = (aiResult.title.isNotEmpty) ? aiResult.title : doc.title;
    final initialTags = List<String>.from(aiResult.tags);
    if (!initialTags.contains('google-drive')) {
      initialTags.add('google-drive');
    }
    if (!initialTags.contains('document')) {
      initialTags.add('document');
    }

    final effectiveContent = (aiResult.documentText != null && aiResult.documentText!.trim().isNotEmpty)
        ? aiResult.documentText!.trim()
        : doc.content;

    // 4. Navigate to Review & Save Screen with real extracted text
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryReviewScreen(
          imageFile: null,
          linkUrl: doc.webViewLink.isNotEmpty ? doc.webViewLink : rawUrl,
          readableContent: effectiveContent,
          initialTitle: initialTitle,
          initialContent: effectiveContent,
          rawOcrText: effectiveContent,
          initialCategory: aiResult.category.isNotEmpty ? aiResult.category : AppStrings.categoryWork,
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const NoteComposeScreen(),
      ),
    );

    if (saved == true && mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleRecordVoice() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const VoiceRecordScreen(),
      ),
    );

    if (saved == true && mounted) {
      context.read<CaptureBloc>().add(LoadMemoriesEvent());
    }
  }

  Future<void> _handleChooseFile({FilePickerService? filePickerService}) async {
    try {
      final service = filePickerService ?? widget.filePickerService ?? const DefaultFilePickerService();
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

      // Clean return if user canceled
      if (picked == null) return;

      // 15 MB file size limit
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
              content: Text('Unsupported file format (.$ext). Supported: PDF, TXT, MD, CSV, JSON, PNG, JPG, WEBP.'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();

      // 1. Image Files -> Route through existing PhotoReviewScreen
      if (const ['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
        final copyPath = '${appDir.path}/memory_${DateTime.now().millisecondsSinceEpoch}.$ext';
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

      // 2. Documents (PDF & Text files)
      final docDir = Directory('${appDir.path}/documents');
      if (!docDir.existsSync()) {
        docDir.createSync(recursive: true);
      }
      final persistentPath = '${docDir.path}/doc_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final persistentFile = sourceFile.copySync(persistentPath);

      final isOnline = await NetworkChecker.isConnected();

      if (const ['txt', 'md', 'csv', 'json'].contains(ext)) {
        // Text files: read actual string contents verbatim
        final rawText = sourceFile.readAsStringSync();
        AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');

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
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
              initialTitle: aiResult.title.isNotEmpty ? aiResult.title : picked.name,
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

      // 3. PDF Files
      if (ext == 'pdf') {
        AiIngestionResult aiResult = AiIngestionResult.empty(aiStatus: 'pending');

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
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
        final bool isAiSuccess = isOnline &&
            aiResult.aiStatus == 'processed' &&
            extractedText.isNotEmpty;

        final effectiveAiStatus = isOnline
            ? (isAiSuccess ? 'processed' : 'failed')
            : 'pending';

        final effectiveTitle = (isAiSuccess && aiResult.title.isNotEmpty)
            ? aiResult.title
            : picked.name;

        final effectiveSummary = isAiSuccess ? aiResult.summary : '';
        final effectiveCategory = isAiSuccess ? aiResult.category : AppStrings.categoryWork;
        final effectiveEntities = isAiSuccess ? aiResult.entities : const <LivingEntityItem>[];

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
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          if (isTakePhoto) {
            await _handleTakePhoto();
          } else if (title == 'Scan Document') {
            await _handleScanDocument();
          } else if (title == 'Add Link') {
            await _handleAddLink();
          } else if (title == 'Add Note') {
            await _handleAddNote();
          } else if (title == 'Record Voice') {
            await _handleRecordVoice();
          } else if (title == 'Choose File') {
            await _handleChooseFile();
          } else if (title == 'Google Drive') {
            await _openGooglePicker();
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
            border: Border.all(
              color: AppColors.borderOf(context),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceTintOf(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 18,
                ),
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
      ),
    );
  }

  // Cyan/Blue Straight Header with Search Bar Inside
  Widget _buildHeaderWithSearch(BuildContext context, String userName, String userInitial) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: Stack(
          children: [
            // Subtle connected-node/network pattern in background
            Positioned.fill(
              child: CustomPaint(
                painter: _NetworkPatternPainter(),
              ),
            ),

            // Header Content: Greeting, Subtitle, Right actions, and Search Bar fully inside
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left: Prominent "Hello {userName} 👋" & Subtitle "Your second brain is ready"
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Hello $userName',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textWhite,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    '👋',
                                    style: TextStyle(
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              AppStrings.homeReadySubtitle,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textWhite.withValues(alpha: 0.88),
                                letterSpacing: -0.1,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Right: Bell notification & Profile avatar
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Bell button with notification dot
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('home_bell_btn'),
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
                              borderRadius: BorderRadius.circular(100),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                      color: AppColors.textWhite,
                                      size: 20,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: AppColors.notificationBadge,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Profile Avatar [Dynamic Initial]
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('home_profile_avatar_btn'),
                              onTap: () {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                final isFallback =
                                    userName.toLowerCase() == 'there';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isFallback
                                          ? 'Your Second Brain'
                                          : '$userName\'s Second Brain',
                                    ),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.textWhite,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    userInitial,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Search Bar: fully inside the header
                  _buildSearchBar(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern Floating Search Bar Pill
  Widget _buildSearchBar(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (widget.onSearchTap != null) {
            widget.onSearchTap!();
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            );
          }
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.cardBackgroundOf(context),
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: AppColors.textSecondaryOf(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.homeSearchHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryOf(context).withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceTintOf(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Section Header: Categories
  Widget _buildCategoriesHeader(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        AppStrings.homeCategoriesHeader,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryOf(context),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  // Categories Section Cards List
  Widget _buildCategorySectionsList(BuildContext context) {
    return Column(
      children: CategorySectionsData.sections.map((section) {
        return _buildCategorySectionCard(context, section);
      }).toList(),
    );
  }

  // Premium Category Navigation Section Card
  Widget _buildCategorySectionCard(BuildContext context, CategorySectionItem section) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('home_category_section_${section.id}'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryDetailScreen(
                  section: section,
                  onCaptureTap: openCaptureBottomSheet,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardBackgroundOf(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.borderOf(context),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.violetTwilight500.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.toggleBackgroundOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderOf(context),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    section.icon,
                    color: AppColors.violetTwilight500,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.toggleBackgroundOf(context).withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.violetTwilight400,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle connected-node / network pattern custom painter for header background
class _NetworkPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Node coordinates scattered across header background
    final nodes = [
      Offset(size.width * 0.10, size.height * 0.28),
      Offset(size.width * 0.26, size.height * 0.65),
      Offset(size.width * 0.45, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.58),
      Offset(size.width * 0.80, size.height * 0.26),
      Offset(size.width * 0.94, size.height * 0.60),
      Offset(size.width * 0.74, size.height * 0.82),
    ];

    final edges = [
      [0, 1],
      [1, 2],
      [0, 2],
      [2, 3],
      [3, 4],
      [3, 6],
      [4, 5],
      [6, 5],
    ];

    for (final edge in edges) {
      canvas.drawLine(nodes[edge[0]], nodes[edge[1]], linePaint);
    }

    for (final node in nodes) {
      canvas.drawCircle(node, 6, glowPaint);
      canvas.drawCircle(node, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

