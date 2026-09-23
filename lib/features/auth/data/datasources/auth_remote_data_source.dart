// ignore_for_file: avoid_print
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRemoteDataSource {
  Future<User> signUp({
    required String email,
    required String password,
    String? fullName,
  });

  Future<User> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> resendVerificationEmail({required String email});

  User? getCurrentUser();

  Stream<AuthState> get onAuthStateChange;
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient supabase;

  AuthRemoteDataSourceImpl({SupabaseClient? supabaseClient})
    : supabase = supabaseClient ?? Supabase.instance.client;

  @override
  Future<User> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      print(
        'DEBUG: Calling supabase.auth.signUp with email: $email, fullName: $fullName',
      );
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: (fullName != null && fullName.trim().isNotEmpty)
            ? {'full_name': fullName.trim()}
            : null,
      );
      print(
        'DEBUG: Supabase signUp response: user=${response.user?.id}, session=${response.session != null}',
      );

      if (response.user == null) {
        print('DEBUG: Supabase signUp failed: User is null in response');
        throw const AuthException('Sign up failed: User is null');
      }

      if (response.session == null) {
        try {
          final signInRes = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
          if (signInRes.user != null) {
            return signInRes.user!;
          }
        } catch (_) {
          // If email confirmation is required, response.user is still valid
        }
      }

      return response.user!;
    } on AuthException catch (e, stack) {
      print(
        'DEBUG: AuthException in supabase.auth.signUp: ${e.message} (status: ${e.statusCode})',
      );
      print('DEBUG: Stack trace: $stack');
      rethrow;
    } catch (e, stack) {
      print('DEBUG: Generic Exception in supabase.auth.signUp: $e');
      print('DEBUG: Stack trace: $stack');
      rethrow;
    }
  }

  @override
  Future<User> signIn({required String email, required String password}) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('Sign in failed: User is null');
    }
    return response.user!;
  }

  @override
  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  @override
  Future<void> resendVerificationEmail({required String email}) async {
    await supabase.auth.resend(type: OtpType.signup, email: email);
  }

  @override
  User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  @override
  Stream<AuthState> get onAuthStateChange {
    return supabase.auth.onAuthStateChange;
  }
}
