import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/services/ocr_text_normalizer.dart';

void main() {
  group('OcrTextNormalizer — Regression & Geometry Reconstruction Tests', () {
    test(
      'reconstructs keyboard layout from chaotic / column-first ML Kit fragments',
      () {
        // Replicates the exact user issue:
        // ML Kit extracts individual key tokens in column-first order, flattening them into
        // one token per line:
        // F2, s Lock, Shift, 4, F3, Ctrl, F4, W, F5, Fn, Latitude
        final fragments = [
          const OcrLineFragment(
            text: 'F2',
            boundingBox: Rect.fromLTWH(50, 50, 40, 20),
          ),
          const OcrLineFragment(
            text: 's Lock',
            boundingBox: Rect.fromLTWH(50, 230, 60, 20),
          ),
          const OcrLineFragment(
            text: 'Shift',
            boundingBox: Rect.fromLTWH(50, 290, 60, 20),
          ),
          const OcrLineFragment(
            text: '4',
            boundingBox: Rect.fromLTWH(170, 110, 20, 20),
          ),
          const OcrLineFragment(
            text: 'F3',
            boundingBox: Rect.fromLTWH(150, 50, 40, 20),
          ),
          const OcrLineFragment(
            text: 'Ctrl',
            boundingBox: Rect.fromLTWH(50, 350, 50, 20),
          ),
          const OcrLineFragment(
            text: 'F4',
            boundingBox: Rect.fromLTWH(250, 50, 40, 20),
          ),
          const OcrLineFragment(
            text: 'W',
            boundingBox: Rect.fromLTWH(170, 170, 30, 20),
          ),
          const OcrLineFragment(
            text: 'F5',
            boundingBox: Rect.fromLTWH(350, 50, 40, 20),
          ),
          const OcrLineFragment(
            text: 'Fn',
            boundingBox: Rect.fromLTWH(120, 350, 30, 20),
          ),
          const OcrLineFragment(
            text: 'Latitude',
            boundingBox: Rect.fromLTWH(300, 410, 100, 20),
          ),
        ];

        final result = OcrTextNormalizer.reconstructFromFragments(fragments);

        // 1. Keys on the function row are unified in left-to-right reading order
        expect(result, contains('F2 F3 F4 F5'));

        // 2. Keys on the bottom row are unified in left-to-right reading order
        expect(result, contains('Ctrl Fn'));

        // 3. Top-to-bottom spatial order is preserved
        final lines = result
            .split(RegExp(r'\n+'))
            .map((l) => l.trim())
            .toList();
        expect(lines, [
          'F2 F3 F4 F5',
          '4',
          'W',
          's Lock',
          'Shift',
          'Ctrl Fn',
          'Latitude',
        ]);

        // 4. Words are not flattened into one-token-per-line
        expect(lines.length, 7); // 7 rows instead of 11 flattened lines
      },
    );

    test(
      'preserves structured document with natural line and paragraph breaks',
      () {
        final fragments = [
          // Paragraph 1 (line height: 20, line gap: 6)
          const OcrLineFragment(
            text: 'Second Brain is an intelligent note-taking application.',
            boundingBox: Rect.fromLTWH(30, 50, 350, 20),
          ),
          const OcrLineFragment(
            text: 'It captures photos, documents, and links seamlessly.',
            boundingBox: Rect.fromLTWH(30, 76, 340, 20),
          ),
          // Paragraph 2 (gap = 140 - 96 = 44px > 1.8 * 20)
          const OcrLineFragment(
            text: 'Key features include offline search and vector embeddings.',
            boundingBox: Rect.fromLTWH(30, 140, 360, 20),
          ),
          const OcrLineFragment(
            text: 'Everything is synced securely to your private database.',
            boundingBox: Rect.fromLTWH(30, 166, 350, 20),
          ),
        ];

        final result = OcrTextNormalizer.reconstructFromFragments(fragments);

        // Paragraphs are separated by double newline
        expect(result, contains('seamlessly.\n\nKey features'));

        // Lines within the same paragraph are separated by single newline
        expect(result, contains('application.\nIt captures'));
        expect(result, contains('embeddings.\nEverything is'));
      },
    );

    test('reconstructs multi-column tabular / receipt layout correctly', () {
      final fragments = [
        // Scrambled column-first order (common ML Kit behavior)
        const OcrLineFragment(
          text: 'Item',
          boundingBox: Rect.fromLTWH(20, 30, 60, 18),
        ),
        const OcrLineFragment(
          text: 'Coffee',
          boundingBox: Rect.fromLTWH(20, 60, 60, 18),
        ),
        const OcrLineFragment(
          text: 'Muffin',
          boundingBox: Rect.fromLTWH(20, 90, 60, 18),
        ),
        const OcrLineFragment(
          text: 'Qty',
          boundingBox: Rect.fromLTWH(120, 30, 40, 18),
        ),
        const OcrLineFragment(
          text: '1',
          boundingBox: Rect.fromLTWH(120, 60, 20, 18),
        ),
        const OcrLineFragment(
          text: '2',
          boundingBox: Rect.fromLTWH(120, 90, 20, 18),
        ),
        const OcrLineFragment(
          text: 'Price',
          boundingBox: Rect.fromLTWH(200, 30, 50, 18),
        ),
        const OcrLineFragment(
          text: r'$4.50',
          boundingBox: Rect.fromLTWH(200, 60, 50, 18),
        ),
        const OcrLineFragment(
          text: r'$6.00',
          boundingBox: Rect.fromLTWH(200, 90, 50, 18),
        ),
      ];

      final result = OcrTextNormalizer.reconstructFromFragments(fragments);
      final lines = result.split(RegExp(r'\n+')).map((l) => l.trim()).toList();

      expect(lines, ['Item Qty Price', r'Coffee 1 $4.50', r'Muffin 2 $6.00']);
    });

    test(
      'preserves raw text when geometry is insufficient or bounding boxes are zero',
      () {
        const rawText = 'Line 1 without geometry\nLine 2 without geometry';
        final fragments = [
          const OcrLineFragment(
            text: 'Line 1 without geometry',
            boundingBox: Rect.zero,
          ),
          const OcrLineFragment(
            text: 'Line 2 without geometry',
            boundingBox: Rect.zero,
          ),
        ];

        final result = OcrTextNormalizer.reconstructFromFragments(
          fragments,
          fallbackRawText: rawText,
        );

        expect(result, rawText);
      },
    );

    test('empty input returns empty string', () {
      expect(OcrTextNormalizer.reconstructFromFragments([]), '');
      expect(OcrTextNormalizer.normalizeRawText(''), '');
      expect(OcrTextNormalizer.normalizeRawText('   \n  \n  '), '');
    });

    test('never hallucinates or alters original text tokens', () {
      final fragments = [
        const OcrLineFragment(
          text: 'Special#Token_123',
          boundingBox: Rect.fromLTWH(10, 10, 80, 20),
        ),
        const OcrLineFragment(
          text: 'Another@Token!',
          boundingBox: Rect.fromLTWH(100, 10, 80, 20),
        ),
      ];

      final result = OcrTextNormalizer.reconstructFromFragments(fragments);

      expect(result, 'Special#Token_123 Another@Token!');
    });
  });
}
