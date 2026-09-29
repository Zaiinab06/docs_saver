import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:url_launcher/url_launcher.dart';
// ignore: depend_on_referenced_packages
import 'package:app_links/app_links.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/profile_notifier.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../integrations/data/datasources/google_auth_remote_data_source.dart';
import '../../../integrations/data/repositories/google_auth_repository_impl.dart';
import '../../../integrations/domain/entities/google_integration_status.dart';
import '../../../integrations/presentation/cubit/google_auth_cubit.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  String _appVersion = '1.0.0';
  late final GoogleAuthCubit _googleAuthCubit;
  StreamSubscription<Uri>? _deepLinkSubscription;
  AppLinks? _appLinks;
  File? _profileImageFile;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _googleAuthCubit = GoogleAuthCubit(
      repository: GoogleAuthRepositoryImpl(
        remoteDataSource: GoogleAuthRemoteDataSourceImpl(),
      ),
    );
    _googleAuthCubit.checkStatus();
    _initDeepLinks();
    _loadAppVersion();
  }

  void _initDeepLinks() {
    try {
      _appLinks = AppLinks();
      _deepLinkSubscription = _appLinks?.uriLinkStream.listen((uri) {
        if (uri.scheme == 'secondbrain' && uri.host == 'oauth') {
          final status = uri.queryParameters['status'] ?? 'missing';
          final reason =
              uri.queryParameters['reason'] ??
              uri.queryParameters['error'] ??
              'none';
          debugPrint(
            '[Google OAuth] Deep link routed to callback: status=$status, reason=$reason.',
          );
          _googleAuthCubit.handleDeepLinkCallback(uri);
        }
      });
    } catch (_) {
      debugPrint('[Google OAuth] Deep-link listener initialization failed.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    _googleAuthCubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _googleAuthCubit.checkStatus();
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {}
  }

  String _getUserName(BuildContext context) {
    if (ProfileNotifier.nameNotifier.value != null && ProfileNotifier.nameNotifier.value!.trim().isNotEmpty) {
      return ProfileNotifier.nameNotifier.value!.trim();
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
    return 'DocsSaver User';
  }

  String _getUserEmail(BuildContext context) {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated &&
          authState.user.email != null &&
          authState.user.email!.isNotEmpty) {
        return authState.user.email!;
      }
      if (authState is AuthSuccess &&
          authState.user.email != null &&
          authState.user.email!.isNotEmpty) {
        return authState.user.email!;
      }
    } catch (_) {}
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user?.email != null && user!.email!.isNotEmpty) {
        return user.email!;
      }
    } catch (_) {}
    return 'user@docssaver.app';
  }


  Future<void> _confirmSignOut(BuildContext context, bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? AppColors.darkCardBackground
              : AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Sign Out',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out of DocsSaver?',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
              child: const Text(
                'Sign Out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.errorText,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(SignOutRequested());
    }
  }

  Future<void> _confirmDisconnectGoogle(bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? AppColors.darkCardBackground
              : AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Disconnect Google Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          content: Text(
            'Are you sure you want to disconnect your Google account? Your stored memories will not be deleted.',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
              child: const Text(
                'Disconnect',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.errorText,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _googleAuthCubit.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google account disconnected.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _navigateToEditProfile(
    BuildContext context,
    String userName,
    String userEmail,
  ) async {
    final updatedImage = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          initialName: userName,
          initialEmail: userEmail,
          initialProfileImage: _profileImageFile,
        ),
      ),
    );

    // Trigger rebuild to update profile name (and image if changed)
    if (mounted) {
      setState(() {
        if (updatedImage != null) {
          _profileImageFile = updatedImage;
        }
      });
    }
  }

  Future<void> _handleContactSupport(BuildContext context, bool isDark) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'support@docssaver.app',
      queryParameters: {'subject': 'DocsSaver Support & Feedback'},
    );
    try {
      final launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showSupportDialog(context, isDark);
      }
    } catch (_) {
      if (context.mounted) {
        _showSupportDialog(context, isDark);
      }
    }
  }

  void _showSupportDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? AppColors.darkCardBackground
              : AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Contact Support',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You can reach out to our team at:',
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'support@docssaver.app',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyDetails(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? AppColors.darkCardBackground
              : AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Privacy & Data Security',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your privacy and data security are built into the architecture:',
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• Tenant Isolation: Every memory belongs strictly to your user account via Supabase Row Level Security (RLS).\n\n'
                '• Local-First: Data is cached locally in an Isar embedded database on your device.\n\n'
                '• Transport Security: All network sync operations occur over encrypted TLS/HTTPS connections.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }


  void _showAboutSecondBrain(BuildContext context, bool isDark) {
    showAboutDialog(
      context: context,
      applicationName: 'DocsSaver',
      applicationVersion: 'v$_appVersion',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.lightCyanTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(
            Icons.psychology_rounded,
            color: isDark ? AppColors.periwinkle300 : AppColors.primary,
            size: 28,
          ),
        ),
      ),
      children: [
        Text(
          'DocsSaver is an AI-powered personal knowledge assistant designed to capture, organize, and retrieve your ideas, documents, audio recordings, and notes effortlessly.',
          style: TextStyle(
            fontSize: 13.5,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBackground : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x0DFFFFFF) : AppColors.subtleBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
    required bool isDark,
  }) {
    final effectiveTitleColor =
        titleColor ?? (isDark ? Colors.white : AppColors.textPrimary);
    final effectiveSubtitleColor =
        isDark ? Colors.white60 : AppColors.textSecondary;
    final effectiveIconColor =
        iconColor ?? (isDark ? AppColors.periwinkle300 : AppColors.primary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 24, color: effectiveIconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: effectiveTitleColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: effectiveSubtitleColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isDark ? Colors.white38 : AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider({required bool isDark}) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 0,
      color: isDark ? AppColors.darkSubtleBorder : AppColors.subtleBorder,
    );
  }

  String _getThemeShortDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemePickerModal(BuildContext context, ThemeMode currentMode, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCardBackground : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, state) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSubtleBorder : AppColors.subtleBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Select Theme',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildThemeSelector(context, state, isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeMode currentMode,
    bool isDark,
  ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkToggleBackground
            : AppColors.violetTwilight50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkSubtleBorder
              : AppColors.violetTwilight100,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildThemeSegment(
              context: context,
              key: const Key('theme_segment_light'),
              title: 'Light',
              icon: Icons.light_mode_outlined,
              mode: ThemeMode.light,
              isSelected: currentMode == ThemeMode.light,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildThemeSegment(
              context: context,
              key: const Key('theme_segment_dark'),
              title: 'Dark',
              icon: Icons.dark_mode_outlined,
              mode: ThemeMode.dark,
              isSelected: currentMode == ThemeMode.dark,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildThemeSegment(
              context: context,
              key: const Key('theme_segment_system'),
              title: 'System',
              icon: Icons.settings_brightness_outlined,
              mode: ThemeMode.system,
              isSelected: currentMode == ThemeMode.system,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegment({
    required BuildContext context,
    Key? key,
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required bool isSelected,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: () async {
          try {
            context.read<ThemeCubit>().setThemeMode(mode);
            await Future.delayed(const Duration(milliseconds: 250));
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          } catch (_) {}
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected
                      ? AppColors.textWhite
                      : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.violetTwilight700),
                ),
                const SizedBox(width: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.textWhite
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.violetTwilight700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: MediaQuery.of(context).viewPadding.top + 16,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C1412) : const Color(0xFF0F3E32),
        borderRadius: BorderRadius.zero,
      ),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeMode currentThemeMode = ThemeMode.system;
    try {
      currentThemeMode = context.watch<ThemeCubit>().state;
    } catch (_) {}

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0C1412) : const Color(0xFFFBFBF9);
    final userName = _getUserName(context);
    final userEmail = _getUserEmail(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: Column(
          children: [
            // 1. Pinned Header Container
            _buildHeader(context),

            Expanded(
              child: BlocBuilder<CaptureBloc, CaptureState>(
                builder: (context, captureState) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Grouped Settings Sections
                          // ACCOUNT DETAILS
                          _buildSectionHeader(title: 'Account Details', isDark: isDark),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.person_outline,
                                title: 'Account',
                                onTap: () => _navigateToEditProfile(context, userName, userEmail),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              BlocConsumer<GoogleAuthCubit, GoogleIntegrationStatus>(
                                bloc: _googleAuthCubit,
                                listener: (context, googleStatus) {
                                  if (googleStatus.errorMessage != null && googleStatus.errorMessage!.isNotEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(googleStatus.errorMessage!),
                                        backgroundColor: AppColors.errorText,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                },
                                builder: (context, googleStatus) {
                                  final isConnected = googleStatus.isConnected;
                                  final isConnecting = googleStatus.isConnecting;
                                  
                                  Widget trailingWidget;
                                  if (isConnecting) {
                                    trailingWidget = const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                                    );
                                  } else {
                                    trailingWidget = Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isConnected)
                                          Text(
                                            'Connected',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                                            ),
                                          ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 20,
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                        ),
                                      ],
                                    );
                                  }

                                  return _buildTile(
                                    icon: Icons.cloud_outlined,
                                    title: 'Cloud & Sync',
                                    trailing: trailingWidget,
                                    onTap: isConnecting ? null : (isConnected ? () => _confirmDisconnectGoogle(isDark) : () => _googleAuthCubit.connect()),
                                    isDark: isDark,
                                  );
                                },
                              ),
                            ],
                          ),

                          // GENERAL
                          _buildSectionHeader(title: 'General', isDark: isDark),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.notifications_none,
                                title: 'Notifications',
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'On',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                onTap: () {},
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.wb_sunny_outlined,
                                title: 'Theme / Mode',
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _getThemeShortDescription(currentThemeMode),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                onTap: () => _showThemePickerModal(context, currentThemeMode, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // SUPPORT & SECURITY
                          _buildSectionHeader(title: 'Support & Security', isDark: isDark),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.lock_outline,
                                title: 'Privacy & Data Protection',
                                onTap: () => _showPrivacyDetails(context, isDark),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.mail_outline,
                                title: 'Contact Support',
                                onTap: () => _handleContactSupport(context, isDark),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.info_outline,
                                title: 'About DocsSaver',
                                onTap: () => _showAboutSecondBrain(context, isDark),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.logout,
                                iconColor: const Color(0xFFEF4444),
                                title: 'Sign Out',
                                titleColor: const Color(0xFFEF4444),
                                onTap: () => _confirmSignOut(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
