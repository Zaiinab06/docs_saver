import 'package:flutter_test/flutter_test.dart';

/// Contract entity for Google Docs import result.
class GoogleDocImportResult {
  final bool success;
  final String title;
  final String content;
  final String fileId;
  final String webViewLink;
  final String mimeType;

  const GoogleDocImportResult({
    required this.success,
    required this.title,
    required this.content,
    required this.fileId,
    required this.webViewLink,
    required this.mimeType,
  });

  factory GoogleDocImportResult.fromJson(Map<String, dynamic> json) {
    return GoogleDocImportResult(
      success: json['success'] == true,
      title: json['title'] as String? ?? 'Untitled Google Doc',
      content: json['content'] as String? ?? '',
      fileId: json['fileId'] as String? ?? '',
      webViewLink: json['webViewLink'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
    );
  }
}

/// Helper to simulate and test backend contract validation logic for import_doc.
class GoogleDocsImportContractValidator {
  static const int maxContentLength = 500000;
  static final RegExp fileIdRegex = RegExp(r'^[a-zA-Z0-9_-]{10,128}$');

  static Map<String, dynamic>? validateRequest({required dynamic fileId}) {
    if (fileId == null || fileId is! String || fileId.trim().isEmpty) {
      return {
        'status': 400,
        'error': 'INVALID_FILE_ID',
        'message': 'Missing or invalid Google Drive file ID.',
      };
    }

    final trimmed = fileId.trim();
    if (!fileIdRegex.hasMatch(trimmed)) {
      return {
        'status': 400,
        'error': 'INVALID_FILE_ID',
        'message': 'Invalid Google Drive file ID format.',
      };
    }

    return null; // Valid
  }

  static Map<String, dynamic> handleDriveMetadata({
    required int statusCode,
    Map<String, dynamic>? metaData,
  }) {
    if (statusCode == 404) {
      return {
        'status': 404,
        'error': 'FILE_NOT_FOUND',
        'message':
            'File not found or not accessible. Under the current Google Drive permissions, the document must be opened with Google Picker or created by Second Brain.',
      };
    }
    if (statusCode == 403) {
      return {
        'status': 403,
        'error': 'PERMISSION_DENIED',
        'message': 'Access denied to the requested Google Drive file.',
      };
    }
    if (statusCode == 429) {
      return {
        'status': 429,
        'error': 'RATE_LIMITED',
        'message': 'Google Drive API rate limit exceeded. Please try again shortly.',
      };
    }
    if (statusCode != 200 || metaData == null) {
      return {
        'status': 502,
        'error': 'DRIVE_API_ERROR',
        'message': 'Google Drive API returned error (HTTP $statusCode).',
      };
    }

    if (metaData['trashed'] == true) {
      return {
        'status': 400,
        'error': 'FILE_TRASHED',
        'message': 'The selected file is in the Google Drive trash.',
      };
    }

    final mimeType = metaData['mimeType'] as String?;
    if (mimeType != 'application/vnd.google-apps.document') {
      return {
        'status': 400,
        'error': 'UNSUPPORTED_MIME_TYPE',
        'message':
            'Unsupported file type ($mimeType). Currently, only Google Docs documents can be imported.',
      };
    }

    return {'status': 200};
  }

