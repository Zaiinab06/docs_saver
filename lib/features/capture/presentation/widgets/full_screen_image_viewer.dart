import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen in-app image viewer using Flutter's native [InteractiveViewer].
/// Supports pinch-to-zoom, pan, close/back navigation, and graceful error handling.
class FullScreenImageViewer extends StatelessWidget {
  final String mediaUrl;
  final String? title;

  const FullScreenImageViewer({super.key, required this.mediaUrl, this.title});

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
      imageWidget = Image.network(
        mediaUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (_, __, ___) => _buildErrorView(),
      );
    } else {
      final file = File(mediaUrl);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildErrorView(),
        );
      } else {
        imageWidget = _buildErrorView();
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title != null && title!.trim().isNotEmpty
              ? title!.trim()
              : 'Image Preview',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          clipBehavior: Clip.none,
          minScale: 0.5,
          maxScale: 4.0,
          child: imageWidget,
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 64, color: Colors.white54),
          SizedBox(height: 12),
          Text(
            'Could not load image',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
