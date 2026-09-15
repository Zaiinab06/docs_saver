enum LinkProvider {
  genericWeb,
  youtube,
  tiktok,
  instagram,
}

class RichLinkContent {
  final LinkProvider provider;
  final String canonicalUrl;
  final String? title;
  final String? description;
  final String? creator;
  final String? thumbnailUrl;
  final String? readableContent;
  final String? transcript;
  final String? siteName;
  final String? faviconUrl;
  final int? wordCount;
  final Map<String, dynamic>? metadata;

  const RichLinkContent({
    required this.canonicalUrl,
    this.provider = LinkProvider.genericWeb,
    this.title,
    this.description,
    this.creator,
    this.thumbnailUrl,
    this.readableContent,
    this.transcript,
    this.siteName,
    this.faviconUrl,
    this.wordCount,
    this.metadata,
  });

  bool get hasContent =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) ||
      (readableContent != null && readableContent!.isNotEmpty) ||
      (transcript != null && transcript!.isNotEmpty);
}

class LinkProviderDetector {
  static const Set<String> _youtubeHosts = {
    'youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
  };

  static const Set<String> _tiktokHosts = {
    'tiktok.com',
    'm.tiktok.com',
    'vm.tiktok.com',
    'vt.tiktok.com',
  };

  static const Set<String> _instagramHosts = {
    'instagram.com',
    'm.instagram.com',
    'instagr.am',
  };

