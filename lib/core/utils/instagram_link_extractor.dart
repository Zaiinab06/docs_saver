import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'link_provider.dart';

class InstagramLinkExtractor {
  final Dio _dio;

  InstagramLinkExtractor({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
              followRedirects: true,
              maxRedirects: 5,
            ),
          );

  Future<RichLinkContent> extract(Uri uri) async {
    final shortcode = LinkProviderDetector.extractInstagramShortcode(uri);
    final postType = LinkProviderDetector.extractInstagramPostType(uri) ?? 'p';
    String canonicalUrl =
        LinkProviderDetector.toCanonicalInstagramUrl(uri) ??
        uri.replace(queryParameters: {}).toString();

    String? title;
    String? description;
    String? caption;
    String? creator;
    String? thumbnailUrl;
    String? ogUrl;

    // Attempt to fetch public page if accessible
    try {
      final response = await _dio.get<String>(
        canonicalUrl,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.data != null && response.data!.isNotEmpty) {
        final html = response.data!;

        // Guard strictly against Meta login wall / login page redirects
        final isLoginWall =
            html.contains('accounts/login') ||
            html.contains('Login • Instagram') ||
            html.contains('Log In • Instagram') ||
            (html.contains('Log In') && html.contains('Instagram')) ||
            html.contains('Welcome back to Instagram');

        if (!isLoginWall) {
          final document = html_parser.parse(html);

          // 1. Extract OpenGraph & Meta tags (DOM queries handle any attribute order/intervening attributes)
          final ogTitle =
              document
                  .querySelector('meta[property="og:title"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="og:title"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="twitter:title"]')
                  ?.attributes['content']
                  ?.trim();

          final ogDesc =
              document
                  .querySelector('meta[property="og:description"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="og:description"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="description"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="twitter:description"]')
                  ?.attributes['content']
                  ?.trim();

          final ogImage =
              document
                  .querySelector('meta[property="og:image"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="og:image"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="twitter:image"]')
                  ?.attributes['content']
                  ?.trim();

          final rawOgUrl =
              document
                  .querySelector('meta[property="og:url"]')
                  ?.attributes['content']
                  ?.trim() ??
              document
                  .querySelector('meta[name="og:url"]')
                  ?.attributes['content']
                  ?.trim();

          if (rawOgUrl != null && rawOgUrl.isNotEmpty) {
            ogUrl = rawOgUrl;
            if (rawOgUrl.contains('instagram.com/')) {
              final detectedCanonical =
                  LinkProviderDetector.toCanonicalInstagramUrl(
                    Uri.tryParse(rawOgUrl) ?? uri,
                  );
              if (detectedCanonical != null) {
                canonicalUrl = detectedCanonical;
              }
            }
          }

          // 2. Extract public structured metadata / JSON-LD when legitimately exposed
          final ldJsonScripts = document.querySelectorAll(
            'script[type="application/ld+json"]',
          );
          for (final script in ldJsonScripts) {
            final rawJson = script.text.trim();
            if (rawJson.isEmpty) continue;
            try {
              final parsed = jsonDecode(rawJson);
              if (parsed is Map<String, dynamic>) {
                _extractFromJsonLd(parsed, (c, cap, thumb) {
                  creator ??= c;
                  caption ??= cap;
                  thumbnailUrl ??= thumb;
                });
              } else if (parsed is List) {
                for (final item in parsed) {
                  if (item is Map<String, dynamic>) {
                    _extractFromJsonLd(item, (c, cap, thumb) {
                      creator ??= c;
                      caption ??= cap;
                      thumbnailUrl ??= thumb;
                    });
                  }
                }
              }
            } catch (_) {
              // Ignore malformed JSON-LD
            }
          }

          // 3. Process og:title
          if (ogTitle != null && !_isLoginText(ogTitle)) {
            final cleanTitle = _cleanHtmlEntities(ogTitle);
            title = cleanTitle;

            // Pattern: "Author (@handle) on Instagram: ..." or "Author on Instagram: ..."
            final creatorMatch = RegExp(
              r'^(.+?)(?:\s*\(@([a-zA-Z0-9_.-]+)\))?\s+on Instagram:',
              caseSensitive: false,
            ).firstMatch(cleanTitle);

            if (creatorMatch != null) {
              final name = creatorMatch.group(1)?.trim();
              final handle = creatorMatch.group(2)?.trim();
              if (name != null && handle != null) {
                creator ??= '$name (@$handle)';
              } else if (name != null) {
                creator ??= name;
              } else if (handle != null) {
                creator ??= '@$handle';
              }

              // Extract caption following "... on Instagram: \"Caption\""
              final onIgIdx = cleanTitle.indexOf('on Instagram:');
              if (onIgIdx != -1) {
                var capCandidate = cleanTitle.substring(onIgIdx + 13).trim();
                if (capCandidate.startsWith('"') ||
                    capCandidate.startsWith('“')) {
                  capCandidate = capCandidate.substring(1);
                }
                if (capCandidate.endsWith('"') || capCandidate.endsWith('”')) {
                  capCandidate = capCandidate.substring(
                    0,
                    capCandidate.length - 1,
                  );
                }
                capCandidate = capCandidate.trim();
                if (capCandidate.isNotEmpty) {
                  caption ??= capCandidate;
                }
              }
            } else {
              // Pattern: "Instagram post by Author • Date"
              final postByMatch = RegExp(
                r'^Instagram\s+(?:post|photo|video|reel)\s+by\s+(.+?)(?:\s+•|\s*$)',
                caseSensitive: false,
              ).firstMatch(cleanTitle);
              if (postByMatch != null) {
                final name = postByMatch.group(1)?.trim();
                if (name != null && name.isNotEmpty) {
                  creator ??= name;
                }
              }
            }
          }

          // 4. Process og:description / meta description
          if (ogDesc != null && !_isLoginText(ogDesc)) {
            final cleanDesc = _cleanHtmlEntities(ogDesc);
            description = cleanDesc;

            // Pattern: "15K likes, 230 comments - handle on Date: \"Caption text...\""
            final engagementMatch = RegExp(
              r'^(?:\d+[\d,.]*[KMB]?\s+likes,\s+\d+[\d,.]*[KMB]?\s+comments\s+-\s+)?([a-zA-Z0-9_.-]+)\s+on\s+[^:]+:\s*["“]?(.*?)["”]?$',
              caseSensitive: false,
            ).firstMatch(cleanDesc);

            if (engagementMatch != null) {
              final handle = engagementMatch.group(1)?.trim();
              final matchedCaption = engagementMatch.group(2)?.trim();
              if (handle != null && handle.isNotEmpty) {
                creator ??= '@$handle';
              }
              if (matchedCaption != null && matchedCaption.isNotEmpty) {
                caption ??= matchedCaption;
              }
            } else if (caption == null &&
                !cleanDesc.contains('likes,') &&
                !cleanDesc.contains('comments -')) {
              caption = cleanDesc;
            }
          }

          // 5. Process og:image
          if (ogImage != null &&
              ogImage.isNotEmpty &&
              !ogImage.contains('static.cdninstagram.com/rsrc.php')) {
            thumbnailUrl ??= ogImage;
          }
        }
      }
    } catch (_) {
      // Graceful fallback on network error, timeout, or access restriction
    }

    // Guard against generic site titles being used as actual post content
    if (title != null && _isLoginText(title)) {
      title = null;
    }
    if (description != null && _isLoginText(description)) {
      description = null;
    }

    // Construct readable content if real creator or caption exists
    final bodyBuffer = StringBuffer();
    final effectiveCaption =
        caption ??
        (description != null && !description.contains('likes,')
            ? description
            : null);

    final finalCreator = creator;
    final finalCaption = effectiveCaption;

    if (finalCreator != null || finalCaption != null) {
      bodyBuffer.writeln('Platform: Instagram');
      if (finalCreator != null && finalCreator.isNotEmpty) {
        bodyBuffer.writeln('Creator: $finalCreator');
      }
      if (finalCaption != null &&
          finalCaption.isNotEmpty &&
          finalCaption != finalCreator) {
        bodyBuffer.writeln('Caption: $finalCaption');
      }
    }

    final readableBody = bodyBuffer.toString().trim();
    final wordCount = readableBody.isNotEmpty
        ? readableBody.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    return RichLinkContent(
      provider: LinkProvider.instagram,
      canonicalUrl: canonicalUrl,
      title: effectiveCaption?.isNotEmpty == true
          ? effectiveCaption
          : (title?.isNotEmpty == true ? title : null),
      description: description?.isNotEmpty == true ? description : null,
      creator: creator,
      thumbnailUrl: thumbnailUrl,
      readableContent: readableBody.isNotEmpty ? readableBody : null,
      transcript: null,
      siteName: 'Instagram',
      faviconUrl: 'https://www.instagram.com/favicon.ico',
      wordCount: wordCount > 0 ? wordCount : null,
      metadata: {
        if (shortcode != null) 'shortcode': shortcode,
        'postType': postType,
        if (ogUrl != null) 'ogUrl': ogUrl,
      },
    );
  }

