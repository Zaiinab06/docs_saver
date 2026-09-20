import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Represents a single OCR text fragment with its 2D spatial bounding box.
class OcrLineFragment {
  final String text;
  final Rect boundingBox;

  const OcrLineFragment({
    required this.text,
    required this.boundingBox,
  });
}

/// Normalizes and reconstructs natural line and paragraph structure from
/// 2D OCR geometry (e.g. Google ML Kit [RecognizedText]), preventing
/// awkward one-token-per-line flattening and preserving natural reading order.
class OcrTextNormalizer {
  /// Normalizes and reconstructs text from a Google ML Kit [RecognizedText] object.
  ///
  /// If geometry is missing or insufficient, gracefully falls back to [recognizedText.text].
  static String normalizeRecognizedText(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) {
      return normalizeRawText(recognizedText.text);
    }

    final fragments = <OcrLineFragment>[];
    for (final block in recognizedText.blocks) {
      if (block.lines.isNotEmpty) {
        for (final line in block.lines) {
          final trimmed = line.text.trim();
          if (trimmed.isNotEmpty) {
            fragments.add(OcrLineFragment(
              text: trimmed,
              boundingBox: line.boundingBox,
            ));
          }
        }
      } else {
        final trimmed = block.text.trim();
        if (trimmed.isNotEmpty) {
          fragments.add(OcrLineFragment(
            text: trimmed,
            boundingBox: block.boundingBox,
          ));
        }
      }
    }

    if (fragments.isEmpty) {
      return normalizeRawText(recognizedText.text);
    }

    return reconstructFromFragments(fragments, fallbackRawText: recognizedText.text);
  }

  /// Reconstructs natural reading order and spatial structure from [OcrLineFragment]s.
  ///
  /// - Clusters fragments into horizontal lines (rows) based on vertical overlap.
  /// - Sorts fragments within each line from left to right.
  /// - Sorts lines from top to bottom.
  /// - Inserts natural line breaks (`\n`) within sections and paragraph breaks (`\n\n`)
  ///   where vertical gap exceeds typical line height.
  /// - Preserves raw text if bounding box geometry is zero or insufficient.
  static String reconstructFromFragments(
    List<OcrLineFragment> fragments, {
    String? fallbackRawText,
  }) {
    if (fragments.isEmpty) {
      return fallbackRawText != null ? normalizeRawText(fallbackRawText) : '';
    }

    // Check if geometry is valid (non-zero bounding boxes)
    final hasValidGeometry = fragments.any((f) =>
        f.boundingBox.width > 0 && f.boundingBox.height > 0);

    if (!hasValidGeometry) {
      if (fallbackRawText != null && fallbackRawText.trim().isNotEmpty) {
        return normalizeRawText(fallbackRawText);
      }
      return fragments.map((f) => f.text.trim()).where((t) => t.isNotEmpty).join('\n');
    }

    // Sort fragments initially by top, then by left
    final sortedFragments = List<OcrLineFragment>.from(fragments)
      ..sort((a, b) {
        final topComparison = a.boundingBox.top.compareTo(b.boundingBox.top);
        if (topComparison != 0) return topComparison;
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });

    // Cluster fragments into horizontal rows
    final rows = <_ReconstructedRow>[];

    for (final fragment in sortedFragments) {
      _ReconstructedRow? bestRow;
      double bestOverlap = 0;

      for (final row in rows) {
        final fBox = fragment.boundingBox;
        final overlapTop = math.max(row.top, fBox.top);
        final overlapBottom = math.min(row.bottom, fBox.bottom);
        final overlap = math.max(0.0, overlapBottom - overlapTop);
        final minHeight = math.min(row.height, fBox.height);

        if (minHeight > 0) {
          final overlapRatio = overlap / minHeight;
          final centerDiff =
              (row.verticalCenter - (fBox.top + fBox.bottom) / 2).abs();

          if (overlapRatio >= 0.45 ||
              (overlapRatio >= 0.25 && centerDiff <= minHeight * 0.4)) {
            if (overlap > bestOverlap) {
              bestOverlap = overlap;
              bestRow = row;
            }
          }
        }
      }

      if (bestRow != null) {
        bestRow.add(fragment);
      } else {
        rows.add(_ReconstructedRow(fragment));
      }
    }

    // Sort rows from top to bottom
    rows.sort((a, b) => a.top.compareTo(b.top));

    // Sort items within each row from left to right
    for (final row in rows) {
      row.items.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }

    // Construct text for each row
    final rowTexts = <String>[];
    final rowBounds = <_ReconstructedRow>[];

    for (final row in rows) {
      final joined = row.items
          .map((i) => i.text.trim())
          .where((t) => t.isNotEmpty)
          .join(' ');
      if (joined.isNotEmpty) {
        rowTexts.add(joined);
        rowBounds.add(row);
      }
    }

    if (rowTexts.isEmpty) {
      return fallbackRawText != null ? normalizeRawText(fallbackRawText) : '';
    }

    // Join rows with line breaks or paragraph breaks based on vertical spacing
    final buffer = StringBuffer();
    for (int i = 0; i < rowTexts.length; i++) {
      if (i > 0) {
        final prevRow = rowBounds[i - 1];
        final currRow = rowBounds[i];
        final verticalGap = currRow.top - prevRow.bottom;
        final avgHeight = (prevRow.height + currRow.height) / 2;

        if (avgHeight > 0 && verticalGap > avgHeight * 1.8) {
          buffer.write('\n\n');
        } else {
          buffer.write('\n');
        }
      }
      buffer.write(rowTexts[i]);
    }

    return buffer.toString().trim();
  }

  /// Cleans and normalizes raw text without hallucinating or modifying words.
  static String normalizeRawText(String text) {
    if (text.trim().isEmpty) return '';

    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .toList();

    final buffer = StringBuffer();
    int consecutiveEmptyLines = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) {
        consecutiveEmptyLines++;
        if (consecutiveEmptyLines <= 1 && buffer.isNotEmpty) {
          buffer.write('\n');
        }
      } else {
        consecutiveEmptyLines = 0;
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write('\n');
        }
        buffer.write(line);
      }
    }

    return buffer.toString().trim();
  }
}

class _ReconstructedRow {
  final List<OcrLineFragment> items = [];
  double top;
  double bottom;

  _ReconstructedRow(OcrLineFragment initial)
      : top = initial.boundingBox.top,
        bottom = initial.boundingBox.bottom {
    items.add(initial);
  }

  double get height => math.max(1.0, bottom - top);
  double get verticalCenter => (top + bottom) / 2;

  void add(OcrLineFragment fragment) {
    items.add(fragment);
    if (fragment.boundingBox.top < top) top = fragment.boundingBox.top;
    if (fragment.boundingBox.bottom > bottom) bottom = fragment.boundingBox.bottom;
  }
}
