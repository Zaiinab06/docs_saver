/// Utility for safely parsing and extracting file IDs from Google Docs URLs.
class GoogleDocsLinkExtractor {
  static final RegExp _fileIdRegex = RegExp(r'^[a-zA-Z0-9_-]{10,128}$');

  /// Detects whether the provided [rawUrl] is a valid Google Docs document URL.
  static bool isGoogleDocsUrl(String? rawUrl) {
    return extractFileId(rawUrl) != null;
  }

  /// Extracts the Google Docs [fileId] from supported URL formats:
  /// - https://docs.google.com/document/d/<fileId>/edit
  /// - https://docs.google.com/document/d/<fileId>/view
  /// - https://docs.google.com/document/d/<fileId>
  ///
  /// Rejects malformed URLs, non-Google-Docs URLs (e.g. Sheets, Slides, Forms, Drive folders),
  /// and invalid fileId lengths/characters.
  static String? extractFileId(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    final host = uri.host.toLowerCase().trim();
    // Host must be docs.google.com (or www.docs.google.com)
    if (host != 'docs.google.com' && host != 'www.docs.google.com') {
      return null;
    }

    // Path segments: ['document', 'd', '<fileId>', ...]
    final segments = uri.pathSegments;
    if (segments.length < 3) return null;

    if (segments[0].toLowerCase() != 'document' || segments[1].toLowerCase() != 'd') {
      return null;
    }

    final candidate = segments[2].trim();
    if (!_fileIdRegex.hasMatch(candidate)) {
      return null;
    }

    return candidate;
  }

  /// Returns a canonical Google Docs URL for the given [fileId].
  static String toCanonicalUrl(String fileId) {
    return 'https://docs.google.com/document/d/$fileId/edit';
  }
}
