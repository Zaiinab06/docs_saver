import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<UserEntity> signUp({
    required String email,
    required String password,
  }) async {
    final user = await remoteDataSource.signUp(
      email: email,
      password: password,
    );
    return UserEntity(id: user.id, email: user.email);
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
    return UserEntity(id: user.id, email: user.email);
  }

  @override
  Future<void> signOut() async {
    await remoteDataSource.signOut();
  }

  @override
  UserEntity? getCurrentUser() {
    final user = remoteDataSource.getCurrentUser();
    if (user == null) return null;
    return UserEntity(id: user.id, email: user.email);
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return remoteDataSource.onAuthStateChange.map((authState) {
      final user = authState.session?.user;
      if (user == null) return null;
      return UserEntity(id: user.id, email: user.email);
    });
  }
}
