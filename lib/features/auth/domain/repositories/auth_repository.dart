import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserEntity> signUp({
    required String email,
    required String password,
    String? fullName,
  });

  Future<UserEntity> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> resendVerificationEmail({required String email});

  UserEntity? getCurrentUser();

  Stream<UserEntity?> get authStateChanges;
}
