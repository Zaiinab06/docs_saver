import 'package:isar_community/isar.dart';

part 'tombstone_model.g.dart';

@collection
class TombstoneModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String serverId;

  late String userId;

  late DateTime deletedAt;
}
