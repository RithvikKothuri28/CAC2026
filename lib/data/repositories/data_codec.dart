import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';

/// Versioned, validated boundary shared by imports and Firestore persistence.
class FarmDataCodec {
  static const schemaVersion = 1;
  static const maxDocumentBytes = 900000;

  static void validateHarvestBatch(Map<String, dynamic> data) {
    void textValue(Object? value, String name, int max) {
      if (value is! String || value.trim().isEmpty || value.length > max) {
        throw DataValidationFailure('$name must contain 1–$max characters.');
      }
    }

    void dateValue(Object? value, String name) {
      final date = value is String ? DateTime.tryParse(value) : null;
      if (value is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != value) {
        throw DataValidationFailure('$name must be a valid YYYY-MM-DD date.');
      }
    }

    textValue(data['crop'], 'Crop', 200);
    if (data.containsKey('field')) textValue(data['field'], 'Field', 200);
    if (data.containsKey('notes')) textValue(data['notes'], 'Notes', 2000);
    for (final key in ['plantingDate', 'harvestDate']) {
      if (data.containsKey(key)) dateValue(data[key], key);
    }
    if (data['plantingDate'] is String &&
        data['harvestDate'] is String &&
        (data['harvestDate'] as String).compareTo(
              data['plantingDate'] as String,
            ) <
            0) {
      throw const DataValidationFailure(
        'Harvest date must be on or after planting date.',
      );
    }
    for (final key in [
      'practices',
      'inputRecords',
      'handlingEvents',
      'storageEvents',
    ]) {
      if (!data.containsKey(key)) continue;
      final list = data[key];
      if (list is! List || list.length > 40) {
        throw DataValidationFailure('$key must contain at most 40 records.');
      }
      for (final entry in list) {
        if (key == 'practices') {
          textValue(entry, key, 200);
          continue;
        }
        if (entry is! Map ||
            entry.keys.any((k) => !['name', 'date', 'details'].contains(k))) {
          throw DataValidationFailure(
            '$key event fields must be name, date, or details.',
          );
        }
        textValue(entry['name'], '$key name', 200);
        if (entry.containsKey('date')) dateValue(entry['date'], '$key date');
        if (entry.containsKey('details')) {
          textValue(entry['details'], '$key details', 500);
        }
      }
    }
  }

  static void validateId(String id) {
    if (id.isEmpty ||
        id.length > 128 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const DataValidationFailure(
        'A record ID must contain only letters, digits, underscores or hyphens.',
      );
    }
  }

  static Map<String, dynamic> validatePayload(Map<String, dynamic> payload) {
    try {
      final encoded = jsonEncode(payload);
      if (utf8.encode(encoded).length > maxDocumentBytes) {
        throw const DataValidationFailure(
          'This record is too large to save. Export or split the data first.',
        );
      }
      return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw DataValidationFailure(
        'The record contains unsupported or non-finite values.',
        cause: error,
      );
    }
  }

  static Farm decodeFarm(Map<String, dynamic> json) {
    try {
      final migrated = migrate(json);
      final farm = Farm.fromJson(migrated);
      validateId(farm.id);
      farm.validate();
      return farm;
    } on AppFailure {
      rethrow;
    } on DomainFailure catch (error) {
      throw DataValidationFailure(error.message, cause: error);
    } on Object catch (error) {
      throw DataValidationFailure(
        'Farm data is invalid or incomplete. Check the imported assumptions.',
        cause: error,
      );
    }
  }

  /// Existing assignments may need correction after stricter validation ships.
  /// This read-only editing path preserves the original assignment and checks
  /// every other input/reference. It does not make an invalid farm calculable
  /// or savable: encodeFarm and all engines still run full strict validation.
  static Farm decodeFarmForEditing(Map<String, dynamic> json) {
    try {
      final farm = Farm.fromJson(migrate(json));
      validateId(farm.id);
      farm
          .copyWith(
            fields: [
              for (final field in farm.fields)
                field.copyWith(currentCropId: ''),
            ],
          )
          .validate();
      return farm;
    } on AppFailure {
      rethrow;
    } on DomainFailure catch (error) {
      throw DataValidationFailure(error.message, cause: error);
    } on Object catch (error) {
      throw DataValidationFailure(
        'Farm data could not be opened for editing. Check its crop references.',
        cause: error,
      );
    }
  }

  static Map<String, dynamic> encodeFarm(Farm farm) {
    try {
      validateId(farm.id);
      farm.validate();
      return validatePayload(farm.toJson());
    } on AppFailure {
      rethrow;
    } on DomainFailure catch (error) {
      throw DataValidationFailure(error.message, cause: error);
    } on Object catch (error) {
      throw DataValidationFailure(
        'Farm data could not be saved. Check the assumptions.',
        cause: error,
      );
    }
  }

  /// Version zero is the original unversioned export format. These additions
  /// describe structure only; missing economic/agronomic assumptions still fail.
  static Map<String, dynamic> migrate(Map<String, dynamic> input) {
    final data = validatePayload(input);
    final version = data['schemaVersion'] ?? 0;
    if (version is! int || version < 0 || version > schemaVersion) {
      throw const DataValidationFailure(
        'This farm uses an unsupported data version. Update FarmTwin before opening it.',
      );
    }
    if (version == 0) {
      data['schemaVersion'] = 1;
      data.putIfAbsent('scenarios', () => <dynamic>[]);
    }
    _normalizeCropReferences(data);
    return data;
  }

