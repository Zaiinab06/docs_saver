import '../../domain/entities/google_doc_entity.dart';
import '../../domain/entities/google_integration_status.dart';
import '../../domain/repositories/google_auth_repository.dart';
import '../datasources/google_auth_remote_data_source.dart';

class GoogleAuthRepositoryImpl implements GoogleAuthRepository {
  final GoogleAuthRemoteDataSource remoteDataSource;

  GoogleAuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<String> startOAuth() => remoteDataSource.startOAuth();

  @override
  Future<GoogleIntegrationStatus> getStatus() => remoteDataSource.getStatus();

  @override
  Future<void> disconnect() => remoteDataSource.disconnect();

  @override
  Future<GoogleDocEntity> importDoc(String fileId) =>
      remoteDataSource.importDoc(fileId);

  @override
  Future<String> startGooglePicker() => remoteDataSource.startGooglePicker();

  @override
  Future<GoogleDocEntity> importDriveFile(String fileId) =>
      remoteDataSource.importDriveFile(fileId);
}
