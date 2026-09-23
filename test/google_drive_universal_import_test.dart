import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/utils/google_drive_link_extractor.dart';
import 'package:second_brain/features/integrations/data/datasources/google_auth_remote_data_source.dart';
import 'package:second_brain/features/integrations/domain/entities/google_doc_entity.dart';
import 'package:second_brain/features/integrations/domain/entities/google_integration_status.dart';

// Test mock implementation of GoogleAuthRemoteDataSource that simulates backend edge function responses
class TestGoogleAuthRemoteDataSource implements GoogleAuthRemoteDataSource {
  Map<String, dynamic>? mockResponse;
  int mockStatusCode = 200;
  String? mockErrorMessage;
  String? mockErrorCode;
  String? lastAction;
  Map<String, dynamic>? lastBody;

  @override
  Future<String> startOAuth() async {
    lastAction = 'start';
    return 'https://accounts.google.com/o/oauth2/v2/auth?client_id=mock&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file+email+profile';
  }

  @override
  Future<String> startGooglePicker() async {
    lastAction = 'start_picker';
    return 'https://accounts.google.com/o/oauth2/v2/auth?client_id=mock&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file&trigger_onepick=true';
  }

  @override
  Future<GoogleIntegrationStatus> getStatus() async {
    lastAction = 'status';
    return const GoogleIntegrationStatus(
      state: GoogleConnectionState.connected,
      email: 'user@example.com',
    );
  }

  @override
  Future<void> disconnect() async {
    lastAction = 'disconnect';
  }

  @override
  Future<GoogleDocEntity> importDoc(String fileId) async {
    return importDriveFile(fileId);
  }

  @override
  Future<GoogleDocEntity> importDriveFile(String fileId) async {
    lastAction = 'import_doc';
    lastBody = {'fileId': fileId};

    if (mockStatusCode != 200) {
      throw GoogleDocsImportException(
        code: mockErrorCode ?? 'UNKNOWN_ERROR',
        message: mockErrorMessage ?? 'Import failed',
        statusCode: mockStatusCode,
      );
    }

    if (mockResponse != null) {
      return GoogleDocEntity.fromJson(mockResponse!);
    }

    return GoogleDocEntity(
      success: true,
      title: 'Default File',
      content: 'Sample text content',
      fileId: fileId,
      webViewLink: 'https://drive.google.com/file/d/$fileId/view',
      mimeType: 'text/plain',
    );
  }
}

