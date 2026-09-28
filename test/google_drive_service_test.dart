import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/services/google_drive_service.dart';

class MockInterceptor extends Interceptor {
  final List<RequestOptions> capturedRequests = [];
  Map<String, dynamic> metadataResponse = {
    'id': 'test-file-id',
    'name': 'Test Document',
    'mimeType': 'application/vnd.google-apps.document',
    'webViewLink': 'https://drive.google.com/file/d/test-file-id/view',
  };
  List<int> binaryResponse = utf8.encode('mock binary data');
  String textResponse = 'mock text content';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequests.add(options);

    final path = options.path;
    if (path.endsWith('/export')) {
      final mime = options.queryParameters['mimeType'];
      if (mime == 'application/pdf') {
        return handler.resolve(
          Response(
            requestOptions: options,
            data: binaryResponse,
            statusCode: 200,
          ),
        );
      } else {
        return handler.resolve(
          Response(
            requestOptions: options,
            data: textResponse,
            statusCode: 200,
          ),
        );
      }
    } else if (options.queryParameters['alt'] == 'media') {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: binaryResponse,
          statusCode: 200,
        ),
      );
    } else {
      // Metadata request
      return handler.resolve(
        Response(
          requestOptions: options,
          data: metadataResponse,
          statusCode: 200,
        ),
      );
    }
  }
}

void main() {
  late Dio testDio;
  late MockInterceptor interceptor;
  const testAccessToken = 'ya29.mock_access_token_12345';
  const testFileId = 'file_abc_123';

  setUp(() {
    testDio = Dio();
    interceptor = MockInterceptor();
    testDio.interceptors.add(interceptor);
    GoogleDriveService.dio = testDio;
  });

  group('GoogleDriveService Download Routing and Headers', () {
    test('Google Doc uses /export?mimeType=application/pdf and includes required headers', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'Meeting Notes',
        'mimeType': 'application/vnd.google-apps.document',
      };

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.title, equals('Meeting Notes'));
      expect(doc.mediaType, equals('pdf'));
      expect(doc.mimeType, equals('application/pdf'));

      // Check captured requests
      final exportRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.path.contains('/export') && r.queryParameters['mimeType'] == 'application/pdf',
      );
      expect(exportRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(exportRequest.headers['Accept'], equals('*/*'));
      expect(exportRequest.queryParameters['mimeType'], equals('application/pdf'));
    });

    test('Google Sheet uses /export?mimeType=application/pdf', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'Budget 2026',
        'mimeType': 'application/vnd.google-apps.spreadsheet',
      };

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.title, equals('Budget 2026'));
      expect(doc.mediaType, equals('pdf'));

      final exportPdfRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.path.contains('/export') && r.queryParameters['mimeType'] == 'application/pdf',
      );
      expect(exportPdfRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(exportPdfRequest.headers['Accept'], equals('*/*'));
    });

    test('Google Slide uses /export?mimeType=application/pdf', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'Keynote Presentation',
        'mimeType': 'application/vnd.google-apps.presentation',
      };

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.title, equals('Keynote Presentation'));
      expect(doc.mediaType, equals('pdf'));

      final exportPdfRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.path.contains('/export') && r.queryParameters['mimeType'] == 'application/pdf',
      );
      expect(exportPdfRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(exportPdfRequest.headers['Accept'], equals('*/*'));
    });

    test('Standard PDF (application/pdf) calls alt=media and NEVER calls /export', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'TaxReturn2025.pdf',
        'mimeType': 'application/pdf',
      };

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.title, equals('TaxReturn2025.pdf'));
      expect(doc.mediaType, equals('pdf'));
      expect(doc.mimeType, equals('application/pdf'));

      // Verify /export was NOT called
      final exportCalls = interceptor.capturedRequests.where((r) => r.path.contains('/export'));
      expect(exportCalls, isEmpty);

      // Verify alt=media was called with required headers
      final mediaRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.queryParameters['alt'] == 'media',
      );
      expect(mediaRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(mediaRequest.headers['Accept'], equals('*/*'));
      expect(mediaRequest.queryParameters['alt'], equals('media'));
    });

    test('Standard image (image/png) calls alt=media and NEVER calls /export', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'Receipt.png',
        'mimeType': 'image/png',
      };

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.mediaType, equals('image'));
      expect(doc.mimeType, equals('image/png'));

      // Verify /export was NOT called
      final exportCalls = interceptor.capturedRequests.where((r) => r.path.contains('/export'));
      expect(exportCalls, isEmpty);

      final mediaRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.queryParameters['alt'] == 'media',
      );
      expect(mediaRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(mediaRequest.headers['Accept'], equals('*/*'));
    });

    test('Standard text file (text/plain) calls alt=media and extracts content', () async {
      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'notes.txt',
        'mimeType': 'text/plain',
      };
      interceptor.binaryResponse = utf8.encode('Hello plain text');

      final doc = await GoogleDriveService.importFileDirect(
        fileId: testFileId,
        accessToken: testAccessToken,
      );

      expect(doc.success, isTrue);
      expect(doc.content, equals('Hello plain text'));

      // Verify /export was NOT called
      final exportCalls = interceptor.capturedRequests.where((r) => r.path.contains('/export'));
      expect(exportCalls, isEmpty);

      final mediaRequest = interceptor.capturedRequests.firstWhere(
        (r) => r.queryParameters['alt'] == 'media',
      );
      expect(mediaRequest.headers['Authorization'], equals('Bearer $testAccessToken'));
      expect(mediaRequest.headers['Accept'], equals('*/*'));
    });

    test('HTTP 403 on binary download throws Exception and clears cachedAccessToken', () async {
      GoogleDriveService.cachedAccessToken = testAccessToken;
      expect(GoogleDriveService.cachedAccessToken, isNotNull);

      interceptor.metadataResponse = {
        'id': testFileId,
        'name': 'ProtectedFile.pdf',
        'mimeType': 'application/pdf',
      };

      // Mock 403 Forbidden for media download
      testDio.interceptors.clear();
      testDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.queryParameters['alt'] == 'media') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 403,
                  data: utf8.encode('{"error": {"code": 403, "message": "The user has not granted read access"}}'),
                ),
              );
            }
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': testFileId,
                  'name': 'ProtectedFile.pdf',
                  'mimeType': 'application/pdf',
                },
              ),
            );
          },
        ),
      );

      await expectLater(
        () => GoogleDriveService.importFileDirect(
          fileId: testFileId,
          accessToken: testAccessToken,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify cached token was wiped to force re-consent
      expect(GoogleDriveService.cachedAccessToken, isNull);
    });

    test('Scope constants include drive.readonly and drive.file', () {
      expect(
        GoogleDriveService.driveReadOnlyScope,
        equals('https://www.googleapis.com/auth/drive.readonly'),
      );
      expect(
        GoogleDriveService.driveFileScope,
        equals('https://www.googleapis.com/auth/drive.file'),
      );
      expect(
        GoogleDriveService.fullDriveScopes,
        contains('https://www.googleapis.com/auth/drive.readonly'),
      );
      expect(
        GoogleDriveService.fullDriveScopes,
        contains('https://www.googleapis.com/auth/drive.file'),
      );
    });
  });
}