  /// Detects whether the parsed [Uri] corresponds to a supported platform.
  static LinkProvider detect(Uri uri) {
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return LinkProvider.genericWeb;
    }
    final host = _normalizeHost(uri.host);
    if (_youtubeHosts.contains(host)) {
      return LinkProvider.youtube;
    }
    if (_isTikTokHost(host)) {
      return LinkProvider.tiktok;
    }
    if (_isInstagramHost(host)) {
      return LinkProvider.instagram;
    }
    return LinkProvider.genericWeb;
  }

  static String _normalizeHost(String host) {
    final lower = host.toLowerCase().trim();
    if (lower.startsWith('www.')) {
      return lower.substring(4);
    }
    return lower;
  }

  static bool _isTikTokHost(String host) {
    return _tiktokHosts.contains(host) || host.endsWith('.tiktok.com');
  }

  static bool _isInstagramHost(String host) {
    return _instagramHosts.contains(host) ||
        host.endsWith('.instagram.com') ||
        host == 'instagr.am' ||
        host.endsWith('.instagr.am');
  }

  // ==================== YOUTUBE ====================

  /// Extracts the 11-character YouTube video ID if present in the [Uri].
  static String? extractYouTubeVideoId(Uri uri) {
    final host = _normalizeHost(uri.host);
    if (!_youtubeHosts.contains(host)) {
      return null;
    }

    // Handle youtu.be/<videoId>
    if (host == 'youtu.be') {
      if (uri.pathSegments.isNotEmpty) {
        final candidate = uri.pathSegments.first.trim();
        if (_isValidYouTubeId(candidate)) return candidate;
      }
      return null;
    }

    // Handle youtube.com / m.youtube.com / music.youtube.com
    // 1. /watch?v=<videoId>
    if (uri.queryParameters.containsKey('v')) {
      final candidate = uri.queryParameters['v']?.trim();
      if (candidate != null && _isValidYouTubeId(candidate)) {
        return candidate;
      }
    }

    // 2. /shorts/<videoId>, /embed/<videoId>, /v/<videoId>, /live/<videoId>
    if (uri.pathSegments.isNotEmpty) {
      final first = uri.pathSegments.first.toLowerCase();
      if (['shorts', 'embed', 'v', 'live'].contains(first) &&
          uri.pathSegments.length > 1) {
        final candidate = uri.pathSegments[1].trim();
        if (_isValidYouTubeId(candidate)) return candidate;
      }
    }

    return null;
  }

  static bool _isValidYouTubeId(String id) {
    return RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id);
  }

  /// Converts a video ID into canonical https://www.youtube.com/watch?v=<id> format.
  static String? toCanonicalYouTubeUrl(String videoId) {
    if (!_isValidYouTubeId(videoId)) return null;
    return 'https://www.youtube.com/watch?v=$videoId';
  }

  // ==================== TIKTOK ====================

  /// Checks whether the [Uri] points to a TikTok domain.
  static bool isTikTok(Uri uri) {
    final host = _normalizeHost(uri.host);
    return _isTikTokHost(host);
  }

  /// Extracts the TikTok video ID from a standard URL if present.
  static String? extractTikTokVideoId(Uri uri) {
    final host = _normalizeHost(uri.host);
    if (!_isTikTokHost(host)) return null;

    for (int i = 0; i < uri.pathSegments.length; i++) {
      final segment = uri.pathSegments[i].toLowerCase();
      if (segment == 'video' && i + 1 < uri.pathSegments.length) {
        final candidate = uri.pathSegments[i + 1].trim();
        if (RegExp(r'^\d+$').hasMatch(candidate)) {
          return candidate;
        }
      }
      if (segment == 'v' && i + 1 < uri.pathSegments.length) {
        var candidate = uri.pathSegments[i + 1].trim();
        if (candidate.endsWith('.html')) {
          candidate = candidate.substring(0, candidate.length - 5);
        }
        if (RegExp(r'^\d+$').hasMatch(candidate)) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Extracts the TikTok username handle if present (e.g. '@scout2015' -> 'scout2015').
  static String? extractTikTokUsername(Uri uri) {
    final host = _normalizeHost(uri.host);
    if (!_isTikTokHost(host)) return null;

    for (final segment in uri.pathSegments) {
      if (segment.startsWith('@') && segment.length > 1) {
        return segment.substring(1);
      }
    }
    return null;
  }

  /// Converts a TikTok username and videoId into canonical format if available.
  static String? toCanonicalTikTokUrl(Uri uri) {
    final username = extractTikTokUsername(uri);
    final videoId = extractTikTokVideoId(uri);
    if (username != null && videoId != null) {
      return 'https://www.tiktok.com/@$username/video/$videoId';
    }
    return null;
  }

  // ==================== INSTAGRAM ====================

  /// Checks whether the [Uri] points to an Instagram domain.
  static bool isInstagram(Uri uri) {
    final host = _normalizeHost(uri.host);
    return _isInstagramHost(host);
  }

  /// Extracts the Instagram shortcode from a post/reel URL if present.
  static String? extractInstagramShortcode(Uri uri) {
    final host = _normalizeHost(uri.host);
    if (!_isInstagramHost(host)) return null;

    for (int i = 0; i < uri.pathSegments.length; i++) {
      final segment = uri.pathSegments[i].toLowerCase();
      if (const {'p', 'reel', 'reels', 'tv'}.contains(segment) &&
          i + 1 < uri.pathSegments.length) {
        final candidate = uri.pathSegments[i + 1].trim();
        if (RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(candidate)) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Extracts the normalized post type ('reel', 'p', or 'tv').
  static String? extractInstagramPostType(Uri uri) {
    final host = _normalizeHost(uri.host);
    if (!_isInstagramHost(host)) return null;

    for (int i = 0; i < uri.pathSegments.length; i++) {
      final segment = uri.pathSegments[i].toLowerCase();
      if (segment == 'reel' || segment == 'reels') return 'reel';
      if (segment == 'p') return 'p';
      if (segment == 'tv') return 'tv';
    }
    return null;
  }

  /// Converts an Instagram URL to clean canonical format (e.g. https://www.instagram.com/p/SHORTCODE/).
  static String? toCanonicalInstagramUrl(Uri uri) {
    final shortcode = extractInstagramShortcode(uri);
    final postType = extractInstagramPostType(uri) ?? 'p';
    if (shortcode != null) {
      return 'https://www.instagram.com/$postType/$shortcode/';
    }
    return null;
  }
}
