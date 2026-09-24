import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

/// Service for extracting representative JPEG frames from video recordings.
/// Used by the client-side Gemini Vision pipeline to analyze video scenes without
/// transferring multi-megabyte video streams.
class VideoFrameExtractor {
  /// Extracts a representative JPEG frame (default 1000ms, fallback to 0ms) from [videoPath].
  /// Returns raw JPEG bytes, or null if extraction fails.
  static Future<Uint8List?> extractRepresentativeFrame(
    String videoPath, {
    int timeMs = 1000,
    int quality = 85,
    int maxWidth = 1280,
  }) async {
    try {
      final file = File(videoPath);
      if (!file.existsSync()) {
        debugPrint('[VideoFrameExtractor] Video file not found at: $videoPath');
        return null;
      }

      // Try extraction at timeMs (1000ms = 1s into video) to avoid black warmup frames
      Uint8List? frameBytes;
      try {
        frameBytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxWidth,
          quality: quality,
          timeMs: timeMs,
        );
      } catch (e) {
        debugPrint('[VideoFrameExtractor] Extraction at ${timeMs}ms failed: $e');
      }

      // If null or empty (e.g. video shorter than 1s), fallback to 0ms (first frame)
      if (frameBytes == null || frameBytes.isEmpty) {
        try {
          frameBytes = await VideoThumbnail.thumbnailData(
            video: videoPath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: maxWidth,
            quality: quality,
            timeMs: 0,
          );
        } catch (e) {
          debugPrint('[VideoFrameExtractor] Fallback extraction at 0ms failed: $e');
        }
      }

      if (frameBytes != null && frameBytes.isNotEmpty) {
        debugPrint(
          '[VideoFrameExtractor] Frame successfully extracted (${frameBytes.lengthInBytes} bytes) from $videoPath',
        );
        return frameBytes;
      }
    } catch (e, stack) {
      debugPrint('[VideoFrameExtractor] Unexpected extraction error: $e\n$stack');
    }
    return null;
  }

  /// Extracts 1 to 3 representative frames (e.g., at 500ms, 1500ms, 3000ms).
  static Future<List<Uint8List>> extractRepresentativeFrames(
    String videoPath, {
    List<int> timeOffsetsMs = const [500, 1500, 3000],
    int quality = 80,
    int maxWidth = 1024,
  }) async {
    final List<Uint8List> frames = [];
    for (final timeMs in timeOffsetsMs) {
      try {
        final frame = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxWidth,
          quality: quality,
          timeMs: timeMs,
        );
        if (frame.isNotEmpty) {
          frames.add(frame);
        }
      } catch (_) {}
    }

    if (frames.isEmpty) {
      final single = await extractRepresentativeFrame(videoPath);
      if (single != null) {
        frames.add(single);
      }
    }
    return frames;
  }

  /// Saves extracted frame bytes to a temporary JPEG thumbnail file on disk.
  static Future<File?> saveThumbnailToFile(
    String videoPath,
    Uint8List frameBytes,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final videoName = File(videoPath).uri.pathSegments.last;
      final cleanName = videoName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final thumbPath =
          '${tempDir.path}/thumb_${cleanName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final thumbFile = File(thumbPath);
      await thumbFile.writeAsBytes(frameBytes, flush: true);
      return thumbFile;
    } catch (e) {
      debugPrint('[VideoFrameExtractor] Error saving thumbnail file: $e');
      return null;
    }
  }
}
