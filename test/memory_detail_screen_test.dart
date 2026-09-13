import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';

void main() {
  group('MemoryDetailScreen Widget Tests', () {
    testWidgets('renders memory details properly and toggles collapsible extracted content',
        (tester) async {
      final memory = MemoryEntity(
        id: 'test-id-123',
        userId: 'user-abc',
        title: 'Project Architecture Review',
        content: 'Reviewed the Clean Architecture and BLoC state management pipeline.',
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
      expect(find.text('See what was extracted from your memory'), findsOneWidget);

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
        find.text('Reviewed the Clean Architecture and BLoC state management pipeline.'),
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

      // Verify living memory / AI metadata section is present
      expect(find.text('Living Memory Knowledge Graph'), findsOneWidget);
      expect(find.text('AI Metadata & Semantic Engine'), findsOneWidget);
    });

    testWidgets('collapses extracted content back when Hide extracted text is tapped',
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
    });

    testWidgets('formats raw OCR text cleanly without word fragments like effec and ant',
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

      final selectableTextWidget = tester.widget<SelectableText>(selectableTextFinder);
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
      expect(displayedText.contains('• Force is proportional to acceleration'), isTrue);
      expect(displayedText.contains('F = ma'), isTrue);

      // 4. Verify typography: 15.5px body text with ~1.55 line height
      expect(selectableTextWidget.style?.fontSize, equals(15.5));
      expect(selectableTextWidget.style?.height, equals(1.55));
    });

    testWidgets('does not render Extracted Content section when content is empty',
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
    });

    testWidgets('does not render Extracted Content section when content is a pure URL',
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
    });

    testWidgets('renders AI Summary card above Extracted Content when initialSummary is provided',
        (tester) async {
      final memory = MemoryEntity(
        id: 'summary-test-id',
        userId: 'user-ai',
        title: 'Quantum Computing Overview',
        content: 'Superposition and entanglement enable exponential speedups for specific algorithms.',
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
            initialSummary: 'Concise summary of quantum superposition principles.',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify AI Summary is displayed
      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text('Concise summary of quantum superposition principles.'), findsOneWidget);

      // Verify Extracted Content is also displayed below it
      expect(find.text('Extracted Content'), findsOneWidget);
      expect(find.text('View extracted text'), findsOneWidget);
    });

    testWidgets('renders very long text content smoothly without overflow or clipping',
        (tester) async {
      final longText = List.generate(
        40,
        (i) => 'Paragraph $i: Classical mechanics deals with the motion of bodies under the influence of forces.',
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
    });

    testWidgets('renders friendly Memory Not Found state when memory cannot be found',
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
        find.text('This thought or note may have been removed or deleted from your Second Brain.'),
        findsOneWidget,
      );
      expect(find.text('Back to Home'), findsOneWidget);
    });
  });
}
