import 'package:isar_community/isar.dart';
import '../../../../core/services/isar_service.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import '../models/search_result_model.dart';

abstract class SearchLocalDataSource {
  Future<List<SearchResultModel>> searchMemoriesLocally(
    String query, {
    String? userId,
  });

  Future<MemoryModel?> getMemoryById(String serverId);
}

class SearchLocalDataSourceImpl implements SearchLocalDataSource {
  final Isar? isarInstance;

  SearchLocalDataSourceImpl({this.isarInstance});

  Isar? get isar {
    if (isarInstance != null) return isarInstance;
    try {
      return IsarService.instance;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MemoryModel?> getMemoryById(String serverId) async {
    final isarDb = isar;
    if (isarDb == null) return null;
    try {
      return await isarDb.memoryModels
          .filter()
          .serverIdEqualTo(serverId)
          .findFirst();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<SearchResultModel>> searchMemoriesLocally(
    String query, {
    String? userId,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final isarDb = isar;
    if (isarDb == null) return [];

    List<MemoryModel> models;
    try {
      if (userId != null && userId.isNotEmpty) {
        models = await isarDb.memoryModels
            .filter()
            .userIdEqualTo(userId)
            .sortByClientCreatedAtDesc()
            .findAll();
      } else {
        models = await isarDb.memoryModels
            .where()
            .sortByClientCreatedAtDesc()
            .findAll();
      }
    } catch (_) {
      return [];
    }

    final queryTokens =
        cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final matched = <_ScoredMemory>[];

    for (final m in models) {
      final titleLower = m.title.toLowerCase();
      final contentLower = m.content.toLowerCase();
      final categoryLower = m.category.toLowerCase();
      final tagsLower = m.tags.map((t) => t.toLowerCase()).toList();

      int score = 0;

      for (final token in queryTokens) {
        if (titleLower.contains(token)) {
          score += 10;
        }
        if (categoryLower.contains(token)) {
          score += 5;
        }
        if (tagsLower.any((t) => t.contains(token))) {
          score += 5;
        }
        if (contentLower.contains(token)) {
          score += 2;
        }
      }

      if (score > 0) {
        matched.add(_ScoredMemory(m, score));
      }
    }

    // Sort by highest keyword relevance score, then by recency
    matched.sort((a, b) {
      final scoreComp = b.score.compareTo(a.score);
      if (scoreComp != 0) return scoreComp;
      return b.model.clientCreatedAt.compareTo(a.model.clientCreatedAt);
    });

    return matched
        .map((sm) => SearchResultModel.fromMemoryModel(sm.model, score: 0.0))
        .toList();
  }
}

class _ScoredMemory {
  final MemoryModel model;
  final int score;
  _ScoredMemory(this.model, this.score);
}
