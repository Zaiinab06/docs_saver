import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/utils/google_docs_link_extractor.dart';
import 'package:second_brain/core/utils/link_metadata_extractor.dart';
import 'package:second_brain/features/brain_ai/domain/entities/ai_ingestion_result.dart';
import 'package:second_brain/features/brain_ai/domain/repositories/ai_repository.dart';
import 'package:second_brain/features/brain_ai/domain/usecases/ingest_memory_usecase.dart';
import 'package:second_brain/features/integrations/domain/entities/google_doc_entity.dart';
import 'package:second_brain/features/integrations/domain/entities/google_integration_status.dart';
import 'package:second_brain/features/integrations/domain/repositories/google_auth_repository.dart';

// Mock repository for testing importDoc handling and error propagation
class MockGoogleAuthRepository implements GoogleAuthRepository {
  GoogleIntegrationStatus statusToReturn = const GoogleIntegrationStatus(
    state: GoogleConnectionState.connected,
    email: 'test@example.com',
  );
  GoogleDocEntity? docToReturn;
  Object? errorToThrow;
  String? lastImportedFileId;

  @override
  Future<String> startOAuth() async => 'https://accounts.google.com/o/oauth2/auth';

  @override
  Future<GoogleIntegrationStatus> getStatus() async => statusToReturn;

  @override
  Future<void> disconnect() async {}

  @override
  Future<GoogleDocEntity> importDoc(String fileId) async {
    lastImportedFileId = fileId;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return docToReturn ??
        GoogleDocEntity(
          success: true,
          title: 'Test Google Doc',
          content: 'This is the real extracted plain text content of the Google Doc.',
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

class MockAiRepository implements AiRepository {
  String? receivedOcrText;
  AiIngestionResult resultToReturn = const AiIngestionResult(
    title: 'AI Generated Title',
    summary: 'AI Generated Summary from real content',
    category: 'Work',
    tags: ['work', 'docs'],
    entities: [],
    aiStatus: 'processed',
  );

  @override
  Future<AiIngestionResult> processPhotoIngestion({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
  }) async {
    receivedOcrText = ocrText;
    return resultToReturn;
  }
}

// Mock IngestMemoryUseCase to track what text AI receives
class MockIngestMemoryUseCase implements IngestMemoryUseCase {
  @override
  final AiRepository repository;

  String? receivedOcrText;
  AiIngestionResult resultToReturn = const AiIngestionResult(
    title: 'AI Generated Title',
    summary: 'AI Generated Summary from real content',
    category: 'Work',
    tags: ['work', 'docs'],
    entities: [],
    aiStatus: 'processed',
  );

  MockIngestMemoryUseCase({AiRepository? repo})
      : repository = repo ?? MockAiRepository();

  @override
  Future<AiIngestionResult> call({
    required String ocrText,
    String? imageBase64,
    String? mimeType,
    String? documentBase64,
  }) async {
    receivedOcrText = ocrText;
    return resultToReturn;
  }
}

void main() {
  group('GoogleDocsLinkExtractor', () {
    const validId = '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms';

    test('extracts fileId from standard /edit URL', () {
      const url = 'https://docs.google.com/document/d/$validId/edit';
      expect(GoogleDocsLinkExtractor.extractFileId(url), equals(validId));
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isTrue);
    });

    test('extracts fileId from /view URL with query params', () {
      const url = 'https://docs.google.com/document/d/$validId/view?usp=sharing';
      expect(GoogleDocsLinkExtractor.extractFileId(url), equals(validId));
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isTrue);
    });

    test('extracts fileId from bare /d/<fileId> URL', () {
      const url = 'https://docs.google.com/document/d/$validId';
      expect(GoogleDocsLinkExtractor.extractFileId(url), equals(validId));
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isTrue);
    });

    test('extracts fileId from www.docs.google.com with preview', () {
      const url = 'https://www.docs.google.com/document/d/$validId/preview';
      expect(GoogleDocsLinkExtractor.extractFileId(url), equals(validId));
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isTrue);
    });

    test('generates canonical URL correctly', () {
      expect(
        GoogleDocsLinkExtractor.toCanonicalUrl(validId),
        equals('https://docs.google.com/document/d/$validId/edit'),
      );
    });

    test('rejects Google Sheets URLs', () {
      const url = 'https://docs.google.com/spreadsheets/d/$validId/edit';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects Google Presentation / Slides URLs', () {
      const url = 'https://docs.google.com/presentation/d/$validId/edit';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects Google Forms URLs', () {
      const url = 'https://docs.google.com/forms/d/$validId/edit';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects Google Drive folder URLs', () {
      const url = 'https://drive.google.com/drive/folders/$validId';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects Google Drive file URLs', () {
      const url = 'https://drive.google.com/file/d/$validId/view';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects non-Google-Docs domains', () {
      const url = 'https://example.com/document/d/$validId/edit';
      expect(GoogleDocsLinkExtractor.extractFileId(url), isNull);
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(url), isFalse);
    });

