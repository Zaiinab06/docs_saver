import 'package:equatable/equatable.dart';

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
  });

  bool get isPinned =>
      tags.any((t) => t.toLowerCase() == 'pinned' || t.toLowerCase() == 'pin') ||
      category.toLowerCase() == 'pinned';

  static int compareByPinnedAndDate(MemoryEntity a, MemoryEntity b) {
    final aPinned = a.isPinned;
    final bPinned = b.isPinned;
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    final dateComp = b.clientCreatedAt.compareTo(a.clientCreatedAt);
    if (dateComp != 0) return dateComp;
    return b.id.compareTo(a.id);
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
  ];
}
