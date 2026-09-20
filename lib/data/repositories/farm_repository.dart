import '../../domain/farm_domain.dart';

enum EntityKind { scenarios, optimizationRuns, simulationRuns, harvestBatches }

class StoredEntity {
  const StoredEntity({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() => {'id': id, 'data': data};
  factory StoredEntity.fromJson(Map<String, dynamic> json) => StoredEntity(
    id: json['id'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
  );
}

abstract interface class FarmRepository {
  Stream<List<Farm>> watchFarms();
  Future<Farm> readFarm(String id);
  Future<void> saveFarm(Farm farm);
  Future<void> deleteFarm(String id);
  Stream<List<StoredEntity>> watchEntities(String farmId, EntityKind kind);
  Future<void> saveEntity(String farmId, EntityKind kind, StoredEntity entity);
  Future<void> deleteEntity(String farmId, EntityKind kind, String id);
  Future<void> close();
}
