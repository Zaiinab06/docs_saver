import 'package:second_brain/features/capture/data/models/memory_model.dart';
import '../../domain/entities/search_result_item.dart';

class SearchResultModel {
  final String id;
  final String title;
  final String content;
  final String category;
  final List<String> tags;
  final String? mediaUrl;
  final DateTime clientCreatedAt;
  final double similarity;

  const SearchResultModel({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.tags,
    this.mediaUrl,
    required this.clientCreatedAt,
    required this.similarity,
  });

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedTags = [];
    if (json['tags'] != null) {
      if (json['tags'] is List) {
        parsedTags = (json['tags'] as List).map((e) => e.toString()).toList();
      }
    }

    DateTime parsedCreatedAt = DateTime.now();
    if (json['client_created_at'] != null) {
      parsedCreatedAt =
          DateTime.tryParse(json['client_created_at'].toString()) ?? DateTime.now();
    }

    double parsedSimilarity = 0.0;
    if (json['similarity'] != null) {
      if (json['similarity'] is num) {
        parsedSimilarity = (json['similarity'] as num).toDouble();
      } else {
        parsedSimilarity = double.tryParse(json['similarity'].toString()) ?? 0.0;
      }
    }

    return SearchResultModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      category: (json['category'] ?? 'General').toString(),
      tags: parsedTags,
      mediaUrl: json['media_url'] as String?,
      clientCreatedAt: parsedCreatedAt,
      similarity: parsedSimilarity,
    );
  }

  factory SearchResultModel.fromMemoryModel(
    MemoryModel model, {
    double score = 1.0,
  }) {
    return SearchResultModel(
      id: model.serverId,
      title: model.title,
      content: model.content,
      category: model.category,
      tags: List<String>.from(model.tags),
      mediaUrl: model.mediaUrl,
      clientCreatedAt: model.clientCreatedAt,
      similarity: score,
    );
  }

  SearchResultItem toEntity({bool isOffline = false}) {
    return SearchResultItem(
      id: id,
      title: title,
      content: content,
      category: category,
      tags: tags,
      mediaUrl: mediaUrl,
      clientCreatedAt: clientCreatedAt,
      similarity: similarity,
      isOfflineResult: isOffline,
    );
  }
}
