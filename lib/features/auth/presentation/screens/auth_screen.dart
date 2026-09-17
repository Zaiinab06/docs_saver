// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

enum AuthMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  final AuthMode initialMode;

  const AuthScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _currentMode;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode newMode) {
    if (_currentMode != newMode) {
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
      _formKey.currentState?.reset();
      setState(() {
        _currentMode = newMode;
      });
    }
  }

  void _onSubmit() {
    print('DEBUG: Sign Up button clicked');
    final isValid = _formKey.currentState?.validate() ?? false;
    print('DEBUG: Form validated: $isValid');

    if (!isValid) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: AppColors.errorBorder.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          backgroundColor: AppColors.snackBarBackground,
          content: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppColors.errorBorder,
                size: 20,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Please fill in all required fields properly.',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (_currentMode == AuthMode.signIn) {
      context.read<AuthBloc>().add(
            SignInRequested(
              email: email,
              password: password,
            ),
          );
    } else {
      print('DEBUG: Dispatching SignUpEvent with email: ${_emailController.text}');
      final fullName = _nameController.text.trim();
      context.read<AuthBloc>().add(
            SignUpRequested(
              email: email,
              password: password,
              fullName: fullName.isNotEmpty ? fullName : null,
            ),
          );
    }
  }

  String _formatErrorMessage(String message) {
    if (message.toLowerCase().contains('email not confirmed')) {
      return 'Email not confirmed. Please check your inbox and verify your email before signing in.';
    }
    final regex = RegExp(r'AuthException\s*\(\s*message:\s*([^,)]+)');
    final match = regex.firstMatch(message);
    if (match != null && match.group(1) != null) {
      final msg = match.group(1)!.trim();
      if (msg.toLowerCase().contains('email not confirmed')) {
        return 'Email not confirmed. Please check your inbox and verify your email before signing in.';
      }
      return msg;
    }
    if (message.startsWith('Exception: ')) {
      return message.replaceFirst('Exception: ', '').trim();
    }
    return message;
  }

  String? _validateName(String? value) {
    if (_currentMode == AuthMode.signUp &&
        (value == null || value.trim().isEmpty)) {
      return AppStrings.validationEmptyName;
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppStrings.validationEmptyEmail;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
      return AppStrings.validationInvalidEmail;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationEmptyPassword;
    }
    if (_currentMode == AuthMode.signUp && value.length < 6) {
      return AppStrings.validationShortPassword;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthFailure) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                backgroundColor: AppColors.snackBarBackground,
                content: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _formatErrorMessage(state.errorMessage),
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (state is AuthNeedsConfirmation) {
            _passwordController.clear();
            _emailController.text = state.email;
            _switchMode(AuthMode.signIn);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                backgroundColor: AppColors.snackBarBackground,
                content: Row(
                  children: [
                    const Icon(
                      Icons.mark_email_read_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.message ??
                            'Verification email sent to ${state.email}. Please verify before signing in.',
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (state is Authenticated ||
              (state is AuthSuccess && state.user.hasSession)) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Section: Logo & Branding
                      Center(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppColors.lightCyanTint,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.psychology_rounded,
                              size: 36,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Title
                      const Text(
                        AppStrings.authWelcomeTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Subtitle
                      const Text(
                        AppStrings.authWelcomeSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 32),

                      if (state is AuthNeedsConfirmation) ...[
                        _buildEmailConfirmationCard(state.email, state.message),
                        const SizedBox(height: 24),
                      ],

                      // Sliding Pill Segment / Toggle
                      Container(
                        height: 48,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.toggleBackground,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final tabWidth = (constraints.maxWidth) / 2;
                            return Stack(
                              children: [
                                // Sliding pill indicator
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  alignment: _currentMode == AuthMode.signIn
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: Container(
                                    width: tabWidth,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBackground,
                                      borderRadius: BorderRadius.circular(100),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.08),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Segment Labels
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _switchMode(AuthMode.signIn),
                                        child: Center(
                                          child: AnimatedDefaultTextStyle(
                                            duration:
                                                const Duration(milliseconds: 200),
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight:
                                                  _currentMode == AuthMode.signIn
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                              color:
                                                  _currentMode == AuthMode.signIn
                                                      ? AppColors.primary
                                                      : AppColors.textSecondary,
                                            ),
                                            child:
                                                const Text(AppStrings.signInTab),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _switchMode(AuthMode.signUp),
                                        child: Center(
                                          child: AnimatedDefaultTextStyle(
                                            duration:
                                                const Duration(milliseconds: 200),
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight:
                                                  _currentMode == AuthMode.signUp
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                              color:
                                                  _currentMode == AuthMode.signUp
                                                      ? AppColors.primary
                                                      : AppColors.textSecondary,
                                            ),
                                            child:
                                                const Text(AppStrings.signUpTab),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Form Fields Card Container
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name Field (Visible only in Sign Up mode)
                            AnimatedCrossFade(
                              firstChild: Column(
                                children: [
                                  _buildTextField(
                                    controller: _nameController,
                                    label: AppStrings.nameLabel,
                                    hintText: AppStrings.nameHint,
                                    icon: Icons.person_outline_rounded,
                                    validator: _validateName,
                                  ),
                                  const SizedBox(height: 18),
                                ],
                              ),
                              secondChild: const SizedBox.shrink(),
                              crossFadeState: _currentMode == AuthMode.signUp
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: const Duration(milliseconds: 250),
                            ),

                            // Email Field
                            _buildTextField(
                              controller: _emailController,
                              label: AppStrings.emailLabel,
                              hintText: AppStrings.emailHint,
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: _validateEmail,
                            ),

                            const SizedBox(height: 18),

                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              label: AppStrings.passwordLabel,
                              hintText: _currentMode == AuthMode.signUp
                                  ? AppStrings.passwordHintSignUp
                                  : AppStrings.passwordHintSignIn,
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              validator: _validatePassword,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Primary Action Button: Full Pill with Primary Gradient
                      Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isLoading ? null : _onSubmit,
                            borderRadius: BorderRadius.circular(100),
                            child: Center(
                              child: isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child:
                                          CircularProgressIndicator.adaptive(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                AppColors.textWhite),
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : Text(
                                      _currentMode == AuthMode.signIn
                                          ? AppStrings.signInButton
                                          : AppStrings.signUpButton,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textWhite,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Footer Navigation Toggle
                      Center(
                        child: TextButton(
                          onPressed: () {
                            _switchMode(
                              _currentMode == AuthMode.signIn
                                  ? AuthMode.signUp
                                  : AuthMode.signIn,
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              children: [
                                TextSpan(
                                  text: _currentMode == AuthMode.signIn
                                      ? AppStrings.dontHaveAccount
                                      : AppStrings.alreadyHaveAccount,
                                ),
                                TextSpan(
                                  text: _currentMode == AuthMode.signIn
                                      ? AppStrings.signUpTab
                                      : AppStrings.signInTab,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          cursorColor: AppColors.primary,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill,
            hintText: hintText,
            hintStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: AppColors.textSecondary,
            ),
            suffixIcon: suffixIcon,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.border, width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.border, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.focusedBorder, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.errorBorder, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.errorBorder, width: 1.2),
            ),
            errorStyle: const TextStyle(
              color: AppColors.errorText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildEmailConfirmationCard(String email, String? message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lightCyanTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.categoryChipBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Check your email',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message ??
                          'We sent a verification link to $email. Please click the link to activate your account.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                context.read<AuthBloc>().add(
                      ResendVerificationEmailRequested(email: email),
                    );
              },
              icon: const Icon(
                Icons.refresh_rounded,
                size: 14,
                color: AppColors.primaryDark,
              ),
              label: const Text(
                'Resend verification email',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
