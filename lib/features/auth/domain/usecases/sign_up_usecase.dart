import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class SignUpUseCase {
  final AuthRepository repository;

  SignUpUseCase(this.repository);

  Future<UserEntity> call({
    required String email,
    required String password,
  }) async {
    return await repository.signUp(email: email, password: password);
  }
}