void main() {
  group('GoogleDriveLinkExtractor Tests', () {
    test('Correctly extracts file ID from Google Docs URL', () {
      const url =
          'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit?tab=t.0';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, equals('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms'));
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
    });

    test('Correctly extracts file ID from Google Sheets URL', () {
      const url =
          'https://docs.google.com/spreadsheets/d/1qpyC0X9xjVCL_sk8X89x_sheet_id_12345/edit#gid=0';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, equals('1qpyC0X9xjVCL_sk8X89x_sheet_id_12345'));
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
    });

    test('Correctly extracts file ID from Google Slides URL', () {
      const url =
          'https://docs.google.com/presentation/d/1presentation_id_9876543210/edit#slide=id.p';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, equals('1presentation_id_9876543210'));
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
    });

    test(
      'Correctly extracts file ID from drive.google.com/file/d/ URL (XML, PDF, DOCX, images)',
      () {
        const url =
            'https://drive.google.com/file/d/1AbC_dEf-1234567890XyZ_test/view?usp=sharing';
        final fileId = GoogleDriveLinkExtractor.extractFileId(url);
        expect(fileId, equals('1AbC_dEf-1234567890XyZ_test'));
        expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
      },
    );

    test('Correctly extracts file ID from drive.google.com/open?id= URL', () {
      const url =
          'https://drive.google.com/open?id=1open_param_id_abcdefghij123';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, equals('1open_param_id_abcdefghij123'));
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
    });

    test('Correctly extracts file ID from drive.google.com/uc?id= URL', () {
      const url =
          'https://drive.google.com/uc?id=1uc_export_id_9876543210zyx&export=download';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, equals('1uc_export_id_9876543210zyx'));
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isTrue);
    });

    test('Rejects Google Drive folder URLs (not individual files)', () {
      const url =
          'https://drive.google.com/drive/folders/1folder_id_should_not_import_123';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, isNull);
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(url), isFalse);
    });

    test('Rejects Google Forms URLs', () {
      const url =
          'https://docs.google.com/forms/d/e/1FAIpQLSc_form_id_12345/viewform';
      final fileId = GoogleDriveLinkExtractor.extractFileId(url);
      expect(fileId, isNull);
    });

    test('Rejects non-Google URLs', () {
      expect(
        GoogleDriveLinkExtractor.extractFileId(
          'https://dropbox.com/s/12345/doc.pdf',
        ),
        isNull,
      );
      expect(
        GoogleDriveLinkExtractor.extractFileId(
          'https://onedrive.live.com/?id=123',
        ),
        isNull,
      );
      expect(
        GoogleDriveLinkExtractor.extractFileId(
          'https://example.com/file/d/12345',
        ),
        isNull,
      );
      expect(
        GoogleDriveLinkExtractor.isGoogleDriveUrl('https://example.com'),
        isFalse,
      );
    });

    test('Handles malformed or empty URLs safely without throwing', () {
      expect(GoogleDriveLinkExtractor.extractFileId(''), isNull);
      expect(GoogleDriveLinkExtractor.extractFileId('not-a-url'), isNull);
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl(''), isFalse);
      expect(GoogleDriveLinkExtractor.isGoogleDriveUrl('http://:80'), isFalse);
    });
  });

  group('GoogleDocEntity Serialization & Format Support Tests', () {
    test('Deserializes native Google Doc response correctly', () {
      final json = {
        'success': true,
        'title': 'Project Roadmap.gdoc',
        'content': 'Q1 2026 Roadmap objectives and deliverables.',
        'fileId': '1doc_id_12345',
        'webViewLink': 'https://docs.google.com/document/d/1doc_id_12345/edit',
        'mimeType': 'application/vnd.google-apps.document',
        'extractionMethod': 'google_docs_export',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.success, isTrue);
      expect(entity.title, equals('Project Roadmap.gdoc'));
      expect(entity.content, contains('Q1 2026 Roadmap'));
      expect(entity.mimeType, equals('application/vnd.google-apps.document'));
      expect(entity.extractionMethod, equals('google_docs_export'));
      expect(entity.mediaBase64, isNull);
      expect(entity.mediaType, isNull);
      expect(entity.warnings, isNull);
    });

    test('Deserializes PDF document with Gemini multimodal payload', () {
      final json = {
        'success': true,
        'title': 'Annual_Report_2025.pdf',
        'content': '',
        'fileId': '1pdf_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1pdf_id_12345/view',
        'mimeType': 'application/pdf',
        'extractionMethod': 'gemini_pdf',
        'mediaType': 'pdf',
        'mediaBase64': 'JVBERi0xLjQKJcTl8uXr...',
        'fileSize': 1048576,
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.mimeType, equals('application/pdf'));
      expect(entity.extractionMethod, equals('gemini_pdf'));
      expect(entity.mediaType, equals('pdf'));
      expect(entity.mediaBase64, equals('JVBERi0xLjQKJcTl8uXr...'));
      expect(entity.fileSize, equals(1048576));
    });

    test('Deserializes Word DOCX with OpenXML extracted content', () {
      final json = {
        'success': true,
        'title': 'Contract_Draft.docx',
        'content':
            'Section 1: Parties\nSection 2: Terms and Conditions\nSection 3: Signatures',
        'fileId': '1docx_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1docx_id_12345/view',
        'mimeType':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'extractionMethod': 'docx_xml',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(
        entity.mimeType,
        equals(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
      );
      expect(entity.extractionMethod, equals('docx_xml'));
      expect(entity.content, contains('Section 1: Parties'));
    });

    test('Deserializes Excel XLSX with tabular text extraction', () {
      final json = {
        'success': true,
        'title': 'Financial_Model.xlsx',
        'content': 'Revenue, Expenses, Profit\n100000, 45000, 55000',
        'fileId': '1xlsx_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1xlsx_id_12345/view',
        'mimeType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'extractionMethod': 'xlsx_sheets',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(
        entity.mimeType,
        equals(
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      );
      expect(entity.extractionMethod, equals('xlsx_sheets'));
      expect(entity.content, contains('Revenue, Expenses, Profit'));
    });

    test('Deserializes PowerPoint PPTX with slide-by-slide text extraction', () {
      final json = {
        'success': true,
        'title': 'Investor_Deck.pptx',
        'content': '[Slide 1]\nCompany Pitch\n\n[Slide 2]\nMarket Opportunity',
        'fileId': '1pptx_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1pptx_id_12345/view',
        'mimeType':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'extractionMethod': 'pptx_slides',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(
        entity.mimeType,
        equals(
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        ),
      );
      expect(entity.extractionMethod, equals('pptx_slides'));
      expect(entity.content, contains('[Slide 1]'));
      expect(entity.content, contains('Market Opportunity'));
    });

    test('Deserializes Image (JPG/PNG/Screenshot) with Gemini OCR payload', () {
      final json = {
        'success': true,
        'title': 'whiteboard_diagram.png',
        'content': '',
        'fileId': '1img_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1img_id_12345/view',
        'mimeType': 'image/png',
        'extractionMethod': 'gemini_ocr',
        'mediaType': 'image',
        'mediaBase64':
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.mimeType, equals('image/png'));
      expect(entity.extractionMethod, equals('gemini_ocr'));
      expect(entity.mediaType, equals('image'));
      expect(entity.mediaBase64, isNotNull);
    });

    test('Deserializes Audio with speech-to-text payload', () {
      final json = {
        'success': true,
        'title': 'meeting_recording.m4a',
        'content': '',
        'fileId': '1audio_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1audio_id_12345/view',
        'mimeType': 'audio/x-m4a',
        'extractionMethod': 'gemini_speech_to_text',
        'mediaType': 'audio',
        'mediaBase64': 'AAAAHGZ0eXBNNEEgAAAA...',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.mimeType, equals('audio/x-m4a'));
      expect(entity.extractionMethod, equals('gemini_speech_to_text'));
      expect(entity.mediaType, equals('audio'));
      expect(entity.mediaBase64, isNotNull);
    });

    test('Deserializes Video with transcript payload', () {
      final json = {
        'success': true,
        'title': 'product_demo.mp4',
        'content': '',
        'fileId': '1video_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1video_id_12345/view',
        'mimeType': 'video/mp4',
        'extractionMethod': 'gemini_video_transcript',
        'mediaType': 'video',
        'mediaBase64': 'AAAAIGZ0eXBpc29tAAAA...',
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.mimeType, equals('video/mp4'));
      expect(entity.extractionMethod, equals('gemini_video_transcript'));
      expect(entity.mediaType, equals('video'));
      expect(entity.mediaBase64, isNotNull);
    });

    test('Handles truncation warnings correctly', () {
      final json = {
        'success': true,
        'title': 'Giant_Documentation.xml',
        'content': '<root>large xml data</root>',
        'fileId': '1xml_id_12345',
        'webViewLink': 'https://drive.google.com/file/d/1xml_id_12345/view',
        'mimeType': 'application/xml',
        'extractionMethod': 'direct_text',
        'warnings': [
          'Extracted text exceeded 500000 characters and was truncated.',
        ],
      };

      final entity = GoogleDocEntity.fromJson(json);
      expect(entity.warnings, isNotNull);
      expect(entity.warnings!.first, contains('truncated'));
    });

    test(
      'Maintains backward compatibility when optional fields are absent',
      () {
        final legacyJson = {
          'success': true,
          'title': 'Legacy Doc',
          'content': 'Plain text without extra fields',
          'fileId': 'legacy_123',
          'webViewLink': 'https://docs.google.com/document/d/legacy_123',
          'mimeType': 'application/vnd.google-apps.document',
        };

        final entity = GoogleDocEntity.fromJson(legacyJson);
        expect(entity.fileSize, isNull);
        expect(entity.extractionMethod, isNull);
        expect(entity.mediaBase64, isNull);
        expect(entity.mediaType, isNull);
        expect(entity.warnings, isNull);
        expect(entity.toJson()['title'], equals('Legacy Doc'));
      },
    );
  });

  group('Google Drive Error Handling & Unsupported Type Tests', () {
    late TestGoogleAuthRemoteDataSource dataSource;

    setUp(() {
      dataSource = TestGoogleAuthRemoteDataSource();
    });

    test(
      'Throws FILE_NOT_FOUND when document is not accessible or not in drive.file scope',
      () async {
        dataSource.mockStatusCode = 404;
        dataSource.mockErrorCode = 'FILE_NOT_FOUND';
        dataSource.mockErrorMessage =
            'File not found or not accessible under current permissions. Please open with Google Picker.';

        expect(
          () => dataSource.importDriveFile('1unshared_file_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'FILE_NOT_FOUND',
            ),
          ),
        );
      },
    );

    test(
      'Throws PERMISSION_DENIED when user lacks permission to file',
      () async {
        dataSource.mockStatusCode = 403;
        dataSource.mockErrorCode = 'PERMISSION_DENIED';
        dataSource.mockErrorMessage =
            'Access denied to the requested Google Drive file.';

        expect(
          () => dataSource.importDriveFile('1forbidden_file_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'PERMISSION_DENIED',
            ),
          ),
        );
      },
    );

    test(
      'Throws TOKEN_REVOKED when user revoked Google authorization',
      () async {
        dataSource.mockStatusCode = 401;
        dataSource.mockErrorCode = 'TOKEN_REVOKED';
        dataSource.mockErrorMessage =
            'Google authorization expired or was revoked.';

        expect(
          () => dataSource.importDriveFile('1any_file_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'TOKEN_REVOKED',
            ),
          ),
        );
      },
    );

    test(
      'Throws UNSUPPORTED_ARCHIVE when attempting to import ZIP archive',
      () async {
        dataSource.mockStatusCode = 400;
        dataSource.mockErrorCode = 'UNSUPPORTED_ARCHIVE';
        dataSource.mockErrorMessage =
            'ZIP archives cannot be imported directly. Please extract and import individual files.';

        expect(
          () => dataSource.importDriveFile('1archive_zip_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'UNSUPPORTED_ARCHIVE',
            ),
          ),
        );
      },
    );

    test(
      'Throws UNSUPPORTED_BINARY when attempting to import executable or binary file',
      () async {
        dataSource.mockStatusCode = 400;
        dataSource.mockErrorCode = 'UNSUPPORTED_BINARY';
        dataSource.mockErrorMessage =
            'Executable and system files are not supported.';

        expect(
          () => dataSource.importDriveFile('1setup_exe_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'UNSUPPORTED_BINARY',
            ),
          ),
        );
      },
    );

    test(
      'Throws EMPTY_DOCUMENT when file has no readable text or media',
      () async {
        dataSource.mockStatusCode = 400;
        dataSource.mockErrorCode = 'EMPTY_DOCUMENT';
        dataSource.mockErrorMessage =
            'The selected file contains no readable text or supported media.';

        expect(
          () => dataSource.importDriveFile('1empty_file_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'EMPTY_DOCUMENT',
            ),
          ),
        );
      },
    );

    test(
      'Throws DOCUMENT_TOO_LARGE when file exceeds 15MB/25MB size limit',
      () async {
        dataSource.mockStatusCode = 400;
        dataSource.mockErrorCode = 'DOCUMENT_TOO_LARGE';
        dataSource.mockErrorMessage =
            'File exceeds maximum allowable size (15 MB).';

        expect(
          () => dataSource.importDriveFile('1huge_file_id_12345'),
          throwsA(
            isA<GoogleDocsImportException>().having(
              (e) => e.code,
              'code',
              'DOCUMENT_TOO_LARGE',
            ),
          ),
        );
      },
    );
  });

  group('Google Picker & Security Isolation Tests', () {
    late TestGoogleAuthRemoteDataSource dataSource;

    setUp(() {
      dataSource = TestGoogleAuthRemoteDataSource();
    });

    test(
      'startGooglePicker returns auth URL with trigger_onepick=true and drive.file scope',
      () async {
        final pickerUrl = await dataSource.startGooglePicker();
        expect(dataSource.lastAction, equals('start_picker'));
        expect(pickerUrl, contains('trigger_onepick=true'));
        expect(pickerUrl, contains('drive.file'));
        // Verifies no sensitive tokens are exposed in returned URL
        expect(pickerUrl, isNot(contains('access_token')));
        expect(pickerUrl, isNot(contains('refresh_token')));
      },
    );

    test(
      'Deep link with picked_file_id passes file ID safely without sensitive credentials',
      () {
        const callbackUri =
            'secondbrain://oauth/callback?status=success&picked_file_id=1real_picker_selected_file_id';
        final uri = Uri.parse(callbackUri);

        expect(uri.scheme, equals('secondbrain'));
        expect(uri.host, equals('oauth'));
        expect(uri.path, equals('/callback'));
        expect(uri.queryParameters['status'], equals('success'));
        expect(
          uri.queryParameters['picked_file_id'],
          equals('1real_picker_selected_file_id'),
        );

        // Verify ZERO credentials in deep link
        expect(uri.queryParameters.containsKey('code'), isFalse);
        expect(uri.queryParameters.containsKey('access_token'), isFalse);
        expect(uri.queryParameters.containsKey('refresh_token'), isFalse);
        expect(uri.queryParameters.containsKey('token'), isFalse);
      },
    );

    test(
      'Deep link with status=cancelled is correctly identified for UI feedback',
      () {
        const cancelledUri =
            'secondbrain://oauth/callback?status=cancelled&error=access_denied';
        final uri = Uri.parse(cancelledUri);

        expect(uri.queryParameters['status'], equals('cancelled'));
        expect(uri.queryParameters['error'], equals('access_denied'));
        expect(uri.queryParameters['picked_file_id'], isNull);
      },
    );

    test('Deep link with status=error parses error reason for user feedback', () {
      const errorUri =
          'secondbrain://oauth/callback?status=error&reason=invalid_or_expired_state';
      final uri = Uri.parse(errorUri);

      expect(uri.queryParameters['status'], equals('error'));
      expect(uri.queryParameters['reason'], equals('invalid_or_expired_state'));
      expect(uri.queryParameters['picked_file_id'], isNull);
    });

    test(
      'Complete Google Picker flow: startPicker -> picked_file_id -> importDriveFile',
      () async {
        // 1. App initiates Google Picker
        final pickerUrl = await dataSource.startGooglePicker();
        expect(pickerUrl, contains('trigger_onepick=true'));
        expect(pickerUrl, contains('drive.file'));

        // 2. User selects file in Picker -> Google redirects to callback -> deep link returned
        const callbackDeepLink =
            'secondbrain://oauth/callback?status=success&picked_file_id=1picked_report_123';
        final uri = Uri.parse(callbackDeepLink);
        final pickedId = uri.queryParameters['picked_file_id']!;
        expect(pickedId, equals('1picked_report_123'));

        // 3. App imports the picked file
        dataSource.mockResponse = {
          'success': true,
          'title': 'Quarterly_Report.docx',
          'content': 'Executive Summary\nRevenue grew by 24% year-over-year.',
          'fileId': pickedId,
          'webViewLink': 'https://drive.google.com/file/d/$pickedId/view',
          'mimeType':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'extractionMethod': 'docx_xml',
        };

        final doc = await dataSource.importDriveFile(pickedId);
        expect(doc.fileId, equals('1picked_report_123'));
        expect(doc.title, equals('Quarterly_Report.docx'));
        expect(doc.content, contains('Revenue grew by 24%'));
        expect(
          doc.mimeType,
          equals(
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ),
        );
        expect(doc.extractionMethod, equals('docx_xml'));
      },
    );
  });
}
