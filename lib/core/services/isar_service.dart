import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/capture/data/models/memory_model.dart';
import '../../features/capture/data/models/tombstone_model.dart';

class IsarService {
  static late Isar _isar;

  static Isar get instance => _isar;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [MemoryModelSchema, TombstoneModelSchema],
      directory: dir.path,
      inspector: true,
    );
  }
}
