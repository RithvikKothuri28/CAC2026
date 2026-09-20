import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';

/// Versioned, validated boundary shared by imports and both repository drivers.
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
    } on Object catch (error) {
      throw DataValidationFailure(
        'Farm data is invalid or incomplete. Check the imported assumptions.',
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
    return data;
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
