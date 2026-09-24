import 'dart:convert';
import 'package:isar_community/isar.dart';
import '../../domain/entities/memory_entity.dart';

part 'memory_model.g.dart';

@collection
class MemoryModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String serverId;

  late String userId;

  late String title;

  late String content;

  String? mediaUrl;

  List<String> tags = [];

  String category = 'General';

  List<double>? embedding;

  String aiStatus = 'pending'; // 'pending', 'processed', 'failed'

  String? rawMetadataJson;

  @ignore
  Map<String, dynamic>? get metadata {
    if (rawMetadataJson == null || rawMetadataJson!.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(rawMetadataJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  set metadata(Map<String, dynamic>? val) {
    if (val == null || val.isEmpty) {
      rawMetadataJson = null;
    } else {
      rawMetadataJson = jsonEncode(val);
    }
  }

  bool isConflictCopy = false;

  late DateTime clientCreatedAt;

  late DateTime clientUpdatedAt;

  late DateTime serverUpdatedAt;

  bool isSynced = false; // Local tracking flag for offline sync engine

  static MemoryModel fromMap(Map<String, dynamic> map, {bool isSynced = true}) {
    var contentStr = (map['content'] ?? '').toString();
    Map<String, dynamic>? meta;
    if (map['metadata'] is Map && (map['metadata'] as Map).isNotEmpty) {
      meta = Map<String, dynamic>.from(map['metadata'] as Map);
    } else if (map['metadata'] is String &&
        (map['metadata'] as String).trim().isNotEmpty) {
      try {
        meta = jsonDecode(map['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    // Strip legacy <!--template_metadata:...--> comment hack if present
    final legacyMatch = RegExp(
      r'<!--template_metadata:(.*?)-->',
      dotAll: true,
    ).firstMatch(contentStr);
    if (legacyMatch != null) {
      if (meta == null) {
        try {
          final jsonStr = legacyMatch.group(1);
          if (jsonStr != null && jsonStr.trim().isNotEmpty) {
            meta = jsonDecode(jsonStr) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      contentStr = contentStr
          .replaceAll(
            RegExp(r'\n*<!--template_metadata:[\s\S]*?-->', dotAll: true),
            '',
          )
          .trim();
    }

    final model = MemoryModel()
      ..serverId = (map['id'] ?? '').toString()
      ..userId = (map['user_id'] ?? '').toString()
      ..title = (map['title'] ?? '').toString()
      ..content = contentStr
      ..metadata = meta
      ..mediaUrl = map['media_url'] as String?
      ..tags = map['tags'] != null ? List<String>.from(map['tags'] as List) : []
      ..category = (map['category'] ?? 'General').toString()
      ..aiStatus = (map['ai_status'] ?? 'pending').toString()
      ..isConflictCopy = map['is_conflict_copy'] as bool? ?? false
      ..clientCreatedAt = map['client_created_at'] != null
          ? DateTime.tryParse(map['client_created_at'].toString()) ??
                DateTime.now()
          : DateTime.now()
      ..clientUpdatedAt = map['client_updated_at'] != null
          ? DateTime.tryParse(map['client_updated_at'].toString()) ??
                DateTime.now()
          : DateTime.now()
      ..serverUpdatedAt = map['server_updated_at'] != null
          ? DateTime.tryParse(map['server_updated_at'].toString()) ??
                DateTime.now()
          : DateTime.now()
      ..isSynced = isSynced;

    if (map['embedding'] != null) {
      if (map['embedding'] is List) {
        model.embedding = (map['embedding'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
      } else if (map['embedding'] is String) {
        final str = (map['embedding'] as String)
            .replaceAll('[', '')
            .replaceAll(']', '');
        model.embedding = str
            .split(',')
            .map((s) => double.tryParse(s.trim()))
            .whereType<double>()
            .toList();
      }
    }

    return model;
  }
}

extension MemoryModelMapper on MemoryModel {
  MemoryEntity toEntity() {
    final cleanContent = content
        .replaceAll(
          RegExp(r'\n*<!--template_metadata:[\s\S]*?-->', dotAll: true),
          '',
        )
        .trim();
    var meta = metadata;
    if (meta == null && content.contains('<!--template_metadata:')) {
      final match = RegExp(
        r'<!--template_metadata:(.*?)-->',
        dotAll: true,
      ).firstMatch(content);
      if (match != null) {
        try {
          meta = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    return MemoryEntity(
      id: serverId,
      userId: userId,
      title: title,
      content: cleanContent,
      mediaUrl: mediaUrl,
      tags: tags,
      category: category,
      embedding: embedding,
      aiStatus: aiStatus,
      isConflictCopy: isConflictCopy,
      clientCreatedAt: clientCreatedAt,
      clientUpdatedAt: clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt,
      isSynced: isSynced,
      metadata: meta,
    );
  }
}

extension MemoryEntityMapper on MemoryEntity {
  MemoryModel toModel({bool? isSynced}) {
    final cleanContent = content
        .replaceAll(
          RegExp(r'\n*<!--template_metadata:[\s\S]*?-->', dotAll: true),
          '',
        )
        .trim();
    final model = MemoryModel()
      ..serverId = id
      ..userId = userId
      ..title = title
      ..content = cleanContent
      ..mediaUrl = mediaUrl
      ..tags = tags
      ..category = category
      ..embedding = embedding
      ..aiStatus = aiStatus
      ..isConflictCopy = isConflictCopy
      ..clientCreatedAt = clientCreatedAt
      ..clientUpdatedAt = clientUpdatedAt
      ..serverUpdatedAt = serverUpdatedAt
      ..isSynced = isSynced ?? this.isSynced;
    model.metadata = metadata;
    return model;
  }
}
