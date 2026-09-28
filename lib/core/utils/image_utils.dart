import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageUtils {
  /// Safely reads an [XFile] from Android Scoped Storage / iOS photo library as bytes,
  /// compresses and downscales it if necessary (max [maxDimension]px, [quality]% JPEG),
  /// and writes it to a persistent local cache file.
  static Future<File> processAndPersistImageXFile(
    XFile xFile, {
    int maxDimension = 1280,
    int quality = 80,
  }) async {
    try {
      debugPrint(
        '[ImageUtils] Reading XFile bytes for: ${xFile.path} (name: ${xFile.name})',
      );
      final rawBytes = await xFile.readAsBytes();
      debugPrint(
        '[ImageUtils] Successfully read ${rawBytes.length} bytes from XFile.',
      );

      Uint8List compressedBytes = rawBytes;
      // Compress / resize if bytes or resolution are high
      if (rawBytes.length > 512 * 1024) {
        try {
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            img.Image working = decoded;
            if (decoded.width > maxDimension || decoded.height > maxDimension) {
              if (decoded.width >= decoded.height) {
                working = img.copyResize(decoded, width: maxDimension);
              } else {
                working = img.copyResize(decoded, height: maxDimension);
              }
              debugPrint(
                '[ImageUtils] Resized image from ${decoded.width}x${decoded.height} to ${working.width}x${working.height}',
              );
            }
            final jpgBytes = img.encodeJpg(working, quality: quality);
            compressedBytes = Uint8List.fromList(jpgBytes);
            debugPrint(
              '[ImageUtils] Compressed image from ${rawBytes.length} to ${compressedBytes.length} bytes (quality: $quality).',
            );
          }
        } catch (compressionErr) {
          debugPrint(
            '[ImageUtils Warning] In-memory image compression failed: $compressionErr. Using raw bytes.',
          );
        }
      }

      final tempDir = await getTemporaryDirectory();
      final cleanBaseName = xFile.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9_\.]'),
        '_',
      );
      final hasJpgExt =
          cleanBaseName.toLowerCase().endsWith('.jpg') ||
          cleanBaseName.toLowerCase().endsWith('.jpeg');
      final fileName =
          'gallery_${DateTime.now().millisecondsSinceEpoch}_$cleanBaseName${hasJpgExt ? '' : '.jpg'}';
      final targetFile = File('${tempDir.path}/$fileName');
      await targetFile.writeAsBytes(compressedBytes, flush: true);
      debugPrint(
        '[ImageUtils] Saved persistent local image: ${targetFile.path}',
      );
      return targetFile;
    } catch (e) {
      debugPrint('[ImageUtils Error] Failed to process XFile: $e');
      // Fallback: return direct File if exists
      return File(xFile.path);
    }
  }

  /// Verifies and optimizes a local image file for Gemini Multimodal AI ingestion.
  /// Downscales to [maxDimension] and encodes as JPEG [quality] if larger than [maxByteThreshold].
  /// Returns a record with base64 string, mimeType ('image/jpeg'), and final byte length.
  static Future<({String base64, String mimeType, int byteLength})?>
  prepareImageForAi(
    File imageFile, {
    int maxDimension = 1280,
    int quality = 80,
    int maxByteThreshold = 1024 * 1024, // 1MB threshold for AI base64 payload
  }) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint(
          '[ImageUtils Warning] Image file does not exist: ${imageFile.path}',
        );
        return null;
      }

      final rawBytes = await imageFile.readAsBytes();
      if (rawBytes.isEmpty) {
        debugPrint(
          '[ImageUtils Warning] Image file is empty: ${imageFile.path}',
        );
        return null;
      }

      Uint8List workingBytes = rawBytes;
      String mimeType = 'image/jpeg';

      // If raw file exceeds threshold, resize and re-encode to quality 80
      if (rawBytes.length > maxByteThreshold) {
        try {
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            img.Image resized = decoded;
            if (decoded.width > maxDimension || decoded.height > maxDimension) {
              if (decoded.width >= decoded.height) {
                resized = img.copyResize(decoded, width: maxDimension);
              } else {
                resized = img.copyResize(decoded, height: maxDimension);
              }
            }
            final jpgBytes = img.encodeJpg(resized, quality: quality);
            workingBytes = Uint8List.fromList(jpgBytes);
            debugPrint(
              '[ImageUtils] Optimized AI payload from ${rawBytes.length} to ${workingBytes.length} bytes',
            );
          }
        } catch (resizeErr) {
          debugPrint(
            '[ImageUtils Warning] Failed to optimize image for AI: $resizeErr',
          );
        }
      } else {
        final ext = imageFile.path.split('.').last.toLowerCase();
        mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
      }

      final base64String = base64Encode(workingBytes);
      return (
        base64: base64String,
        mimeType: mimeType,
        byteLength: workingBytes.length,
      );
    } catch (e) {
      debugPrint('[ImageUtils Error] prepareImageForAi failed: $e');
      return null;
    }
  }
}