  /// Canonical IDs win. Only an unambiguous, exact legacy display name may be
  /// resolved; missing/ambiguous references never become inferred compatibility.
  /// Normalization is persisted only by the next explicitly accepted farm save.
  static void _normalizeCropReferences(Map<String, dynamic> data) {
    final crops = data['crops'];
    final fields = data['fields'];
    if (crops is! List || fields is! List) return;
    final ids = <String>{};
    final names = <String, List<String>>{};
    for (final crop in crops) {
      if (crop is! Map || crop['id'] is! String || crop['name'] is! String) {
        continue;
      }
      final id = crop['id'] as String;
      validateId(id);
      if (!ids.add(id)) {
        throw const DataValidationFailure(
          'Crop profiles have duplicate IDs. Correct the duplicate profiles before loading this farm.',
        );
      }
      names.putIfAbsent((crop['name'] as String).trim(), () => []).add(id);
    }
    String resolve(Object? value, String fieldName, {bool allowEmpty = false}) {
      if (value is! String) {
        throw DataValidationFailure(
          'Crop references for $fieldName must be crop IDs.',
        );
      }
      if (ids.contains(value)) return value;
      final reference = value.trim();
      if (allowEmpty && reference.isEmpty) return '';
      if (ids.contains(reference)) return reference;
      final matches = names[reference] ?? const <String>[];
      if (matches.length == 1) return matches.single;
      throw DataValidationFailure(
        matches.length > 1
            ? 'Crop reference "$reference" for $fieldName matches multiple profiles. Select the intended crop by ID.'
            : 'Crop reference "$reference" for $fieldName does not match a crop profile. Restore the profile or correct the reference.',
      );
    }

    List<String> resolveList(Object? value, String fieldName) {
      if (value is! List) {
        throw DataValidationFailure(
          'Compatible crops for $fieldName must be a list of crop IDs.',
        );
      }
      return value.map((entry) => resolve(entry, fieldName)).toList();
    }

    for (final field in fields) {
      if (field is! Map) continue;
      final name = field['name'] is String
          ? field['name'] as String
          : 'this field';
      if (field.containsKey('currentCropId')) {
        field['currentCropId'] = resolve(
          field['currentCropId'],
          name,
          allowEmpty: true,
        );
      }
      final canonical = field.containsKey('compatibleCropIds')
          ? resolveList(field['compatibleCropIds'], name)
          : null;
      final legacy = field.containsKey('allowedCropIds')
          ? resolveList(field['allowedCropIds'], name)
          : null;
      if (canonical != null &&
          legacy != null &&
          (canonical.length != legacy.length ||
              !canonical.toSet().containsAll(legacy) ||
              !legacy.toSet().containsAll(canonical))) {
        throw DataValidationFailure(
          'Conflicting compatibility lists for $name. Choose the intended compatible crops before importing this farm.',
        );
      }
      field['compatibleCropIds'] = canonical ?? legacy ?? <String>[];
      field.remove('allowedCropIds');
      if (field.containsKey('cropHistory')) {
        field['cropHistory'] = resolveList(field['cropHistory'], name);
      }
    }
  }
}

class FarmExportService {
  const FarmExportService();

  String exportFarm(Farm farm) => const JsonEncoder.withIndent('  ').convert({
    'format': 'farmtwin-farm',
    'schemaVersion': FarmDataCodec.schemaVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'data': FarmDataCodec.encodeFarm(farm),
  });

  Farm importFarm(String input, {required String id}) {
    FarmDataCodec.validateId(id);
    if (utf8.encode(input).length > FarmDataCodec.maxDocumentBytes) {
      throw const DataValidationFailure(
        'The imported farm exceeds the supported document size.',
      );
    }
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map) throw const FormatException('Expected JSON object');
      final root = Map<String, dynamic>.from(decoded);
      if (root.containsKey('format') && root['format'] != 'farmtwin-farm') {
        throw const DataValidationFailure(
          'This file is not a FarmTwin farm export.',
        );
      }
      if (root.containsKey('format') &&
          root['schemaVersion'] != FarmDataCodec.schemaVersion) {
        throw const DataValidationFailure(
          'This export version is not supported.',
        );
      }
      final data = Map<String, dynamic>.from((root['data'] ?? root) as Map);
      data['id'] = id;
      // Imported files cannot assert external verification or user entry.
      // Preserve previous provenance as quality metadata for auditability.
      final importedAt = DateTime.now().toUtc().toIso8601String();
      void markImported(Map<String, dynamic> model) {
        final prior = model['provenance'];
        model['provenance'] = {
          'source': 'imported',
          'updatedAt': importedAt,
          'quality': prior is Map
              ? 'Imported; original source: ${prior['source'] ?? 'unspecified'}'
              : 'Imported; original source unspecified',
        };
      }

      markImported(data);
      for (final key in ['fields', 'crops', 'expenses', 'debts']) {
        final values = data[key];
        if (values is List) {
          for (final value in values) {
            if (value is Map<String, dynamic>) markImported(value);
          }
        }
      }
      return FarmDataCodec.decodeFarm(data);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw DataValidationFailure(
        'The file does not contain valid FarmTwin farm data.',
        cause: error,
      );
    }
  }
}
