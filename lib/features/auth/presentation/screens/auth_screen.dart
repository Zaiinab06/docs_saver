// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

enum AuthMode { signIn, signUp }

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF134E3F);
const _kBorder = Color(0xFFE2E8F0);
const _kLabelColor = Color(0xFF2D3748);
const _kSubtextColor = Color(0xFF718096);
const _kInputFill = Color(0xFFF7FAFC);

// ─────────────────────────────────────────────────────────────────────────────
// AuthScreen
// ─────────────────────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  final AuthMode initialMode;
  const AuthScreen({super.key, this.initialMode = AuthMode.signIn});

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
  bool _rememberMe = false;

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

  // ── Mode switching ──────────────────────────────────────────────────────────
  void _switchMode(AuthMode newMode) {
    if (_currentMode != newMode) {
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
      _formKey.currentState?.reset();
      setState(() => _currentMode = newMode);
    }
  }

  // ── Form submission ─────────────────────────────────────────────────────────
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
              Icon(Icons.error_outline_rounded,
                  color: AppColors.errorBorder, size: 20),
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
            SignInRequested(email: email, password: password),
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

  // ── Error formatting ────────────────────────────────────────────────────────
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

  // ── Validators ──────────────────────────────────────────────────────────────
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

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.primary, size: 20),
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
                    const Icon(Icons.mark_email_read_rounded,
                        color: AppColors.primary, size: 20),
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
          final isSignIn = _currentMode == AuthMode.signIn;

          return SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Top spacing ──────────────────────────────────────────
                    const SizedBox(height: 16),

                    // ── Title ───────────────────────────────────────────────
                    Text(
                      isSignIn ? 'Welcome Back' : 'Create Account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _kLabelColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Subtitle ────────────────────────────────────────────
                    Text(
                      isSignIn
                          ? 'Log in to your account to continue.'
                          : 'Sign up to get started with your dashboard.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _kSubtextColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Email-confirmation card ──────────────────────────────
                    if (state is AuthNeedsConfirmation) ...[
                      _buildEmailConfirmationCard(
                          state.email, state.message),
                      const SizedBox(height: 24),
                    ],

                    // ── Full Name (sign-up only) ─────────────────────────────
                    AnimatedCrossFade(
                      firstChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('Full Name'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _nameController,
                            hintText: 'Enter your name',
                            prefixIcon: Icons.person_outline_rounded,
                            validator: _validateName,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                      secondChild: const SizedBox.shrink(),
                      crossFadeState: isSignIn
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 250),
                    ),

                    // ── Email ───────────────────────────────────────────────
                    _buildFieldLabel('Email'),
                    const SizedBox(height: 6),
                    _buildTextField(
                      controller: _emailController,
                      hintText: 'Enter your email',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 20),

                    // ── Password ────────────────────────────────────────────
                    _buildFieldLabel('Password'),
                    const SizedBox(height: 6),
                    _buildTextField(
                      controller: _passwordController,
                      hintText: isSignIn
                          ? AppStrings.passwordHintSignIn
                          : AppStrings.passwordHintSignUp,
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _kSubtextColor,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),

                    // ── Remember me / Forgot password (sign-in only) ────────
                    if (isSignIn)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _rememberMe,
                                  activeColor: _kPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  side: const BorderSide(
                                      color: _kSubtextColor, width: 1.5),
                                  onChanged: (v) =>
                                      setState(() => _rememberMe = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Remember me',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _kLabelColor,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              // TODO: wire forgot-password flow
                            },
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: 13,
                                color: _kPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 28),

                    // ── Primary action button ───────────────────────────────
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          disabledBackgroundColor:
                              _kPrimary.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Text(
                                isSignIn
                                    ? AppStrings.signInButton
                                    : AppStrings.signUpButton,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Footer navigation ───────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () => _switchMode(
                          isSignIn ? AuthMode.signUp : AuthMode.signIn,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: _kSubtextColor,
                            ),
                            children: [
                              TextSpan(
                                text: isSignIn
                                    ? AppStrings.dontHaveAccount
                                    : AppStrings.alreadyHaveAccount,
                              ),
                              TextSpan(
                                text: isSignIn
                                    ? AppStrings.signUpTab
                                    : AppStrings.signInTab,
                                style: const TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w700,
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
          );
        },
      ),
    );
  }

  // ── Field label ─────────────────────────────────────────────────────────────
  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _kLabelColor,
      ),
    );
  }

  // ── Text field ──────────────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      cursorColor: _kPrimary,
      style: const TextStyle(
        fontSize: 14,
        color: _kLabelColor,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _kInputFill,
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: _kSubtextColor,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(prefixIcon, size: 20, color: _kSubtextColor),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.errorBorder,
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.errorBorder,
            width: 1.2,
          ),
        ),
        errorStyle: const TextStyle(
          color: AppColors.errorText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      validator: validator,
    );
  }

  // ── Email confirmation card ──────────────────────────────────────────────────
  Widget _buildEmailConfirmationCard(String email, String? message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F0EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kPrimary.withValues(alpha: 0.25),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _kPrimary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(Icons.mark_email_read_rounded,
                    color: _kPrimary, size: 20),
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
                        color: _kLabelColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message ??
                          'We sent a verification link to $email. Please click the link to activate your account.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kSubtextColor,
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
              icon: const Icon(Icons.refresh_rounded,
                  size: 14, color: _kPrimary),
              label: const Text(
                'Resend verification email',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
