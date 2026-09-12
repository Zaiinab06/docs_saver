import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRemoteDataSource {
  Future<User> signUp({
    required String email,
    required String password,
    String? fullName,
  });

  Future<User> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

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
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: (fullName != null && fullName.trim().isNotEmpty)
          ? {'full_name': fullName.trim()}
          : null,
    );
    if (response.user == null) {
      throw const AuthException('Sign up failed: User is null');
    }
    return response.user!;
  }

  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
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
  User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  @override
  Stream<AuthState> get onAuthStateChange {
    return supabase.auth.onAuthStateChange;
  }
}
