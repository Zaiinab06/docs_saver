import 'package:supabase_flutter/supabase_flutter.dart' show User;
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  UserEntity _toEntity(User user) {
    final meta = user.userMetadata;
    String? fullName;
    if (meta != null) {
      if (meta['full_name'] is String &&
          (meta['full_name'] as String).trim().isNotEmpty) {
        fullName = (meta['full_name'] as String).trim();
      } else if (meta['name'] is String &&
          (meta['name'] as String).trim().isNotEmpty) {
        fullName = (meta['name'] as String).trim();
      }
    }
    return UserEntity(
      id: user.id,
      email: user.email,
      fullName: fullName,
    );
  }

  @override
  Future<UserEntity> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final user = await remoteDataSource.signUp(
      email: email,
      password: password,
      fullName: fullName,
    );
    return _toEntity(user);
  }

  @override
  Future<UserEntity> signIn({
    required String email,
    required String password,
  }) async {
    final user = await remoteDataSource.signIn(
      email: email,
      password: password,
    );
    return _toEntity(user);
  }

  @override
  Future<void> signOut() async {
    await remoteDataSource.signOut();
  }

  @override
  UserEntity? getCurrentUser() {
    final user = remoteDataSource.getCurrentUser();
    if (user == null) return null;
    return _toEntity(user);
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return remoteDataSource.onAuthStateChange.map((authState) {
      final user = authState.session?.user;
      if (user == null) return null;
      return _toEntity(user);
    });
  }
}
