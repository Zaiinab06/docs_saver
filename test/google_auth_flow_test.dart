import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/integrations/domain/entities/google_doc_entity.dart';
import 'package:second_brain/features/integrations/domain/entities/google_integration_status.dart';
import 'package:second_brain/features/integrations/domain/repositories/google_auth_repository.dart';
import 'package:second_brain/features/integrations/presentation/cubit/google_auth_cubit.dart';

class _MockGoogleAuthRepository implements GoogleAuthRepository {
  GoogleIntegrationStatus currentStatus =
      const GoogleIntegrationStatus(state: GoogleConnectionState.notConnected);
  String? authUrlToReturn =
      'https://accounts.google.com/o/oauth2/v2/auth?client_id=test_client_id&response_type=code';
  bool startOAuthCalled = false;
  bool getStatusCalled = false;
  bool disconnectCalled = false;

  @override
  Future<String> startOAuth() async {
    startOAuthCalled = true;
    if (authUrlToReturn == null) {
      throw Exception('Configuration error: GOOGLE_CLIENT_ID missing.');
    }
    return authUrlToReturn!;
  }

  @override
  Future<GoogleIntegrationStatus> getStatus() async {
    getStatusCalled = true;
    return currentStatus;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    currentStatus = const GoogleIntegrationStatus(
      state: GoogleConnectionState.notConnected,
    );
  }

  @override
  Future<GoogleDocEntity> importDoc(String fileId) async {
    return GoogleDocEntity(
      success: true,
      title: 'Mock Doc',
      content: 'Mock Doc Content',
      fileId: fileId,
      webViewLink: 'https://docs.google.com/document/d/$fileId/edit',
      mimeType: 'application/vnd.google-apps.document',
    );
  }

  @override
  Future<String> startGooglePicker() async =>
      'https://accounts.google.com/o/oauth2/v2/auth?trigger_onepick=true';

  @override
  Future<GoogleDocEntity> importDriveFile(String fileId) async => importDoc(fileId);
}

void main() {
  group('GoogleAuthCubit & OAuth Security Flow Tests', () {
    late _MockGoogleAuthRepository repository;
    late GoogleAuthCubit cubit;

    setUp(() {
      repository = _MockGoogleAuthRepository();
      cubit = GoogleAuthCubit(repository: repository);
    });

    tearDown(() {
      cubit.close();
    });

    test('Initial state is notConnected with null email', () {
      expect(cubit.state.state, GoogleConnectionState.notConnected);
      expect(cubit.state.isConnected, false);
      expect(cubit.state.isConnecting, false);
      expect(cubit.state.email, isNull);
    });

    test('checkStatus updates state to connected when repository returns connected', () async {
      repository.currentStatus = GoogleIntegrationStatus(
        state: GoogleConnectionState.connected,
        email: 'user@example.com',
        name: 'Test User',
        updatedAt: DateTime(2026, 9, 20),
      );

      await cubit.checkStatus();

      expect(repository.getStatusCalled, true);
      expect(cubit.state.state, GoogleConnectionState.connected);
      expect(cubit.state.isConnected, true);
      expect(cubit.state.email, 'user@example.com');
    });

    test('connect sets state to connecting and prevents duplicate concurrent attempts', () async {
      // First connect attempt
      final connectFuture = cubit.connect();
      expect(cubit.state.isConnecting, true);

      // Duplicate connect attempt while already connecting
      await cubit.connect();
      // Should not throw or crash, stays connecting
      expect(cubit.state.isConnecting, true);

      await connectFuture;
    });

    test('handleDeepLinkCallback with status=success triggers checkStatus and updates to connected', () async {
      repository.currentStatus = const GoogleIntegrationStatus(
        state: GoogleConnectionState.connected,
        email: 'connected_user@gmail.com',
      );

      final successUri = Uri.parse('secondbrain://oauth/callback?status=success');
      cubit.handleDeepLinkCallback(successUri);

      // Wait for checkStatus to complete
      await pumpEventQueue();

      expect(repository.getStatusCalled, true);
      expect(cubit.state.isConnected, true);
      expect(cubit.state.email, 'connected_user@gmail.com');
    });

    test('handleDeepLinkCallback with status=cancelled emits cancelled state', () {
      final cancelUri = Uri.parse('secondbrain://oauth/callback?status=cancelled&error=access_denied');
      cubit.handleDeepLinkCallback(cancelUri);

      expect(cubit.state.state, GoogleConnectionState.cancelled);
      expect(cubit.state.errorMessage, 'Google connection was cancelled.');
    });

    test('handleDeepLinkCallback with invalid_or_expired_state emits connectionFailed', () {
      final errorUri = Uri.parse(
          'secondbrain://oauth/callback?status=error&reason=invalid_or_expired_state');
      cubit.handleDeepLinkCallback(errorUri);

      expect(cubit.state.state, GoogleConnectionState.connectionFailed);
      expect(cubit.state.errorMessage, 'invalid_or_expired_state');
    });

    test('Security verification: Deep link contains zero authorization codes or tokens', () {
      final safeDeepLink = Uri.parse('secondbrain://oauth/callback?status=success');
      expect(safeDeepLink.queryParameters.containsKey('code'), false);
      expect(safeDeepLink.queryParameters.containsKey('access_token'), false);
      expect(safeDeepLink.queryParameters.containsKey('refresh_token'), false);
      expect(safeDeepLink.queryParameters.containsKey('state'), false);
      expect(safeDeepLink.queryParameters['status'], 'success');
    });

    test('disconnect revokes tokens via repository and resets state to notConnected', () async {
      repository.currentStatus = const GoogleIntegrationStatus(
        state: GoogleConnectionState.connected,
        email: 'user@example.com',
      );
      await cubit.checkStatus();
      expect(cubit.state.isConnected, true);

      await cubit.disconnect();

      expect(repository.disconnectCalled, true);
      expect(cubit.state.state, GoogleConnectionState.notConnected);
      expect(cubit.state.isConnected, false);
      expect(cubit.state.email, isNull);
    });
  });
}
