import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'structured_template.dart';

class MemoryEntity extends Equatable {
  final String id;
  final String userId;
  final String title;
  final String content;
  final String? mediaUrl;
  final List<String> tags;
  final String category;
  final List<double>? embedding;
  final String aiStatus;
  final bool isConflictCopy;
  final DateTime clientCreatedAt;
  final DateTime clientUpdatedAt;
  final DateTime serverUpdatedAt;
  final bool isSynced;
  final Map<String, dynamic>? metadata;

  const MemoryEntity({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    this.mediaUrl,
    this.tags = const [],
    this.category = 'General',
    this.embedding,
    this.aiStatus = 'pending',
    this.isConflictCopy = false,
    required this.clientCreatedAt,
    required this.clientUpdatedAt,
    required this.serverUpdatedAt,
    this.isSynced = true,
    this.metadata,
  });

  bool get isPinned =>
      tags.any(
        (t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin',
      ) ||
      category.toLowerCase() == 'pinned';

  /// Resolves the file type of the memory (e.g. 'video', 'audio', 'document', 'image')
  String? get fileType {
    if (metadata != null && metadata!['file_type'] != null) {
      return metadata!['file_type'].toString().toLowerCase();
    }
    if (tags.any((t) => t.toLowerCase() == 'video')) return 'video';
    if (tags.any((t) => t.toLowerCase() == 'voice' || t.toLowerCase() == 'audio')) return 'audio';
    if (tags.any((t) => t.toLowerCase() == 'document' || t.toLowerCase() == 'pdf')) return 'document';
    if (mediaUrl != null && mediaUrl!.trim().isNotEmpty) {
      final cleanUrl = mediaUrl!.trim().split('?').first.toLowerCase();
      if (cleanUrl.endsWith('.mp4') ||
          cleanUrl.endsWith('.mov') ||
          cleanUrl.endsWith('.avi') ||
          cleanUrl.endsWith('.mkv') ||
          cleanUrl.endsWith('.webm') ||
          cleanUrl.endsWith('.3gp') ||
          cleanUrl.endsWith('.m4v')) {
        return 'video';
      }
      if (cleanUrl.endsWith('.m4a') ||
          cleanUrl.endsWith('.aac') ||
          cleanUrl.endsWith('.mp3') ||
          cleanUrl.endsWith('.wav') ||
          cleanUrl.endsWith('.ogg')) {
        return 'audio';
      }
      if (cleanUrl.endsWith('.pdf') ||
          cleanUrl.endsWith('.txt') ||
          cleanUrl.endsWith('.md') ||
          cleanUrl.endsWith('.csv') ||
          cleanUrl.endsWith('.json')) {
        return 'document';
      }
      if (cleanUrl.endsWith('.jpg') ||
          cleanUrl.endsWith('.jpeg') ||
          cleanUrl.endsWith('.png') ||
          cleanUrl.endsWith('.webp') ||
          cleanUrl.endsWith('.gif') ||
          cleanUrl.endsWith('.bmp')) {
        return 'image';
      }
    }
    return null;
  }

  /// Whether this memory has an attached video
  bool get isVideo => fileType == 'video';

  /// Returns parsed structured template data from metadata map or content comment envelope
  Map<String, dynamic>? get templateData {
    if (metadata != null && metadata!.isNotEmpty) {
      return metadata;
    }
    final match = RegExp(
      r'<!--template_metadata:(.*?)-->',
      dotAll: true,
    ).firstMatch(content);
    if (match != null) {
      try {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          return jsonDecode(jsonStr) as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Template type string: 'bank_card', 'bill', or null
  String? get templateType => templateData?['template'] as String?;

  /// Whether this memory represents a structured template
  bool get isStructuredTemplate => templateType != null;

  /// Human-readable content without the raw HTML comment envelope
  String get cleanContent => content
      .replaceAll(
        RegExp(r'\n*<!--template_metadata:.*?-->', dotAll: true),
        '',
      )
      .trim();

  /// Typed helper for Bank Card Template
  BankCardTemplate? get bankCardTemplate {
    if (templateType != TemplateTypes.bankCard) return null;
    final data = templateData;
    if (data == null) return null;
    return BankCardTemplate.fromJson(data);
  }

  /// Typed helper for Bill Template
  BillTemplate? get billTemplate {
    if (templateType != TemplateTypes.bill) return null;
    final data = templateData;
    if (data == null) return null;
    return BillTemplate.fromJson(data);
  }

  static int compareByPinnedAndDate(MemoryEntity a, MemoryEntity b) {
    final aPinned = a.isPinned;
    final bPinned = b.isPinned;
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    final dateComp = b.clientCreatedAt.compareTo(a.clientCreatedAt);
    if (dateComp != 0) return dateComp;
    return b.id.compareTo(a.id);
  }

  MemoryEntity copyWith({
    String? id,
    String? userId,
    String? title,
    String? content,
    String? mediaUrl,
    List<String>? tags,
    String? category,
    List<double>? embedding,
    String? aiStatus,
    bool? isConflictCopy,
    DateTime? clientCreatedAt,
    DateTime? clientUpdatedAt,
    DateTime? serverUpdatedAt,
    bool? isSynced,
    Map<String, dynamic>? metadata,
  }) {
    return MemoryEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      embedding: embedding ?? this.embedding,
      aiStatus: aiStatus ?? this.aiStatus,
      isConflictCopy: isConflictCopy ?? this.isConflictCopy,
      clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      isSynced: isSynced ?? this.isSynced,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    title,
    content,
    mediaUrl,
    tags,
    category,
    embedding,
    aiStatus,
    isConflictCopy,
    clientCreatedAt,
    clientUpdatedAt,
    serverUpdatedAt,
    isSynced,
    metadata,
  ];
}
