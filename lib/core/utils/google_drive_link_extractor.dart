/// Utility for safely parsing and extracting Google Drive and Google Workspace file IDs from URLs.
///
/// Supports:
/// - https://docs.google.com/document/d/<fileId>/edit
/// - https://docs.google.com/spreadsheets/d/<fileId>/edit
/// - https://docs.google.com/presentation/d/<fileId>/edit
/// - https://drive.google.com/file/d/<fileId>/view
/// - https://drive.google.com/open?id=<fileId>
/// - https://drive.google.com/uc?id=<fileId>
///
/// Rejects folders, forms, invalid IDs, and non-Google domains.
class GoogleDriveLinkExtractor {
  static final RegExp _fileIdRegex = RegExp(r'^[a-zA-Z0-9_-]{10,128}$');

  /// Detects whether [rawUrl] is a recognized Google Drive or Google Workspace document URL.
  static bool isGoogleDriveUrl(String? rawUrl) {
    return extractFileId(rawUrl) != null;
  }

  /// Extracts the Google Drive [fileId] from supported URL patterns.
  static String? extractFileId(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    final host = uri.host.toLowerCase().trim();

    // 1. docs.google.com patterns: document, spreadsheets, presentation
    if (host == 'docs.google.com' || host == 'www.docs.google.com') {
      final segments = uri.pathSegments;
      if (segments.length >= 3) {
        final type = segments[0].toLowerCase();
        // Support documents, spreadsheets, and presentations
        if (type == 'document' ||
            type == 'spreadsheets' ||
            type == 'presentation') {
          if (segments[1].toLowerCase() == 'd') {
            final candidate = segments[2].trim();
            if (_fileIdRegex.hasMatch(candidate)) {
              return candidate;
            }
          }
        }
      }
      return null;
    }

    // 2. drive.google.com patterns
    if (host == 'drive.google.com' || host == 'www.drive.google.com') {
      // Reject folder URLs explicitly
      if (uri.path.contains('/drive/folders/') ||
          uri.path.contains('/folders/')) {
        return null;
      }

      // Pattern A: /file/d/<fileId>/...
      final segments = uri.pathSegments;
      if (segments.length >= 3 &&
          segments[0].toLowerCase() == 'file' &&
          segments[1].toLowerCase() == 'd') {
        final candidate = segments[2].trim();
        if (_fileIdRegex.hasMatch(candidate)) {
          return candidate;
        }
      }

      // Pattern B: /open?id=<fileId> or /uc?id=<fileId>
      final queryId = uri.queryParameters['id']?.trim();
      if (queryId != null && _fileIdRegex.hasMatch(queryId)) {
        return queryId;
      }

      return null;
    }

    return null;
  }

  /// Returns a canonical Google Drive / Docs URL for the given [fileId].
  static String toCanonicalUrl(String fileId) {
    return 'https://drive.google.com/file/d/$fileId/view';
  }
}
