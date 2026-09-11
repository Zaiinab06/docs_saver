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
    );
  }
}

extension MemoryEntityMapper on MemoryEntity {
  MemoryModel toModel({bool isSynced = false}) {
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
      ..isSynced = isSynced;
  }
}
