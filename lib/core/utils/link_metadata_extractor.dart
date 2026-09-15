import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'link_provider.dart';
import 'youtube_link_extractor.dart';
import 'tiktok_link_extractor.dart';
import 'instagram_link_extractor.dart';

export 'link_provider.dart';
export 'youtube_link_extractor.dart';
export 'tiktok_link_extractor.dart';
export 'instagram_link_extractor.dart';

class LinkMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final String? readableContent;
  final int? wordCount;
  final LinkProvider provider;
  final String? creator;
  final String? transcript;
  final Map<String, dynamic>? extraMetadata;

  const LinkMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    this.readableContent,
    this.wordCount,
    this.provider = LinkProvider.genericWeb,
    this.creator,
    this.transcript,
    this.extraMetadata,
  });

  String get canonicalUrl => url;
  String? get thumbnailUrl => imageUrl;

  bool get hasContent =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty) ||
      (readableContent != null && readableContent!.isNotEmpty) ||
      (transcript != null && transcript!.isNotEmpty);

  RichLinkContent toRichLinkContent() => RichLinkContent(
        provider: provider,
        canonicalUrl: url,
        title: title,
        description: description,
        creator: creator,
        thumbnailUrl: imageUrl,
        readableContent: readableContent,
        transcript: transcript,
        siteName: siteName,
        faviconUrl: faviconUrl,
        wordCount: wordCount,
        metadata: extraMetadata,
      );

  factory LinkMetadata.fromRichLinkContent(RichLinkContent rich) {
    return LinkMetadata(
      url: rich.canonicalUrl,
      title: rich.title,
      description: rich.description,
      imageUrl: rich.thumbnailUrl,
      siteName: rich.siteName,
      faviconUrl: rich.faviconUrl,
      readableContent: rich.readableContent,
      wordCount: rich.wordCount,
      provider: rich.provider,
      creator: rich.creator,
      transcript: rich.transcript,
      extraMetadata: rich.metadata,
    );
  }
}

class LinkMetadataExtractor {
  final Dio _dio;
  late final YouTubeLinkExtractor _youTubeExtractor;
  late final TikTokLinkExtractor _tikTokExtractor;
  late final InstagramLinkExtractor _instagramExtractor;