  static Map<String, dynamic> handleExportedContent({
    required int statusCode,
    required String? content,
    required Map<String, dynamic> metaData,
  }) {
    if (statusCode != 200 || content == null) {
      return {
        'status': 502,
        'error': 'EXPORT_FAILED',
        'message': 'Failed to export Google Docs content (HTTP $statusCode).',
      };
    }

    if (content.trim().isEmpty) {
      return {
        'status': 400,
        'error': 'EMPTY_DOCUMENT',
        'message': 'The selected Google Doc is empty.',
      };
    }

    if (content.length > maxContentLength) {
      return {
        'status': 400,
        'error': 'DOCUMENT_TOO_LARGE',
        'message':
            'Document exceeds maximum allowable size ($maxContentLength characters).',
      };
    }

    return {
      'status': 200,
      'data': {
        'success': true,
        'title': metaData['name'] ?? 'Untitled Google Doc',
        'content': content,
        'fileId': metaData['id'],
        'webViewLink': metaData['webViewLink'] ??
            'https://docs.google.com/document/d/${metaData['id']}/edit',
        'mimeType': metaData['mimeType'],
      },
    };
  }
}

void main() {
  group('Phase 2A — Google Docs Import Backend Contract & Validation Tests', () {
    test('Reject missing, null, or whitespace-only fileId', () {
      final nullResult =
          GoogleDocsImportContractValidator.validateRequest(fileId: null);
      expect(nullResult?['status'], 400);
      expect(nullResult?['error'], 'INVALID_FILE_ID');

      final emptyResult =
          GoogleDocsImportContractValidator.validateRequest(fileId: '');
      expect(emptyResult?['status'], 400);
      expect(emptyResult?['error'], 'INVALID_FILE_ID');

      final whitespaceResult =
          GoogleDocsImportContractValidator.validateRequest(fileId: '   ');
      expect(whitespaceResult?['status'], 400);
      expect(whitespaceResult?['error'], 'INVALID_FILE_ID');
    });

    test('Reject malformed fileId with path traversal or illegal characters', () {
      final traversal = GoogleDocsImportContractValidator.validateRequest(
          fileId: '../../etc/passwd');
      expect(traversal?['status'], 400);
      expect(traversal?['error'], 'INVALID_FILE_ID');

      final withSpaces = GoogleDocsImportContractValidator.validateRequest(
          fileId: '1BxiMVs0XRA5nFMdKvBdBZjgm UUqptlbs74OgvE2upms');
      expect(withSpaces?['status'], 400);
      expect(withSpaces?['error'], 'INVALID_FILE_ID');

      final tooShort =
          GoogleDocsImportContractValidator.validateRequest(fileId: 'abc12');
      expect(tooShort?['status'], 400);
      expect(tooShort?['error'], 'INVALID_FILE_ID');
    });

    test('Accept valid Google Drive fileId format', () {
      final valid1 = GoogleDocsImportContractValidator.validateRequest(
          fileId: '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms');
      expect(valid1, isNull);

      final validWithHyphen = GoogleDocsImportContractValidator.validateRequest(
          fileId: '1_yJ0-kR27qXn4AbCdEfGhIjKlMnOpQrStUvWxYz-09');
      expect(validWithHyphen, isNull);
    });

    test('Maps 404 to FILE_NOT_FOUND with clear drive.file scope explanation', () {
      final result =
          GoogleDocsImportContractValidator.handleDriveMetadata(statusCode: 404);
      expect(result['status'], 404);
      expect(result['error'], 'FILE_NOT_FOUND');
      expect(result['message'], contains('Google Picker'));
    });

    test('Maps 403 to PERMISSION_DENIED', () {
      final result =
          GoogleDocsImportContractValidator.handleDriveMetadata(statusCode: 403);
      expect(result['status'], 403);
      expect(result['error'], 'PERMISSION_DENIED');
    });

    test('Maps 429 to RATE_LIMITED', () {
      final result =
          GoogleDocsImportContractValidator.handleDriveMetadata(statusCode: 429);
      expect(result['status'], 429);
      expect(result['error'], 'RATE_LIMITED');
    });

    test('Rejects trashed Google Drive files', () {
      final result = GoogleDocsImportContractValidator.handleDriveMetadata(
        statusCode: 200,
        metaData: {
          'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'name': 'Trashed Doc',
          'mimeType': 'application/vnd.google-apps.document',
          'trashed': true,
        },
      );
      expect(result['status'], 400);
      expect(result['error'], 'FILE_TRASHED');
    });

    test('Rejects unsupported non-Google-Docs MIME types (e.g. PDF, Sheet, image)',
        () {
      final pdfResult = GoogleDocsImportContractValidator.handleDriveMetadata(
        statusCode: 200,
        metaData: {
          'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'name': 'Report.pdf',
          'mimeType': 'application/pdf',
          'trashed': false,
        },
      );
      expect(pdfResult['status'], 400);
      expect(pdfResult['error'], 'UNSUPPORTED_MIME_TYPE');

      final sheetResult = GoogleDocsImportContractValidator.handleDriveMetadata(
        statusCode: 200,
        metaData: {
          'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'name': 'Budget.xlsx',
          'mimeType': 'application/vnd.google-apps.spreadsheet',
          'trashed': false,
        },
      );
      expect(sheetResult['status'], 400);
      expect(sheetResult['error'], 'UNSUPPORTED_MIME_TYPE');
    });

    test('Rejects empty document content without fabricating placeholder text', () {
      final result = GoogleDocsImportContractValidator.handleExportedContent(
        statusCode: 200,
        content: '   \n\t  ',
        metaData: {
          'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'name': 'Empty Doc',
          'mimeType': 'application/vnd.google-apps.document',
        },
      );
      expect(result['status'], 400);
      expect(result['error'], 'EMPTY_DOCUMENT');
    });

    test('Rejects documents exceeding 500,000 characters to prevent DoS', () {
      final hugeContent = 'A' * 500001;
      final result = GoogleDocsImportContractValidator.handleExportedContent(
        statusCode: 200,
        content: hugeContent,
        metaData: {
          'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'name': 'Huge Doc',
          'mimeType': 'application/vnd.google-apps.document',
        },
      );
      expect(result['status'], 400);
      expect(result['error'], 'DOCUMENT_TOO_LARGE');
    });

    test('Successfully parses and sanitizes real Google Docs export response', () {
      const realText =
          'Second Brain Project Specifications\n\n1. Overview\nThis document outlines the architecture for Google Drive integration.';
      final metaData = {
        'id': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
        'name': 'Second Brain Specs',
        'mimeType': 'application/vnd.google-apps.document',
        'webViewLink':
            'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit',
      };

      final result = GoogleDocsImportContractValidator.handleExportedContent(
        statusCode: 200,
        content: realText,
        metaData: metaData,
      );

      expect(result['status'], 200);
      final data = result['data'] as Map<String, dynamic>;
      final docResult = GoogleDocImportResult.fromJson(data);

      expect(docResult.success, isTrue);
      expect(docResult.title, 'Second Brain Specs');
      expect(docResult.content, realText);
      expect(docResult.fileId, '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms');
      expect(docResult.webViewLink,
          'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit');
      expect(docResult.mimeType, 'application/vnd.google-apps.document');
    });
  });
}
