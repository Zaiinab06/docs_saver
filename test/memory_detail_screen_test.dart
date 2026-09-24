import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/capture/presentation/widgets/full_screen_image_viewer.dart';
import 'package:second_brain/features/capture/presentation/widgets/video_player_preview_card.dart';

void main() {
  group('MemoryDetailScreen Widget Tests', () {
    testWidgets(
      'renders memory details properly and toggles collapsible extracted content',
      (tester) async {
        final memory = MemoryEntity(
          id: 'test-id-123',
          userId: 'user-abc',
          title: 'Project Architecture Review',
          content:
              'Reviewed the Clean Architecture and BLoC state management pipeline.',
          category: 'Work',
          tags: const ['flutter', 'architecture', 'bloc'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 10, 30),
          clientUpdatedAt: DateTime(2026, 9, 13, 10, 30),
          serverUpdatedAt: DateTime(2026, 9, 13, 10, 30),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        // Verify title is rendered
        expect(find.text('Project Architecture Review'), findsOneWidget);

        // Verify section heading & subtitle
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(
          find.text('See what was extracted from your memory'),
          findsOneWidget,
        );

        // Collapsed by default: "View extracted text" is visible, full SelectableText is not
        expect(find.text('View extracted text'), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);

        // Tap to expand
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        // Expanded state: "Hide extracted text" and SelectableText are now visible
        expect(find.text('Hide extracted text'), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);
        expect(
          find.text(
            'Reviewed the Clean Architecture and BLoC state management pipeline.',
          ),
          findsOneWidget,
        );

        // Verify category is rendered
        expect(find.text('Work'), findsAtLeastNWidgets(1));

        // Verify AI status is rendered
        expect(find.text('AI Organized'), findsOneWidget);

        // Verify tags are rendered
        expect(find.text('#flutter'), findsOneWidget);
        expect(find.text('#architecture'), findsOneWidget);
        expect(find.text('#bloc'), findsOneWidget);

        // Verify living memory card is removed, and user-facing AI metadata engine card is removed
        expect(find.text('Living Memory Knowledge Graph'), findsNothing);
        expect(find.text('AI Metadata & Semantic Engine'), findsNothing);
      },
    );

    testWidgets(
      'collapses extracted content back when Hide extracted text is tapped',
      (tester) async {
        final memory = MemoryEntity(
          id: 'toggle-test-id',
          userId: 'user-xyz',
          title: 'Meeting Highlights',
          content: 'Action items and roadmap review for Q4.',
          category: 'Work',
          tags: const ['roadmap'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 10, 30),
          clientUpdatedAt: DateTime(2026, 9, 13, 10, 30),
          serverUpdatedAt: DateTime(2026, 9, 13, 10, 30),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        // Expand
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();
        expect(find.text('Hide extracted text'), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);

        // Collapse back
        await tester.tap(find.text('Hide extracted text'));
        await tester.pumpAndSettle();
        expect(find.text('View extracted text'), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);
      },
    );

    testWidgets(
      'formats raw OCR text cleanly without word fragments like effec and ant',
      (tester) async {
        // Raw OCR text with typical textbook line breaks and hyphenated words
        const rawPhysicsOcr = '''
Newton's second law of motion is an import-
ant principle in mechanics. The effec-
tive gravitational force acting on a body determines its acceler-
ation and result-
ant trajectory.

Key Principles:
• Force is proportional to acceleration
• Mass resists acceleration
F = ma''';

        final memory = MemoryEntity(
          id: 'physics-notes-101',
          userId: 'student-1',
          title: 'Physics Mechanics Notes',
          content: rawPhysicsOcr,
          category: 'Study',
          tags: const ['physics', 'mechanics', 'newton'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 11, 0),
          clientUpdatedAt: DateTime(2026, 9, 13, 11, 0),
          serverUpdatedAt: DateTime(2026, 9, 13, 11, 0),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Expand the card to inspect formatted text
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        // Find the reading card with the formatted text
        final selectableTextFinder = find.byType(SelectableText);
        expect(selectableTextFinder, findsOneWidget);

        final selectableTextWidget = tester.widget<SelectableText>(
          selectableTextFinder,
        );
        final displayedText = selectableTextWidget.data!;

        // 1. Verify that hyphenated fragments like "effec-" and "ant" are NOT present
        expect(displayedText.contains('effec-\n'), isFalse);
        expect(displayedText.contains('import-\n'), isFalse);
        expect(displayedText.contains('result-\n'), isFalse);

        // 2. Verify that the words are properly unified into complete words
        expect(displayedText.contains('effective'), isTrue);
        expect(displayedText.contains('important'), isTrue);
        expect(displayedText.contains('resultant'), isTrue);
        expect(displayedText.contains('acceleration'), isTrue);

        // 3. Verify bullets and formulas are preserved
        expect(
          displayedText.contains('• Force is proportional to acceleration'),
          isTrue,
        );
        expect(displayedText.contains('F = ma'), isTrue);

        // 4. Verify typography: 15.5px body text with ~1.55 line height
        expect(selectableTextWidget.style?.fontSize, equals(15.5));
        expect(selectableTextWidget.style?.height, equals(1.55));
      },
    );

    testWidgets(
      'does not render Extracted Content section when content is empty',
      (tester) async {
        final memory = MemoryEntity(
          id: 'empty-content-id',
          userId: 'user-empty',
          title: 'Empty Photo Memory',
          content: '',
          category: 'Personal',
          tags: const ['photo'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 10, 30),
          clientUpdatedAt: DateTime(2026, 9, 13, 10, 30),
          serverUpdatedAt: DateTime(2026, 9, 13, 10, 30),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Extracted Content'), findsNothing);
        expect(find.text('View extracted text'), findsNothing);
      },
    );

    testWidgets(
      'does not render Extracted Content section when content is a pure URL',
      (tester) async {
        final memory = MemoryEntity(
          id: 'url-memory-id',
          userId: 'user-web',
          title: 'Flutter Documentation',
          content: 'https://flutter.dev/docs',
          category: 'Study',
          tags: const ['link'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 10, 30),
          clientUpdatedAt: DateTime(2026, 9, 13, 10, 30),
          serverUpdatedAt: DateTime(2026, 9, 13, 10, 30),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Pure URL is rendered in the link action banner
        expect(find.text('https://flutter.dev/docs'), findsOneWidget);
        // Extracted Content card should not duplicate the single URL awkwardly
        expect(find.text('Extracted Content'), findsNothing);
        expect(find.text('View extracted text'), findsNothing);
      },
    );

    testWidgets(
      'renders AI Summary card above Extracted Content when initialSummary is provided',
      (tester) async {
        final memory = MemoryEntity(
          id: 'summary-test-id',
          userId: 'user-ai',
          title: 'Quantum Computing Overview',
          content:
              'Superposition and entanglement enable exponential speedups for specific algorithms.',
          category: 'Study',
          tags: const ['quantum', 'computing'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 10, 30),
          clientUpdatedAt: DateTime(2026, 9, 13, 10, 30),
          serverUpdatedAt: DateTime(2026, 9, 13, 10, 30),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
              initialSummary:
                  'Concise summary of quantum superposition principles.',
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify AI Summary is displayed
        expect(find.text('AI Summary'), findsOneWidget);
        expect(
          find.text('Concise summary of quantum superposition principles.'),
          findsOneWidget,
        );

        // Verify Extracted Content is also displayed below it
        expect(find.text('Extracted Content'), findsOneWidget);
        expect(find.text('View extracted text'), findsOneWidget);
      },
    );

    testWidgets(
      'renders very long text content smoothly without overflow or clipping',
      (tester) async {
        final longText = List.generate(
          40,
          (i) =>
              'Paragraph $i: Classical mechanics deals with the motion of bodies under the influence of forces.',
        ).join('\n\n');

        final memory = MemoryEntity(
          id: 'long-content-id',
          userId: 'user-long',
          title: 'Comprehensive Physics Treatise',
          content: longText,
          category: 'Study',
          tags: const ['physics'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 13, 11, 0),
          clientUpdatedAt: DateTime(2026, 9, 13, 11, 0),
          serverUpdatedAt: DateTime(2026, 9, 13, 11, 0),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify header exists
        expect(find.text('Extracted Content'), findsOneWidget);

        // Expand to view full long text
        await tester.tap(find.text('View extracted text'));
        await tester.pumpAndSettle();

        expect(find.byType(SelectableText), findsOneWidget);

        // Verify no RenderFlex overflow happened
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders friendly Memory Not Found state when memory cannot be found',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: MemoryDetailScreen(
              memoryId: 'non-existent-memory-id',
              initialMemory: null,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Memory Not Found'), findsOneWidget);
        expect(
          find.text(
            'This thought or note may have been removed or deleted from your Second Brain.',
          ),
          findsOneWidget,
        );
        expect(find.text('Back to Home'), findsOneWidget);
      },
    );

    testWidgets(
      'verifies exact layout order: Extracted Content -> Tags (last) with Knowledge Graph removed',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final memory = MemoryEntity(
          id: 'order-test-id',
          userId: 'user-order',
          title: 'Layout Order Verification Memory',
          content: 'Extracted OCR text body from the camera snapshot.',
          category: 'Work',
          tags: const ['strategy', 'roadmap'],
          aiStatus: 'processed',
          clientCreatedAt: DateTime(2026, 9, 14, 14, 0),
          clientUpdatedAt: DateTime(2026, 9, 14, 14, 0),
          serverUpdatedAt: DateTime(2026, 9, 14, 14, 0),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify Extracted Content is present
        final extractedContentFinder = find.text('Extracted Content');
        expect(extractedContentFinder, findsOneWidget);

        // 2. Verify Living Memory Knowledge Graph is completely removed
        expect(find.text('Living Memory Knowledge Graph'), findsNothing);
        expect(find.text('Category & Topic relationships'), findsNothing);
        expect(find.text('CATEGORY'), findsNothing);
        expect(find.text('TOPIC'), findsNothing);

        // 3. Verify Tags section is inside its own card and ALWAYS EXPANDED (no collapse control)
        final tagsHeaderFinder = find.text('Tags');
        expect(tagsHeaderFinder, findsOneWidget);
        expect(find.text('Associated memory tags'), findsOneWidget);

        // Tags are immediately visible by default
        expect(find.text('#strategy'), findsOneWidget);
        expect(find.text('#roadmap'), findsOneWidget);

        // Tapping Tags header does NOT collapse tags (no open/close control or chevron)
        await tester.tap(tagsHeaderFinder);
        await tester.pumpAndSettle();
        expect(find.text('#strategy'), findsOneWidget);
        expect(find.text('#roadmap'), findsOneWidget);

        // 4. Verify AI Metadata & Semantic Engine card is completely removed
        expect(find.text('AI Metadata & Semantic Engine'), findsNothing);
        expect(find.text('Vector Embeddings: '), findsNothing);

        // 5. Verify the exact vertical layout ordering: Extracted Content -> Tags (last)
        final extractedY = tester.getTopLeft(extractedContentFinder).dy;
        final tagsY = tester.getTopLeft(tagsHeaderFinder).dy;

        expect(
          extractedY < tagsY,
          isTrue,
          reason: 'Extracted Content must appear above Tags',
        );
      },
    );

    testWidgets(
      'displays image preview for image attachment and tapping opens FullScreenImageViewer',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('img_test_');
        final imageFile = File('${tempDir.path}/sample.jpg')
          ..writeAsBytesSync([
            0xFF,
            0xD8,
            0xFF,
            0xE0,
            0x00,
            0x10,
            0x4A,
            0x46,
            0x49,
            0x46,
          ]);
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final memory = MemoryEntity(
          id: 'image-memory-1',
          userId: 'user-1',
          title: 'Meeting Whiteboard Photo',
          content: 'Whiteboard notes from brainstorming',
          category: 'Work',
          tags: const ['photo', 'meeting'],
          mediaUrl: imageFile.path,
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Image widget is rendered
        expect(find.byType(Image), findsOneWidget);

        // Tap image to open full-screen viewer
        await tester.tap(find.byType(Image), warnIfMissed: false);
        await tester.pumpAndSettle();

        // FullScreenImageViewer is pushed
        expect(find.byType(FullScreenImageViewer), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.text('Meeting Whiteboard Photo'), findsOneWidget);

        // Tap back button
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Back to MemoryDetailScreen
        expect(find.byType(FullScreenImageViewer), findsNothing);
        expect(find.byType(MemoryDetailScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Take Photo image renders full-width without empty side space and expand button opens viewer',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('take_photo_img_');
        final imageFile = File('${tempDir.path}/camera_photo.jpg')
          ..writeAsBytesSync([
            0xFF,
            0xD8,
            0xFF,
            0xE0,
            0x00,
            0x10,
            0x4A,
            0x46,
            0x49,
            0x46,
          ]);
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final memory = MemoryEntity(
          id: 'take-photo-1',
          userId: 'user-1',
          title: 'Whiteboard Discussion',
          content: 'Sprint planning notes on whiteboard',
          category: 'Work',
          tags: const ['photo'],
          mediaUrl: imageFile.path,
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Image is rendered with full width and BoxFit.cover
        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);
        final imageWidget = tester.widget<Image>(imageFinder);
        expect(imageWidget.width, double.infinity);
        expect(imageWidget.height, 220);
        expect(imageWidget.fit, BoxFit.cover);

        // 2. Expand/fullscreen icon button is visible
        final expandButton = find.byIcon(Icons.fullscreen_rounded);
        expect(expandButton, findsOneWidget);

        // 3. Tapping the expand button opens the full-screen viewer
        await tester.tap(expandButton);
        await tester.pumpAndSettle();

        expect(find.byType(FullScreenImageViewer), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.text('Whiteboard Discussion'), findsOneWidget);
      },
    );

    testWidgets(
      'document memory with image attachment displays image file card with View Image button',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('img_doc_test_');
        final imageFile = File('${tempDir.path}/receipt_scan.png')
          ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final memory = MemoryEntity(
          id: 'doc-img-memory-2',
          userId: 'user-1',
          title: 'Dinner Receipt',
          content: 'Dinner with client at Bistro',
          category: 'Finance',
          tags: const ['document', 'receipt'],
          mediaUrl: imageFile.path,
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Renders file name and PNG badge
        expect(find.text('receipt_scan.png'), findsOneWidget);
        expect(find.text('PNG'), findsOneWidget);

        // Must have "View Image" button, NOT "Open File"
        expect(find.text('View Image'), findsOneWidget);
        expect(find.text('Open File'), findsNothing);

        // Tap "View Image" button
        await tester.tap(find.text('View Image'));
        await tester.pumpAndSettle();

        // Opens FullScreenImageViewer
        expect(find.byType(FullScreenImageViewer), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
      },
    );

    testWidgets(
      'document memory with non-image PDF preserves Open File button and does not render as image',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('pdf_doc_test_');
        final pdfFile = File('${tempDir.path}/contract.pdf')
          ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final memory = MemoryEntity(
          id: 'pdf-memory-3',
          userId: 'user-1',
          title: 'Service Agreement',
          content: 'Contract terms and conditions',
          category: 'Work',
          tags: const ['document', 'contract'],
          mediaUrl: pdfFile.path,
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // PDF card
        expect(find.text('contract.pdf'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);
        expect(find.text('Open File'), findsOneWidget);
        expect(find.text('View Image'), findsNothing);
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets('missing image file displays fallback gracefully', (
      tester,
    ) async {
      final memory = MemoryEntity(
        id: 'missing-img-memory-4',
        userId: 'user-1',
        title: 'Deleted Photo',
        content: 'Photo was removed from storage',
        category: 'Personal',
        tags: const ['photo'],
        mediaUrl: '/non/existent/path/missing_image.jpg',
        aiStatus: 'processed',
        clientCreatedAt: DateTime.now(),
        clientUpdatedAt: DateTime.now(),
        serverUpdatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MemoryDetailScreen(memoryId: memory.id, initialMemory: memory),
        ),
      );
      await tester.pumpAndSettle();

      // Graceful fallback icon
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });

    testWidgets(
      'video memory renders VideoPlayerPreviewCard and does not render Image widget',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('vid_test_');
        final videoFile = File('${tempDir.path}/sample_demo.mp4')
          ..writeAsBytesSync([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final memory = MemoryEntity(
          id: 'video-memory-1',
          userId: 'user-1',
          title: 'Product Walkthrough Video',
          content: 'Recorded demonstration of the new feature set.',
          category: 'Work',
          tags: const ['video', 'walkthrough'],
          mediaUrl: videoFile.path,
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify VideoPlayerPreviewCard is rendered
        expect(find.byType(VideoPlayerPreviewCard), findsOneWidget);

        // 2. Verify standard Image widget is NEVER called for video files
        expect(find.byType(Image), findsNothing);

        // 3. Verify video title & badge
        expect(find.text('Product Walkthrough Video'), findsAtLeastNWidgets(1));
        expect(find.text('VIDEO'), findsOneWidget);

        // 4. Verify Extracted Content displays video-specific title & icon
        expect(find.text('Video Analysis & Key Events'), findsOneWidget);
        expect(
          find.text('Scene description & speech extracted from video'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.videocam_rounded), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'remote video URL (.mov) renders VideoPlayerPreviewCard without calling Image preview',
      (tester) async {
        final memory = MemoryEntity(
          id: 'remote-video-memory-2',
          userId: 'user-1',
          title: 'Design Critique Clip',
          content: 'Critique of the mobile navigation patterns.',
          category: 'Work',
          tags: const ['critique'],
          mediaUrl: 'https://example.supabase.co/storage/v1/object/public/memories/critique.mov',
          aiStatus: 'processed',
          clientCreatedAt: DateTime.now(),
          clientUpdatedAt: DateTime.now(),
          serverUpdatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MemoryDetailScreen(
              memoryId: memory.id,
              initialMemory: memory,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify VideoPlayerPreviewCard is rendered
        expect(find.byType(VideoPlayerPreviewCard), findsOneWidget);

        // 2. Verify Image widget is not used for .mov video files
        expect(find.byType(Image), findsNothing);
      },
    );
  });
}