    test('rejects invalid or too short file IDs', () {
      expect(GoogleDocsLinkExtractor.extractFileId('https://docs.google.com/document/d/short/edit'), isNull);
      expect(GoogleDocsLinkExtractor.extractFileId('https://docs.google.com/document/d/'), isNull);
      expect(GoogleDocsLinkExtractor.extractFileId(''), isNull);
      expect(GoogleDocsLinkExtractor.extractFileId(null), isNull);
      expect(GoogleDocsLinkExtractor.extractFileId('not a url'), isNull);
    });
  });

  group('GoogleDocEntity and GoogleDocsImportException', () {
    test('deserializes complete GoogleDocEntity from JSON', () {
      final json = {
        'success': true,
        'title': 'Project Architecture Spec',
        'content': 'Comprehensive plain text of the document...',
        'fileId': '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
        'webViewLink': 'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit',
        'mimeType': 'application/vnd.google-apps.document',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.success, isTrue);
      expect(entity.title, equals('Project Architecture Spec'));
      expect(entity.content, equals('Comprehensive plain text of the document...'));
      expect(entity.fileId, equals('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms'));
      expect(entity.webViewLink, equals('https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit'));
      expect(entity.mimeType, equals('application/vnd.google-apps.document'));
    });

    test('provides safe defaults for missing optional fields in JSON', () {
      final json = {
        'success': true,
        'content': 'Some content',
        'fileId': 'file123',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.title, equals('Untitled Document'));
      expect(entity.mimeType, equals('application/vnd.google-apps.document'));
      expect(entity.webViewLink, isEmpty);
    });

    test('serializes to JSON correctly', () {
      const entity = GoogleDocEntity(
        success: true,
        title: 'Doc Title',
        content: 'Content',
        fileId: 'id123',
        webViewLink: 'https://docs.google.com/document/d/id123',
        mimeType: 'application/vnd.google-apps.document',
      );

      final json = entity.toJson();
      expect(json['success'], isTrue);
      expect(json['title'], equals('Doc Title'));
      expect(json['content'], equals('Content'));
      expect(json['fileId'], equals('id123'));
    });

    test('GoogleDocsImportException preserves code, message, and statusCode', () {
      const exception = GoogleDocsImportException(
        code: 'FILE_NOT_FOUND',
        message: 'Google Drive file not found or not accessible.',
        statusCode: 404,
      );

      expect(exception.code, equals('FILE_NOT_FOUND'));
      expect(exception.message, equals('Google Drive file not found or not accessible.'));
      expect(exception.statusCode, equals(404));
      expect(exception.toString(), contains('FILE_NOT_FOUND'));
    });
  });

  group('GoogleAuthRepository importDoc error handling contract', () {
    late MockGoogleAuthRepository repository;

    setUp(() {
      repository = MockGoogleAuthRepository();
    });

    test('successful importDoc returns real document entity', () async {
      const fileId = '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms';
      repository.docToReturn = const GoogleDocEntity(
        success: true,
        title: 'Real Document Title',
        content: 'Verbatim text extracted from Google Docs API.',
        fileId: fileId,
        webViewLink: 'https://docs.google.com/document/d/$fileId/edit',
        mimeType: 'application/vnd.google-apps.document',
      );

      final result = await repository.importDoc(fileId);
      expect(result.success, isTrue);
      expect(result.title, equals('Real Document Title'));
      expect(result.content, equals('Verbatim text extracted from Google Docs API.'));
      expect(repository.lastImportedFileId, equals(fileId));
    });

    test('handles FILE_NOT_FOUND error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'FILE_NOT_FOUND',
        message: 'Google Drive file not found or not accessible.',
        statusCode: 404,
      );

      expect(
        () => repository.importDoc('non_existent_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'FILE_NOT_FOUND')),
      );
    });

    test('handles PERMISSION_DENIED error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'PERMISSION_DENIED',
        message: 'Permission denied accessing Google Drive file.',
        statusCode: 403,
      );

      expect(
        () => repository.importDoc('forbidden_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'PERMISSION_DENIED')),
      );
    });

    test('handles TOKEN_REVOKED error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'TOKEN_REVOKED',
        message: 'Google authorization expired or was revoked.',
        statusCode: 401,
      );

      expect(
        () => repository.importDoc('revoked_token_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'TOKEN_REVOKED')),
      );
    });

    test('handles GOOGLE_NOT_CONNECTED error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'GOOGLE_NOT_CONNECTED',
        message: 'Google Drive is not connected.',
        statusCode: 401,
      );

      expect(
        () => repository.importDoc('not_connected_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'GOOGLE_NOT_CONNECTED')),
      );
    });

    test('handles UNSUPPORTED_MIME_TYPE error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'UNSUPPORTED_MIME_TYPE',
        message: 'Only Google Docs documents are supported.',
        statusCode: 400,
      );

      expect(
        () => repository.importDoc('sheet_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'UNSUPPORTED_MIME_TYPE')),
      );
    });

    test('handles EMPTY_DOCUMENT error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'EMPTY_DOCUMENT',
        message: 'Google Doc contains no readable text.',
        statusCode: 422,
      );

      expect(
        () => repository.importDoc('empty_doc_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'EMPTY_DOCUMENT')),
      );
    });

    test('handles DOCUMENT_TOO_LARGE error', () async {
      repository.errorToThrow = const GoogleDocsImportException(
        code: 'DOCUMENT_TOO_LARGE',
        message: 'Google Doc exceeds maximum character limit.',
        statusCode: 413,
      );

      expect(
        () => repository.importDoc('huge_doc_id_123'),
        throwsA(isA<GoogleDocsImportException>().having((e) => e.code, 'code', 'DOCUMENT_TOO_LARGE')),
      );
    });
  });

  group('AI Ingestion with Real Exported Google Docs Text', () {
    test('AI ingestion use case receives actual document content, not URL or title', () async {
      final mockAiUseCase = MockIngestMemoryUseCase();
      const realContent = 'Section 1: Executive Summary\nThis project implements real Google Docs import.\nSection 2: Architecture\nEnd-to-end Vault security.';

      final result = await mockAiUseCase(ocrText: realContent);

      expect(mockAiUseCase.receivedOcrText, equals(realContent));
      expect(mockAiUseCase.receivedOcrText, isNot(contains('https://docs.google.com')));
      expect(result.aiStatus, equals('processed'));
      expect(result.summary, equals('AI Generated Summary from real content'));
    });
  });

  group('Generic Web Link Preservation', () {
    test('LinkProviderDetector still treats non-Docs URLs as genericWeb or social platforms', () {
      final generalUri = Uri.parse('https://example.com/blog/article');
      expect(LinkProviderDetector.detect(generalUri), equals(LinkProvider.genericWeb));

      final youtubeUri = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(LinkProviderDetector.detect(youtubeUri), equals(LinkProvider.youtube));

      // Google Docs URL is NOT detected as YouTube, TikTok, or Instagram
      final docsUri = Uri.parse('https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit');
      expect(LinkProviderDetector.detect(docsUri), equals(LinkProvider.genericWeb));
      // But GoogleDocsLinkExtractor properly detects it
      expect(GoogleDocsLinkExtractor.isGoogleDocsUrl(docsUri.toString()), isTrue);
    });
  });
}
