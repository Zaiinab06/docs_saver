import '../entities/google_doc_entity.dart';
import '../entities/google_integration_status.dart';

abstract class GoogleAuthRepository {
  /// Initiates OAuth flow with Supabase backend and returns the Google authorization URL.
  Future<String> startOAuth();

  /// Fetches the current Google Drive integration status for the authenticated user.
  Future<GoogleIntegrationStatus> getStatus();

  /// Disconnects the Google account and revokes tokens.
  Future<void> disconnect();

  /// Imports a Google Docs document by its fileId and extracts plain text content.
  Future<GoogleDocEntity> importDoc(String fileId);

  /// Initiates Google Picker OAuth flow (trigger_onepick=true) and returns authorization URL.
  Future<String> startGooglePicker();

  /// Imports an authorized Google Drive file (Docs, Sheets, Slides, Text, PDF, Media) by fileId.
  Future<GoogleDocEntity> importDriveFile(String fileId);
}
