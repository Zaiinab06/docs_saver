import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/google_integration_status.dart';
import '../../domain/repositories/google_auth_repository.dart';

class GoogleAuthCubit extends Cubit<GoogleIntegrationStatus> {
  final GoogleAuthRepository repository;

  GoogleAuthCubit({required this.repository})
    : super(const GoogleIntegrationStatus());

  Future<void> checkStatus() async {
    try {
      final status = await repository.getStatus();
      debugPrint('[Google OAuth] Integration status: ${status.state.name}.');
      emit(status);
    } catch (_) {
      debugPrint('[Google OAuth] Status check failed.');
      emit(state.copyWith(state: GoogleConnectionState.notConnected));
    }
  }

  Future<void> connect() async {
    if (state.isConnecting) return; // Prevent duplicate connection attempts

    emit(
      state.copyWith(
        state: GoogleConnectionState.connecting,
        errorMessage: null,
      ),
    );

    try {
      debugPrint('[Google OAuth] Starting authorization.');
      final authUrl = await repository.startOAuth();
      final uri = Uri.parse(authUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        debugPrint('[Google OAuth] Browser launch failed.');
        emit(
          state.copyWith(
            state: GoogleConnectionState.connectionFailed,
            errorMessage: 'Could not open system browser for Google sign-in.',
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '[Google OAuth] Authorization start failed: ${e.toString().replaceFirst('Exception: ', '')}.',
      );
      emit(
        state.copyWith(
          state: GoogleConnectionState.connectionFailed,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  void handleDeepLinkCallback(Uri uri) {
    final status = uri.queryParameters['status'];
    final error = uri.queryParameters['error'] ?? uri.queryParameters['reason'];

    debugPrint(
      '[Google OAuth] Callback received: status=${status ?? 'missing'}, reason=${error ?? 'none'}.',
    );

    if (status == 'success') {
      debugPrint(
        '[Google OAuth] Callback succeeded; refreshing integration status.',
      );
      checkStatus();
    } else if (status == 'cancelled') {
      debugPrint('[Google OAuth] Callback cancelled.');
      emit(
        state.copyWith(
          state: GoogleConnectionState.cancelled,
          errorMessage: 'Google connection was cancelled.',
        ),
      );
    } else {
      debugPrint(
        '[Google OAuth] Callback failed: ${error ?? 'unknown_error'}.',
      );
      emit(
        state.copyWith(
          state: GoogleConnectionState.connectionFailed,
          errorMessage: error ?? 'Google connection failed.',
        ),
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await repository.disconnect();
      emit(
        const GoogleIntegrationStatus(
          state: GoogleConnectionState.notConnected,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
