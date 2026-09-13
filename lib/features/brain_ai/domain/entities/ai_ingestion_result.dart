import 'package:equatable/equatable.dart';

class LivingEntityItem extends Equatable {
  final String name;
  final String type;
  final String attributes;

  const LivingEntityItem({
    required this.name,
    required this.type,
    this.attributes = '',
  });

  factory LivingEntityItem.fromMap(Map<String, dynamic> map) {
    return LivingEntityItem(
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? 'Topic').toString(),
      attributes: (map['attributes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'attributes': attributes,
    };
  }

  @override
  List<Object?> get props => [name, type, attributes];
}

class AiIngestionResult extends Equatable {
  final String title;
  final String category;
  final List<String> tags;
  final String summary;
  final List<LivingEntityItem> entities;
  final String aiStatus; // 'processed' | 'pending' | 'failed'
  final String? rawOcrText;

  const AiIngestionResult({
    required this.title,
    required this.category,
    required this.tags,
    required this.summary,
    this.entities = const [],
    required this.aiStatus,
    this.rawOcrText,
  });

  factory AiIngestionResult.empty({
    String? rawOcrText,
    String aiStatus = 'pending',
  }) {
    return AiIngestionResult(
      title: '',
      category: 'Personal',
      tags: const [],
      summary: '',
      entities: const [],
      aiStatus: aiStatus,
      rawOcrText: rawOcrText,
    );
  }

  @override
  List<Object?> get props => [
        title,
        category,
        tags,
        summary,
        entities,
        aiStatus,
        rawOcrText,
      ];
}