  static void _extractFromJsonLd(
    Map<String, dynamic> json,
    void Function(String? creator, String? caption, String? thumbnail) onData,
  ) {
    String? creator;
    String? caption;
    String? thumbnail;

    // Extract author
    final authorRaw = json['author'];
    if (authorRaw is Map<String, dynamic>) {
      final name = authorRaw['name']?.toString().trim();
      final alternateName = authorRaw['alternateName']?.toString().trim();
      if (name != null && alternateName != null && alternateName.isNotEmpty) {
        creator = '$name ($alternateName)';
      } else if (name != null && name.isNotEmpty) {
        creator = name;
      } else if (alternateName != null && alternateName.isNotEmpty) {
        creator = alternateName;
      }
    } else if (authorRaw is String && authorRaw.trim().isNotEmpty) {
      creator = authorRaw.trim();
    }

    // Extract caption / body
    final body =
        json['articleBody']?.toString().trim() ??
        json['caption']?.toString().trim() ??
        json['text']?.toString().trim() ??
        json['headline']?.toString().trim() ??
        json['description']?.toString().trim();
    if (body != null && body.isNotEmpty) {
      caption = _cleanHtmlEntities(body);
    }

    // Extract image
    final img = json['image'] ?? json['thumbnailUrl'];
    if (img is String && img.trim().isNotEmpty) {
      thumbnail = img.trim();
    } else if (img is List && img.isNotEmpty && img.first is String) {
      thumbnail = img.first.toString().trim();
    } else if (img is Map && img['url'] != null) {
      thumbnail = img['url'].toString().trim();
    }

    onData(creator, caption, thumbnail);
  }

  static bool _isLoginText(String text) {
    final lower = text.toLowerCase().trim();
    return lower == 'instagram' ||
        lower == 'login' ||
        lower == 'log in' ||
        lower.startsWith('login •') ||
        lower.startsWith('log in •') ||
        lower.contains('log in to instagram') ||
        lower.contains('login to instagram') ||
        lower.contains('welcome back to instagram') ||
        lower.contains('accounts/login');
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
