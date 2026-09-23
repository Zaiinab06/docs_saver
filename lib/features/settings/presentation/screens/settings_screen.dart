import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:url_launcher/url_launcher.dart';
// ignore: depend_on_referenced_packages
import 'package:app_links/app_links.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../capture/domain/entities/memory_entity.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';
import '../../../capture/presentation/bloc/capture_state.dart';
import '../../../integrations/data/datasources/google_auth_remote_data_source.dart';
import '../../../integrations/data/repositories/google_auth_repository_impl.dart';
import '../../../integrations/domain/entities/google_integration_status.dart';
import '../../../integrations/presentation/cubit/google_auth_cubit.dart';

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
    return 'Second Brain User';
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
    return 'user@secondbrain.app';
  }

  String _getUserInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'second brain user') {
      return 'U';
    }
    return trimmed[0].toUpperCase();
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
            'Are you sure you want to sign out of Second Brain?',
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

  void _showAccountDetails(
    BuildContext context,
    String userName,
    String userEmail,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark
          ? AppColors.darkCardBackground
          : AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSubtleBorder
                          : AppColors.chipInactiveBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Account Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Name', userName, isDark),
                const SizedBox(height: 12),
                _buildInfoRow('Email', userEmail, isDark),
                const SizedBox(height: 12),
                _buildInfoRow('Authentication', 'Supabase Auth', isDark),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? AppColors.periwinkle300
                          : AppColors.primary,
                      side: BorderSide(
                        color: isDark
                            ? AppColors.periwinkle300
                            : AppColors.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _handleContactSupport(BuildContext context, bool isDark) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'support@secondbrain.app',
      queryParameters: {'subject': 'Second Brain Support & Feedback'},
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
                'support@secondbrain.app',
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

  void _showAiDetails(BuildContext context, bool isDark) {
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
                Icons.auto_awesome_rounded,
                color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'AI Knowledge Engine',
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
                'Second Brain uses Google Gemini to automatically understand and organize your memories:',
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
                '• Multi-modal OCR for images & document scans\n'
                '• Accurate speech-to-text audio transcription\n'
                '• Smart 8-category classification & semantic tags\n'
                '• Living Memory entity extraction\n'
                '• 768-dimensional pgvector semantic search',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Got It',
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
      applicationName: 'Second Brain',
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
          'Second Brain is an AI-powered personal knowledge assistant designed to capture, organize, and retrieve your ideas, documents, audio recordings, and notes effortlessly.',
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
    required IconData icon,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSubtleBorder
                  : AppColors.violetTwilight100.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 15,
              color: isDark ? AppColors.periwinkle300 : AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBackground : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkSubtleBorder : AppColors.subtleBorder,
          width: 1.2,
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
        titleColor ??
        (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary);
    final effectiveSubtitleColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final effectiveIconColor =
        iconColor ?? (isDark ? AppColors.periwinkle300 : AppColors.primary);
    final iconBgColor = iconColor != null
        ? iconColor.withValues(alpha: 0.1)
        : (isDark
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.primary.withValues(alpha: 0.1));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: effectiveIconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: effectiveTitleColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: effectiveSubtitleColor,
                          height: 1.3,
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
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
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
      indent: 68,
      endIndent: 16,
      color: isDark ? AppColors.darkSubtleBorder : AppColors.subtleBorder,
    );
  }

  String _getThemeDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light mode active';
      case ThemeMode.dark:
        return 'Dark mode active';
      case ThemeMode.system:
        return 'Following device system theme';
    }
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
        onTap: () {
          try {
            context.read<ThemeCubit>().setThemeMode(mode);
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

  Widget _buildHeader(
    BuildContext context,
    String userName,
    String userInitial,
    bool isDark,
  ) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Header gradient background
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 56),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textWhite,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your Second Brain',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textWhite.withValues(alpha: 0.88),
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
        // Overlapping avatar at bottom edge of header
        Positioned(
          bottom: -40,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCardBackground
                  : AppColors.cardBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.white,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                userInitial,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.periwinkle300 : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeMode currentThemeMode = ThemeMode.system;
    try {
      currentThemeMode = context.watch<ThemeCubit>().state;
    } catch (_) {}

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final userName = _getUserName(context);
    final userEmail = _getUserEmail(context);
    final userInitial = _getUserInitial(userName);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: SafeArea(
          top: false,
          bottom: true,
          child: BlocBuilder<CaptureBloc, CaptureState>(
            builder: (context, captureState) {
              final List<MemoryEntity> memories = captureState is CaptureLoaded
                  ? captureState.memories
                  : const <MemoryEntity>[];
              final pendingCount = memories.where((m) => !m.isSynced).length;
              final totalCount = memories.length;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // 1. Header with Overlapping Avatar
                    _buildHeader(context, userName, userInitial, isDark),

                    const SizedBox(
                      height: 52,
                    ), // Clearance for overlapping avatar
                    // Centered Real Authenticated User Name and Email
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            userName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Content Sections
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Account Section Card
                          _buildSectionHeader(
                            title: 'ACCOUNT',
                            icon: Icons.person_outline_rounded,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.person_outline_rounded,
                                title: 'Profile',
                                subtitle: 'View account details',
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.textSecondary,
                                ),
                                onTap: () => _showAccountDetails(
                                  context,
                                  userName,
                                  userEmail,
                                  isDark,
                                ),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.mail_outline_rounded,
                                title: 'Email',
                                subtitle: userEmail,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.primary.withValues(
                                            alpha: 0.25,
                                          )
                                        : AppColors.lightCyanTint,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppColors.periwinkle300
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                                onTap: () => _showAccountDetails(
                                  context,
                                  userName,
                                  userEmail,
                                  isDark,
                                ),
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.logout_rounded,
                                iconColor: AppColors.errorText,
                                title: 'Sign Out',
                                titleColor: AppColors.errorText,
                                subtitle:
                                    'Sign out of your Second Brain account',
                                onTap: () => _confirmSignOut(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 2. Connected Accounts Section
                          _buildSectionHeader(
                            title: 'CONNECTED ACCOUNTS',
                            icon: Icons.link_rounded,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              BlocConsumer<
                                GoogleAuthCubit,
                                GoogleIntegrationStatus
                              >(
                                bloc: _googleAuthCubit,
                                listener: (context, googleStatus) {
                                  if (googleStatus.errorMessage != null &&
                                      googleStatus.errorMessage!.isNotEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          googleStatus.errorMessage!,
                                        ),
                                        backgroundColor: AppColors.errorText,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                },
                                builder: (context, googleStatus) {
                                  final isConnected = googleStatus.isConnected;
                                  final isConnecting =
                                      googleStatus.isConnecting;
                                  final email = googleStatus.email;

                                  String subtitle;
                                  if (isConnecting) {
                                    subtitle =
                                        'Opening Google sign-in in system browser...';
                                  } else if (isConnected) {
                                    subtitle = email != null && email.isNotEmpty
                                        ? 'Connected as $email'
                                        : 'Connected to Google Drive';
                                  } else if (googleStatus.state ==
                                      GoogleConnectionState.cancelled) {
                                    subtitle =
                                        'Connection was cancelled. Tap to retry.';
                                  } else if (googleStatus.state ==
                                      GoogleConnectionState.connectionFailed) {
                                    subtitle =
                                        'Connection failed. Tap to retry.';
                                  } else {
                                    subtitle =
                                        'Connect your Google account for Docs import';
                                  }

                                  Widget trailingWidget;
                                  if (isConnecting) {
                                    trailingWidget = const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primary,
                                            ),
                                      ),
                                    );
                                  } else if (isConnected) {
                                    trailingWidget = Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.primary.withValues(
                                                    alpha: 0.25,
                                                  )
                                                : AppColors.lightCyanTint,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'Connected',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? AppColors.periwinkle300
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.link_off_rounded,
                                            size: 20,
                                          ),
                                          color: AppColors.errorText,
                                          tooltip: 'Disconnect Google Account',
                                          onPressed: () =>
                                              _confirmDisconnectGoogle(isDark),
                                        ),
                                      ],
                                    );
                                  } else {
                                    trailingWidget = Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? AppColors.primary.withValues(
                                                alpha: 0.25,
                                              )
                                            : AppColors.lightCyanTint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.login_rounded,
                                            size: 14,
                                            color: isDark
                                                ? AppColors.periwinkle300
                                                : AppColors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Connect',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? AppColors.periwinkle300
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return _buildTile(
                                    icon: Icons.account_circle_outlined,
                                    title: 'Google Drive',
                                    subtitle: subtitle,
                                    trailing: trailingWidget,
                                    onTap: isConnecting
                                        ? null
                                        : (isConnected
                                              ? () => _confirmDisconnectGoogle(
                                                  isDark,
                                                )
                                              : () =>
                                                    _googleAuthCubit.connect()),
                                    isDark: isDark,
                                  );
                                },
                              ),
                            ],
                          ),

                          // 3. Appearance Section
                          _buildSectionHeader(
                            title: 'APPEARANCE',
                            icon: Icons.palette_outlined,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.primary.withValues(
                                                    alpha: 0.2,
                                                  )
                                                : AppColors.primary.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.palette_outlined,
                                            size: 20,
                                            color: isDark
                                                ? AppColors.periwinkle300
                                                : AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Theme',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? AppColors
                                                            .darkTextPrimary
                                                      : AppColors.textPrimary,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _getThemeDescription(
                                                  currentThemeMode,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: isDark
                                                      ? AppColors
                                                            .darkTextSecondary
                                                      : AppColors.textSecondary,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _buildThemeSelector(
                                      context,
                                      currentThemeMode,
                                      isDark,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // 3. Notifications Section
                          _buildSectionHeader(
                            title: 'NOTIFICATIONS',
                            icon: Icons.notifications_none_rounded,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.notifications_none_rounded,
                                title: 'Push Notifications',
                                subtitle: 'Memory reminders and suggestions',
                                trailing: Text(
                                  'Enabled',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.periwinkle300
                                        : AppColors.primary,
                                  ),
                                ),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 4. Data & Storage Section
                          _buildSectionHeader(
                            title: 'DATA & STORAGE',
                            icon: Icons.cloud_sync_outlined,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.cloud_sync_outlined,
                                title: 'Sync Offline Memories',
                                subtitle: pendingCount > 0
                                    ? '$pendingCount memories waiting to sync'
                                    : 'Synchronize local cache with Supabase cloud',
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.primary.withValues(
                                            alpha: 0.25,
                                          )
                                        : AppColors.lightCyanTint,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.sync_rounded,
                                        size: 14,
                                        color: isDark
                                            ? AppColors.periwinkle300
                                            : AppColors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Sync Now',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? AppColors.periwinkle300
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () {
                                  context.read<CaptureBloc>().add(
                                    SyncPendingMemoriesEvent(),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Syncing memories with cloud...',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                isDark: isDark,
                              ),
                              _buildDivider(isDark: isDark),
                              _buildTile(
                                icon: Icons.storage_rounded,
                                title: 'Local Database',
                                subtitle:
                                    'Isar Embedded Database • $totalCount saved',
                                trailing: Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.periwinkle300
                                        : AppColors.primary,
                                  ),
                                ),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 5. AI & Knowledge Engine Section
                          _buildSectionHeader(
                            title: 'AI & KNOWLEDGE ENGINE',
                            icon: Icons.auto_awesome_outlined,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.psychology_outlined,
                                title: 'AI Knowledge Engine',
                                subtitle:
                                    'Google Gemini • OCR, Audio & Semantic Search',
                                trailing: Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.periwinkle300
                                        : AppColors.primary,
                                  ),
                                ),
                                onTap: () => _showAiDetails(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 6. Help & Support Section
                          _buildSectionHeader(
                            title: 'HELP & SUPPORT',
                            icon: Icons.help_outline_rounded,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.mail_outline_rounded,
                                title: 'Contact Support',
                                subtitle:
                                    'Reach out to support@secondbrain.app',
                                onTap: () =>
                                    _handleContactSupport(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 7. Privacy & Security Section
                          _buildSectionHeader(
                            title: 'PRIVACY & SECURITY',
                            icon: Icons.shield_outlined,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.lock_outline_rounded,
                                title: 'Privacy & Data Protection',
                                subtitle:
                                    'Your memories are encrypted and tenant-isolated',
                                onTap: () =>
                                    _showPrivacyDetails(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          // 8. About Section
                          _buildSectionHeader(
                            title: 'ABOUT',
                            icon: Icons.info_outline_rounded,
                            isDark: isDark,
                          ),
                          _buildCard(
                            isDark: isDark,
                            children: [
                              _buildTile(
                                icon: Icons.psychology_rounded,
                                title: 'Second Brain',
                                subtitle:
                                    'v$_appVersion • AI-powered personal knowledge assistant',
                                onTap: () =>
                                    _showAboutSecondBrain(context, isDark),
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
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
}
