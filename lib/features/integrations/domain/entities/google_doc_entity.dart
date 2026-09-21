/// Represents the result of a Google Docs document import from the backend.
class GoogleDocEntity {
  final bool success;
  final String title;
  final String content;
  final String fileId;
  final String webViewLink;
  final String mimeType;
  final int? fileSize;
  final String? extractionMethod;
  final String? mediaBase64;
  final String? mediaType;
  final List<String>? warnings;

  const GoogleDocEntity({
    required this.success,
    required this.title,
    required this.content,
    required this.fileId,
    required this.webViewLink,
    required this.mimeType,
    this.fileSize,
    this.extractionMethod,
    this.mediaBase64,
    this.mediaType,
    this.warnings,
  });

  factory GoogleDocEntity.fromJson(Map<String, dynamic> json) {
    return GoogleDocEntity(
      success: json['success'] == true,
      title: (json['title'] as String?)?.trim() ?? 'Untitled Document',
      content: (json['content'] as String?) ?? '',
      fileId: (json['fileId'] as String?) ?? '',
      webViewLink: (json['webViewLink'] as String?) ?? '',
      mimeType: (json['mimeType'] as String?) ?? 'application/vnd.google-apps.document',
      fileSize: json['fileSize'] as int?,
      extractionMethod: json['extractionMethod'] as String?,
      mediaBase64: json['mediaBase64'] as String?,
      mediaType: json['mediaType'] as String?,
      warnings: (json['warnings'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'title': title,
        'content': content,
        'fileId': fileId,
        'webViewLink': webViewLink,
        'mimeType': mimeType,
        if (fileSize != null) 'fileSize': fileSize,
        if (extractionMethod != null) 'extractionMethod': extractionMethod,
        if (mediaBase64 != null) 'mediaBase64': mediaBase64,
        if (mediaType != null) 'mediaType': mediaType,
        if (warnings != null) 'warnings': warnings,
      };
}

/// Typed exception for Google Docs import errors with error code and user-friendly message.
class GoogleDocsImportException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const GoogleDocsImportException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'GoogleDocsImportException($code): $message';
}
