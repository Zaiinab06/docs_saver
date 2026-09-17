import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../capture/presentation/bloc/capture_bloc.dart';
import '../../../capture/presentation/bloc/capture_event.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Sign Out',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          content: const Text(
            'Are you sure you want to sign out of Second Brain?',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.errorText,
              ),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.subtleBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
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
  }) {
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? AppColors.primary,
                ),
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
                        color: titleColor ?? AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 66,
      endIndent: 16,
      color: AppColors.subtleBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = _getUserName(context);
    final userEmail = _getUserEmail(context);
    final userInitial = _getUserInitial(userName);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.cardBackground,
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: AppColors.subtleBorder,
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
          physics: const BouncingScrollPhysics(),
          children: [
            // 1. Account Section
            _buildSectionHeader('ACCOUNT'),
            _buildCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.lightCyanTint,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.categoryChipBorder,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            userInitial,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              userEmail,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.errorText,
                  title: 'Sign Out',
                  titleColor: AppColors.errorText,
                  subtitle: 'Sign out of your Second Brain account',
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),

            // 2. Appearance Section
            _buildSectionHeader('APPEARANCE'),
            _buildCard(
              children: [
                _buildTile(
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'Light Mode (Default)',
                  trailing: const Text(
                    'Light',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            // 3. Notifications Section
            _buildSectionHeader('NOTIFICATIONS'),
            _buildCard(
              children: [
                _buildTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Push Notifications',
                  subtitle: 'Memory reminders and suggestions',
                  trailing: const Text(
                    'Enabled',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            // 4. Data & Storage Section
            _buildSectionHeader('DATA & STORAGE'),
            _buildCard(
              children: [
                _buildTile(
                  icon: Icons.cloud_sync_outlined,
                  title: 'Sync Offline Memories',
                  subtitle: 'Synchronize local cache with Supabase cloud',
                  onTap: () {
                    context.read<CaptureBloc>().add(SyncPendingMemoriesEvent());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Syncing memories with cloud...'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.storage_rounded,
                  title: 'Local Database',
                  subtitle: 'Isar Embedded Database Storage',
                  trailing: const Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            // 5. About Section
            _buildSectionHeader('ABOUT'),
            _buildCard(
              children: [
                _buildTile(
                  icon: Icons.psychology_rounded,
                  title: 'Second Brain',
                  subtitle: 'v1.0.0 • AI-powered personal knowledge assistant',
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.security_rounded,
                  title: 'Privacy & Security',
                  subtitle: 'Your memories are encrypted and tenant-isolated',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
