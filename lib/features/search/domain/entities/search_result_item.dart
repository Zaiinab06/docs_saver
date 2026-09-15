import 'package:equatable/equatable.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';

class SearchResultItem extends Equatable {
  final String id;
  final String title;
  final String content;
  final String category;
  final List<String> tags;
  final String? mediaUrl;
  final DateTime clientCreatedAt;
  final double similarity;
  final bool isOfflineResult;

  const SearchResultItem({
    required this.id,
    required this.title,
    required this.content,
    this.category = 'General',
    this.tags = const [],
    this.mediaUrl,
    required this.clientCreatedAt,
    this.similarity = 0.0,
    this.isOfflineResult = false,
  });

  MemoryEntity toMemoryEntity({String userId = 'local_user'}) {
    return MemoryEntity(
      id: id,
      userId: userId,
      title: title,
      content: content,
      mediaUrl: mediaUrl,
      tags: tags,
      category: category,
      aiStatus: 'processed',
      clientCreatedAt: clientCreatedAt,
      clientUpdatedAt: clientCreatedAt,
      serverUpdatedAt: clientCreatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        content,
        category,
        tags,
        mediaUrl,
        clientCreatedAt,
        similarity,
        isOfflineResult,
      ];
}
