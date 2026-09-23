import 'dart:convert';
import 'package:dio/dio.dart';
import 'link_provider.dart';

class TikTokLinkExtractor {
  final Dio _dio;

  TikTokLinkExtractor({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                'Accept': 'application/json,text/html,*/*',
              },
              followRedirects: true,
              maxRedirects: 5,
            ),
          );

  Future<RichLinkContent> extract(Uri uri) async {
    // 1. Initial canonicalization from URL path if possible
    String canonicalUrl =
        LinkProviderDetector.toCanonicalTikTokUrl(uri) ??
        uri.replace(queryParameters: {}).toString();
    if (canonicalUrl.endsWith('?')) {
      canonicalUrl = canonicalUrl.substring(0, canonicalUrl.length - 1);
    }

    String? title;
    String? creator;
    String? authorUniqueId = LinkProviderDetector.extractTikTokUsername(uri);
    String? authorName;
    String? authorUrl;
    String? thumbnailUrl;
    String? videoId = LinkProviderDetector.extractTikTokVideoId(uri);

    // 2. Fetch metadata from official TikTok oEmbed API
    final targetUrlForOembed = uri.toString();
    try {
      final oEmbedUri = Uri.parse(
        'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(targetUrlForOembed)}&format=json',
      );
      final oEmbedResponse = await _dio.getUri(
        oEmbedUri,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (oEmbedResponse.data != null) {
        final data = oEmbedResponse.data is Map
            ? (oEmbedResponse.data as Map)
            : (oEmbedResponse.data is String
                  ? jsonDecode(oEmbedResponse.data as String) as Map
                  : null);

        if (data != null) {
          title = data['title']?.toString().trim();
          authorName = data['author_name']?.toString().trim();
          final uniqueId = data['author_unique_id']?.toString().trim();
          if (uniqueId != null && uniqueId.isNotEmpty) {
            authorUniqueId = uniqueId;
          }
          authorUrl = data['author_url']?.toString().trim();
          final rawThumb = data['thumbnail_url']?.toString().trim();
          if (rawThumb != null && rawThumb.isNotEmpty) {
            thumbnailUrl = rawThumb;
          }
          final embedId = data['embed_product_id']?.toString().trim();
          if (embedId != null && embedId.isNotEmpty) {
            videoId = embedId;
          }
        }
      }
    } catch (_) {
      // Graceful fallback if oEmbed is unreachable, video deleted, or offline
    }

    // Update canonical URL if authorUniqueId and videoId are resolved from oEmbed
    if (authorUniqueId != null && videoId != null) {
      canonicalUrl = 'https://www.tiktok.com/@$authorUniqueId/video/$videoId';
    }

    // Format Creator
    if (authorName != null && authorName.isNotEmpty) {
      if (authorUniqueId != null &&
          authorUniqueId.isNotEmpty &&
          authorUniqueId.toLowerCase() != authorName.toLowerCase()) {
        creator = '$authorName (@$authorUniqueId)';
      } else {
        creator = authorName;
      }
    } else if (authorUniqueId != null && authorUniqueId.isNotEmpty) {
      creator = '@$authorUniqueId';
    }

    // 3. Construct readable body text from real creator and caption
    final bodyBuffer = StringBuffer();
    bodyBuffer.writeln('Platform: TikTok');
    if (creator != null && creator.isNotEmpty) {
      bodyBuffer.writeln('Creator: $creator');
    }
    if (title != null && title.isNotEmpty) {
      bodyBuffer.writeln('Caption: $title');
    }

    final readableBody = bodyBuffer.toString().trim();
    final wordCount = readableBody.isNotEmpty
        ? readableBody.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    return RichLinkContent(
      provider: LinkProvider.tiktok,
      canonicalUrl: canonicalUrl,
      title: title?.isNotEmpty == true ? title : null,
      description: title?.isNotEmpty == true ? title : null,
      creator: creator,
      thumbnailUrl: thumbnailUrl,
      readableContent: readableBody.isNotEmpty ? readableBody : null,
      transcript: null,
      siteName: 'TikTok',
      faviconUrl: 'https://www.tiktok.com/favicon.ico',
      wordCount: wordCount > 0 ? wordCount : null,
      metadata: {
        if (videoId != null) 'videoId': videoId,
        if (authorUniqueId != null) 'authorUniqueId': authorUniqueId,
        if (authorUrl != null) 'authorUrl': authorUrl,
      },
    );
  }
}