  LinkMetadataExtractor({
    Dio? dio,
    YouTubeLinkExtractor? youTubeExtractor,
    TikTokLinkExtractor? tikTokExtractor,
    InstagramLinkExtractor? instagramExtractor,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 5),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                },
                followRedirects: true,
                maxRedirects: 5,
                responseType: ResponseType.plain,
              ),
            ),
        _youTubeExtractor = youTubeExtractor ??
            YouTubeLinkExtractor(dio: dio),
        _tikTokExtractor = tikTokExtractor ??
            TikTokLinkExtractor(dio: dio),
        _instagramExtractor = instagramExtractor ??
            InstagramLinkExtractor(dio: dio);

  static String? validateUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return 'Please enter a URL';
    }
    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return 'URL must start with http:// or https://';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Only http:// and https:// URLs are supported';
    }
    if (!uri.hasAuthority || uri.host.trim().isEmpty) {
      return 'URL is missing a valid host or domain';
    }
    final host = uri.host.trim();
    if (!host.contains('.') && host.toLowerCase() != 'localhost') {
      return 'Please enter a valid domain (e.g. example.com)';
    }
    return null;
  }

  Future<LinkMetadata> extract(String rawUrl) async {
    final validationError = validateUrl(rawUrl);
    if (validationError != null) {
      return LinkMetadata(url: rawUrl.trim());
    }

    final trimmed = rawUrl.trim();
    final uri = Uri.parse(trimmed);

    // 1. Detect Provider
    final provider = LinkProviderDetector.detect(uri);
    if (provider == LinkProvider.youtube) {
      try {
        final rich = await _youTubeExtractor.extract(uri);
        return LinkMetadata.fromRichLinkContent(rich);
      } catch (_) {
        // Fallback to generic link handling on unexpected extractor failure
      }
    } else if (provider == LinkProvider.tiktok) {
      try {
        final rich = await _tikTokExtractor.extract(uri);
        return LinkMetadata.fromRichLinkContent(rich);
      } catch (_) {
        // Fallback
      }
    } else if (provider == LinkProvider.instagram) {
      try {
        final rich = await _instagramExtractor.extract(uri);
        return LinkMetadata.fromRichLinkContent(rich);
      } catch (_) {
        // Fallback
      }
    }

    // 2. Generic Web / Article Extraction (Existing implementation preserved 100%)
    try {
      final response = await _dio.get<String>(trimmed);
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          response.data != null) {
        final html = response.data!;
        return parseHtml(trimmed, html);
      }
    } catch (_) {
      // Graceful fallback: Network error, timeout, 401/403, or non-HTML response
    }

    return LinkMetadata(
      url: trimmed,
      siteName: uri.host.isNotEmpty ? uri.host : null,
      faviconUrl: uri.host.isNotEmpty
          ? '${uri.scheme}://${uri.host}/favicon.ico'
          : null,
    );
  }

  static LinkMetadata parseHtml(String url, String html) {
    final uri = Uri.tryParse(url);
    final document = html_parser.parse(html);

    // 1. Metadata Extraction via DOM query selectors
    // Title
    String? title = document
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
            ?.trim() ??
        document.querySelector('title')?.text.trim();

    title = _cleanHtmlText(title);

    // Description
    String? description = document
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

    description = _cleanHtmlText(description);

    // Image URL
    String? imageUrl = document
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

    if (imageUrl != null && imageUrl.isNotEmpty && uri != null) {
      imageUrl = _resolveUrl(uri, imageUrl);
    }

    // Site Name
    String? siteName = document
            .querySelector('meta[property="og:site_name"]')
            ?.attributes['content']
            ?.trim() ??
        (uri != null && uri.host.isNotEmpty ? uri.host : null);

    siteName = _cleanHtmlText(siteName);

    // Favicon URL
    String? faviconUrl;
    final iconEl = document.querySelector('link[rel~="icon"]') ??
        document.querySelector('link[rel="shortcut icon"]');
    final iconHref = iconEl?.attributes['href']?.trim();
    if (iconHref != null && iconHref.isNotEmpty && uri != null) {
      faviconUrl = _resolveUrl(uri, iconHref);
    } else if (uri != null && uri.host.isNotEmpty) {
      faviconUrl = '${uri.scheme}://${uri.host}/favicon.ico';
    }

    // 2. Readable Webpage Content Extraction
    final readableResult = _extractReadableBody(document);
    String? readableContent = readableResult.text;
    int wordCount = readableResult.wordCount;

    // 3. Fallback Handling
    // If readableContent is empty or less than ~80 words, fallback to og:title + og:description
    if (wordCount < 80) {
      final fallbackBuffer = StringBuffer();
      if (title != null && title.isNotEmpty) {
        fallbackBuffer.writeln(title);
      }
      if (description != null && description.isNotEmpty) {
        if (fallbackBuffer.isNotEmpty) fallbackBuffer.writeln();
        fallbackBuffer.writeln(description);
      }
      final fallbackStr = fallbackBuffer.toString().trim();
      if (fallbackStr.isNotEmpty) {
        readableContent = fallbackStr;
        wordCount = fallbackStr
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
      }
    }

    return LinkMetadata(
      url: url,
      title: title?.isNotEmpty == true ? title : null,
      description: description?.isNotEmpty == true ? description : null,
      imageUrl: imageUrl?.isNotEmpty == true ? imageUrl : null,
      siteName: siteName?.isNotEmpty == true ? siteName : null,
      faviconUrl: faviconUrl?.isNotEmpty == true ? faviconUrl : null,
      readableContent:
          readableContent?.isNotEmpty == true ? readableContent : null,
      wordCount: wordCount > 0 ? wordCount : null,
    );
  }

  static ({String? text, int wordCount}) _extractReadableBody(
      Document document) {
    // Clone body or work on document
    final body = document.body;
    if (body == null) {
      return (text: null, wordCount: 0);
    }

    // Step A: Remove non-content and clutter tags
    const tagsToRemove = [
      'script',
      'style',
      'noscript',
      'nav',
      'header',
      'footer',
      'aside',
      'form',
      'svg',
      'iframe',
      'canvas',
      'video',
      'audio',
      'button',
      'input',
      'select',
      'textarea',
      'dialog',
    ];

    for (final tag in tagsToRemove) {
      for (final el in body.querySelectorAll(tag)) {
        el.remove();
      }
    }

    // Remove obvious ad, cookie, consent, and share widgets
    for (final el in body.querySelectorAll(
      '[class*="cookie"], [id*="cookie"], [class*="consent"], [id*="consent"], [class*="advertisement"], [id*="advertisement"], [class*="ad-container"], [class*="social-share"]',
    )) {
      final name = el.localName?.toLowerCase();
      if (name != 'article' && name != 'main' && name != 'body') {
        el.remove();
      }
    }

    // Step B: Identify primary content container in order of preference
    Element? contentContainer;
    contentContainer = body.querySelector('article');
    contentContainer ??= body.querySelector('main');
    contentContainer ??= body.querySelector('[role="main"]');
    contentContainer ??= body.querySelector(
      '.post-content, .article-content, .article-body, .entry-content, .content-area, .main-content, #content, #main-content',
    );
    contentContainer ??= body;

    // Step C: Extract structural blocks
    final structuralQuery =
        contentContainer.querySelectorAll('h1, h2, h3, h4, p, blockquote, li, pre');

    // De-duplicate parent-child matches (e.g. avoid parsing <p> inside <li> or <blockquote> twice)
    final rootElements = <Element>[];
    for (final el in structuralQuery) {
      bool hasAncestor = false;
      Element? parent = el.parent;
      while (parent != null && parent != contentContainer) {
        if (structuralQuery.contains(parent)) {
          hasAncestor = true;
          break;
        }
        parent = parent.parent;
      }
      if (!hasAncestor) {
        rootElements.add(el);
      }
    }

    final buffer = StringBuffer();
    final seenParagraphs = <String>{};

    void appendBlock(String prefix, String raw) {
      final clean = _cleanHtmlText(raw);
      if (clean == null || clean.length < 3) return;

      // Filter noise button labels or repetitive links
      final lower = clean.toLowerCase();
      const noiseWords = {
        'share', 'tweet', 'like', 'follow us', 'subscribe', 'sign in',
        'log in', 'cookie policy', 'privacy policy', 'terms of service',
        'read more', 'click here', 'all rights reserved'
      };
      if (noiseWords.contains(lower)) return;

      // Avoid duplicate lines
      if (seenParagraphs.contains(clean)) return;
      seenParagraphs.add(clean);

      if (buffer.isNotEmpty) {
        buffer.writeln('\n');
      }
      if (prefix.isNotEmpty) {
        buffer.write('$prefix ');
      }
      buffer.write(clean);
    }

    if (rootElements.isNotEmpty) {
      for (final el in rootElements) {
        final tag = el.localName?.toLowerCase() ?? '';
        final text = el.text;

        switch (tag) {
          case 'h1':
            appendBlock('#', text);
            break;
          case 'h2':
            appendBlock('##', text);
            break;
          case 'h3':
          case 'h4':
            appendBlock('###', text);
            break;
          case 'blockquote':
            appendBlock('>', text);
            break;
          case 'li':
            appendBlock('•', text);
            break;
          case 'pre':
            final clean = el.text.trim();
            if (clean.isNotEmpty && !seenParagraphs.contains(clean)) {
              seenParagraphs.add(clean);
              if (buffer.isNotEmpty) buffer.writeln('\n');
              buffer.write(clean);
            }
            break;
          default:
            appendBlock('', text);
        }
      }
    } else {
      // Fallback if no structural tags found: split body text by lines
      final lines = contentContainer.text.split(RegExp(r'[\r\n]+'));
      for (final line in lines) {
        appendBlock('', line);
      }
    }

    var fullText = buffer.toString().trim();
    if (fullText.isEmpty) {
      return (text: null, wordCount: 0);
    }

    // Step D: Apply ~10,000-character cap cleanly at paragraph or sentence boundary
    if (fullText.length > 10000) {
      final paragraphBreak = fullText.lastIndexOf('\n\n', 10000);
      if (paragraphBreak > 6500) {
        fullText = fullText.substring(0, paragraphBreak).trim();
      } else {
        final sentenceBreak =
            fullText.lastIndexOf(RegExp(r'[\.\?\!]\s'), 10000);
        if (sentenceBreak > 6500) {
          fullText = fullText.substring(0, sentenceBreak + 1).trim();
        } else {
          fullText = fullText.substring(0, 10000).trim();
        }
      }
    }

    final wordCount = fullText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return (text: fullText, wordCount: wordCount);
  }

  static String? _cleanHtmlText(String? raw) {
    if (raw == null) return null;
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
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  static String _resolveUrl(Uri baseUri, String relativeOrAbsolute) {
    final trimmed = relativeOrAbsolute.trim();
    if (trimmed.startsWith('//')) {
      return '${baseUri.scheme}:$trimmed';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    return baseUri.resolve(trimmed).toString();
  }
}
