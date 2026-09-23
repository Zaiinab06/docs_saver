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

  bool isConflictCopy = false;

  late DateTime clientCreatedAt;

  late DateTime clientUpdatedAt;

  late DateTime serverUpdatedAt;

  bool isSynced = false; // Local tracking flag for offline sync engine

  static MemoryModel fromMap(Map<String, dynamic> map, {bool isSynced = true}) {
    var contentStr = (map['content'] ?? '').toString();
    if (map['metadata'] is Map &&
        (map['metadata'] as Map).isNotEmpty &&
        !contentStr.contains('<!--template_metadata:')) {
      contentStr =
          '$contentStr\n\n<!--template_metadata:${jsonEncode(map['metadata'])}-->'
              .trim();
    }

    final model = MemoryModel()
      ..serverId = (map['id'] ?? '').toString()
      ..userId = (map['user_id'] ?? '').toString()
      ..title = (map['title'] ?? '').toString()
      ..content = contentStr
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
    return MemoryEntity(
      id: serverId,
      userId: userId,
      title: title,
      content: content,
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
    );
  }
}

extension MemoryEntityMapper on MemoryEntity {
  MemoryModel toModel({bool? isSynced}) {
    return MemoryModel()
      ..serverId = id
      ..userId = userId
      ..title = title
      ..content = content
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
  }
}
