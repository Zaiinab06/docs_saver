import 'dart:convert';
import 'package:dio/dio.dart';
import 'link_provider.dart';

class YouTubeLinkExtractor {
  final Dio _dio;

  YouTubeLinkExtractor({Dio? dio})
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
    final videoId = LinkProviderDetector.extractYouTubeVideoId(uri);
    final canonicalUrl = videoId != null
        ? (LinkProviderDetector.toCanonicalYouTubeUrl(videoId) ??
              uri.toString())
        : uri.toString();

    String? title;
    String? creator;
    String? authorUrl;
    String? thumbnailUrl = videoId != null
        ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
        : null;
    String? description;
    String? transcript;

    // 1. Fetch metadata from official YouTube oEmbed API
    try {
      final oEmbedUri = Uri.parse(
        'https://www.youtube.com/oembed?url=${Uri.encodeComponent(canonicalUrl)}&format=json',
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
          creator = data['author_name']?.toString().trim();
          authorUrl = data['author_url']?.toString().trim();
          final rawThumb = data['thumbnail_url']?.toString().trim();
          if (rawThumb != null && rawThumb.isNotEmpty) {
            thumbnailUrl = rawThumb;
          }
        }
      }
    } catch (_) {
      // Graceful fallback if oEmbed is unreachable or video is private/deleted
    }

    // 2. Fetch video page meta tags for description
    try {
      final htmlResponse = await _dio.get<String>(
        canonicalUrl,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (htmlResponse.data != null && htmlResponse.data!.isNotEmpty) {
        final html = htmlResponse.data!;

        // Extract description from meta tags
        final ogDescMatch = RegExp(
          r'<meta\s+property=["\x27]og:description["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).firstMatch(html);
        final nameDescMatch = RegExp(
          r'<meta\s+name=["\x27]description["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).firstMatch(html);

        final rawDesc = ogDescMatch?.group(1) ?? nameDescMatch?.group(1);
        if (rawDesc != null && rawDesc.trim().isNotEmpty) {
          final cleaned = _cleanHtmlEntities(rawDesc.trim());
          if (cleaned.isNotEmpty) {
            description = cleaned;
          }
        }

        // Fallback for title if oEmbed didn't provide one
        if (title == null || title.isEmpty) {
          final ogTitleMatch = RegExp(
            r'<meta\s+property=["\x27]og:title["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
            caseSensitive: false,
          ).firstMatch(html);
          if (ogTitleMatch != null) {
            title = _cleanHtmlEntities(ogTitleMatch.group(1) ?? '');
          }
        }
      }
    } catch (_) {
      // Graceful fallback
    }

    // 3. Attempt public captions/transcript if videoId is available
    if (videoId != null) {
      transcript = await _tryFetchPublicTranscript(videoId);
    }

    // 4. Construct readable body text from real metadata & transcript
    final bodyBuffer = StringBuffer();
    if (creator != null && creator.isNotEmpty) {
      bodyBuffer.writeln('Channel: $creator');
    }
    if (description != null && description.isNotEmpty) {
      if (bodyBuffer.isNotEmpty) bodyBuffer.writeln();
      bodyBuffer.writeln('Description:\n$description');
    }
    if (transcript != null && transcript.isNotEmpty) {
      if (bodyBuffer.isNotEmpty) bodyBuffer.writeln();
      bodyBuffer.writeln('Transcript:\n$transcript');
    }

    final readableBody = bodyBuffer.toString().trim();
    final wordCount = readableBody.isNotEmpty
        ? readableBody.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    return RichLinkContent(
      provider: LinkProvider.youtube,
      canonicalUrl: canonicalUrl,
      title: title?.isNotEmpty == true ? title : null,
      description: description?.isNotEmpty == true ? description : null,
      creator: creator?.isNotEmpty == true ? creator : null,
      thumbnailUrl: thumbnailUrl,
      readableContent: readableBody.isNotEmpty ? readableBody : null,
      transcript: transcript,
      siteName: 'YouTube',
      faviconUrl: 'https://www.youtube.com/favicon.ico',
      wordCount: wordCount > 0 ? wordCount : null,
      metadata: {
        if (videoId != null) 'videoId': videoId,
        if (authorUrl != null) 'authorUrl': authorUrl,
      },
    );
  }

  /// Attempts to fetch public open closed captions via timedtext endpoint.
  /// Returns null if closed captions are disabled, unavailable, or restricted.
  Future<String?> _tryFetchPublicTranscript(String videoId) async {
    try {
      final response = await _dio.get<String>(
        'https://www.youtube.com/api/timedtext?v=$videoId&lang=en',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.data != null && response.data!.contains('<text')) {
        final matches = RegExp(
          r'<text[^>]*>([^<]+)<\/text>',
        ).allMatches(response.data!);
        final chunks = <String>[];
        for (final m in matches) {
          final text = m.group(1);
          if (text != null && text.trim().isNotEmpty) {
            chunks.add(_cleanHtmlEntities(text.trim()));
          }
        }

        if (chunks.isNotEmpty) {
          var joined = chunks.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
          if (joined.length > 8000) {
            final sentenceBreak = joined.lastIndexOf(
              RegExp(r'[\.\?\!]\s'),
              8000,
            );
            if (sentenceBreak > 5000) {
              joined = joined.substring(0, sentenceBreak + 1).trim();
            } else {
              joined = joined.substring(0, 8000).trim();
            }
          }
          return joined.isNotEmpty ? joined : null;
        }
      }
    } catch (_) {
      // Transcript endpoint not accessible without session or video has no public captions
    }
    return null;
  }

  static String _cleanHtmlEntities(String raw) {
    var text = raw.trim();
    text = text
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—');
    return text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}
