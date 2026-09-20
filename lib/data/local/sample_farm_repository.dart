import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';
import '../repositories/data_codec.dart';
import '../repositories/farm_repository.dart';

/// An explicitly selected, persisted sample workspace. No Firebase dependency.
class SampleFarmRepository implements FarmRepository {
  SampleFarmRepository._(this._preferences, this._loadAsset);
  static const storageKey = 'farmtwin.sample.workspace.v1';
  final SharedPreferences _preferences;
  final Future<String> Function(String) _loadAsset;
  final _changes = StreamController<void>.broadcast(sync: true);
  Map<String, Farm> _farms = {};
  Map<String, List<StoredEntity>> _entities = {};
  Future<void> _pending = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<SampleFarmRepository> open({
    SharedPreferences? preferences,
    Future<String> Function(String)? loadAsset,
  }) async {
    try {
      final repository = SampleFarmRepository._(
        preferences ?? await SharedPreferences.getInstance(),
        loadAsset ?? rootBundle.loadString,
      );
      final stored = repository._preferences.getString(storageKey);
      if (stored != null) {
        final state = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        if (state['schemaVersion'] != 1) {
          throw const DataValidationFailure(
            'The saved Sample Farm uses an unsupported version. Export it before resetting.',
          );
        }
        repository._farms = {
          for (final json in state['farms'] as List)
            (json as Map)['id'] as String: FarmDataCodec.decodeFarm(
              Map<String, dynamic>.from(json),
            ),
        };
        repository._entities = {
          for (final entry
              in (state['entities'] as Map<String, dynamic>).entries)
            entry.key: (entry.value as List)
                .map(
                  (value) => StoredEntity.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList(),
        };
      }
      return repository;
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw StorageFailure(
        'The saved Sample Farm could not be opened. Its data has not been replaced.',
        cause: error,
      );
    }
  }

  Future<Farm> loadSample() => _serialize(() async {
    try {
      final contents = await _loadAsset('assets/sample/sample_farm.json');
      final farm = FarmDataCodec.decodeFarm(
        Map<String, dynamic>.from(jsonDecode(contents) as Map),
      );
      if (farm.provenance.source != DataSourceType.sample) {
        throw const DataValidationFailure(
          'The Sample Farm must declare its sample provenance.',
        );
      }
      await _persist({farm.id: farm}, {});
      return farm;
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw StorageFailure('Sample inputs could not be loaded.', cause: error);
    }
  });

  Future<void> _persist(
    Map<String, Farm> farms,
    Map<String, List<StoredEntity>> entities,
  ) async {
    try {
      final state = jsonEncode({
        'schemaVersion': 1,
        'farms': farms.values.map(FarmDataCodec.encodeFarm).toList(),
        'entities': entities.map(
          (key, value) =>
              MapEntry(key, value.map((entity) => entity.toJson()).toList()),
        ),
      });
      if (!await _preferences.setString(storageKey, state)) {
        throw const StorageFailure(
          'The device could not save your Sample Farm changes.',
        );
      }
      _farms = farms;
      _entities = entities;
      _changes.add(null);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw StorageFailure(
        'The device could not save your Sample Farm changes.',
        cause: error,
      );
    }
  }

  @override
  Stream<List<Farm>> watchFarms() async* {
    yield List.unmodifiable(_farms.values);
    await for (final _ in _changes.stream) {
      yield List.unmodifiable(_farms.values);
    }
  }

  @override
  Future<Farm> readFarm(String id) async {
    final farm = _farms[id];
    if (farm == null) {
      throw const RepositoryUnavailableFailure(
        'The farm was not found in this workspace.',
      );
    }
    return farm;
  }

  @override
  Future<void> saveFarm(Farm farm) => _serialize(() async {
    FarmDataCodec.encodeFarm(farm);
    await _persist({..._farms, farm.id: farm}, {..._entities});
  });

  @override
  Future<void> deleteFarm(String id) => _serialize(() async {
    final farms = {..._farms}..remove(id);
    final entities = {..._entities}
      ..removeWhere((key, _) => key.startsWith('$id/'));
    await _persist(farms, entities);
  });

  @override
  Stream<List<StoredEntity>> watchEntities(
    String farmId,
    EntityKind kind,
  ) async* {
    final key = '$farmId/${kind.name}';
    yield List.unmodifiable(_entities[key] ?? []);
    await for (final _ in _changes.stream) {
      yield List.unmodifiable(_entities[key] ?? []);
    }
  }

  @override
  Future<void> saveEntity(
    String farmId,
    EntityKind kind,
    StoredEntity entity,
  ) => _serialize(() async {
    await readFarm(farmId);
    FarmDataCodec.validateId(entity.id);
    final data = FarmDataCodec.validatePayload(entity.data);
    if (kind == EntityKind.harvestBatches)
      FarmDataCodec.validateHarvestBatch(data);
    final key = '$farmId/${kind.name}';
    final values = [...?_entities[key]]
      ..removeWhere((value) => value.id == entity.id);
    values.add(StoredEntity(id: entity.id, data: data));
    await _persist({..._farms}, {..._entities, key: values});
  });

  @override
  Future<void> deleteEntity(String farmId, EntityKind kind, String id) =>
      _serialize(() async {
        final key = '$farmId/${kind.name}';
        final values = [...?_entities[key]]
          ..removeWhere((value) => value.id == id);
        await _persist({..._farms}, {..._entities, key: values});
      });

  @override
  Future<void> close() async {
    await _pending;
    await _changes.close();
  }
}
