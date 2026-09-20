import 'dart:io';

import 'package:farmtwin/data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> validBatch() => {
    'crop': 'Test crop',
    'field': 'Test field',
    'plantingDate': '2024-02-29',
    'harvestDate': '2024-09-01',
    'practices': ['Farmer supplied practice'],
    'inputRecords': [
      {'name': 'Input', 'date': '2024-03-01', 'details': 'Farmer supplied'},
    ],
    'handlingEvents': [
      {'name': 'Handling'},
    ],
    'storageEvents': <dynamic>[],
    'notes': 'Test notes',
  };

  test('harvest accepts optional records and exact backend length limits', () {
    expect(
      () => FarmDataCodec.validateHarvestBatch({'crop': 'Crop'}),
      returnsNormally,
    );
    expect(
      () => FarmDataCodec.validateHarvestBatch(validBatch()),
      returnsNormally,
    );
    final batch = validBatch()
      ..['crop'] = 'a' * 200
      ..['notes'] = 'n' * 2000
      ..['practices'] = List.filled(40, 'p' * 200)
      ..['handlingEvents'] = [
        {'name': 'e' * 200, 'details': 'd' * 500},
      ];
    expect(() => FarmDataCodec.validateHarvestBatch(batch), returnsNormally);
  });

  test('harvest rejects empty, overlong and malformed public field data', () {
    for (final change in <Map<String, dynamic>>[
      {'crop': ''},
      {'crop': ' '},
      {'crop': 'a' * 201},
      {'field': ''},
      {'notes': 'a' * 2001},
      {'practices': List.filled(41, 'practice')},
      {
        'practices': [42],
      },
      {
        'practices': ['a' * 201],
      },
      {
        'inputRecords': [
          {'name': 'Input', 'secret': 'not allowed'},
        ],
      },
      {
        'handlingEvents': [
          {'name': 'event', 'details': 'a' * 501},
        ],
      },
      {
        'storageEvents': [
          {'name': ''},
        ],
      },
      {
        'handlingEvents': ['not an event map'],
      },
    ]) {
      expect(
        () => FarmDataCodec.validateHarvestBatch({...validBatch(), ...change}),
        throwsA(isA<DataValidationFailure>()),
        reason: change.keys.join(','),
      );
    }
  });

  test(
    'harvest rejects impossible dates, timestamps and reversed date order',
    () {
      for (final invalid in [
        '2023-02-29',
        '2024-02-30',
        '2024-13-01',
        '2024-01-32',
        '2024-01-01T00:00:00Z',
        '2024-1-01',
      ]) {
        expect(
          () => FarmDataCodec.validateHarvestBatch({
            ...validBatch(),
            'harvestDate': invalid,
          }),
          throwsA(isA<DataValidationFailure>()),
          reason: invalid,
        );
      }
      expect(
        () => FarmDataCodec.validateHarvestBatch({
          ...validBatch(),
          'harvestDate': '2024-02-28',
        }),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => FarmDataCodec.validateHarvestBatch({
          ...validBatch(),
          'inputRecords': [
            {'name': 'Input', 'date': '2024-02-30'},
          ],
        }),
        throwsA(isA<DataValidationFailure>()),
      );
    },
  );

  test(
    'sample repository enforces harvest boundary and replacement removes omitted fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = await SampleFarmRepository.open(
        loadAsset: (path) => File(path).readAsString(),
      );
      final farm = await repository.loadSample();
      await expectLater(
        repository.saveEntity(
          farm.id,
          EntityKind.harvestBatches,
          const StoredEntity(id: 'bad', data: {'crop': ''}),
        ),
        throwsA(isA<DataValidationFailure>()),
      );
      await repository.saveEntity(
        farm.id,
        EntityKind.harvestBatches,
        StoredEntity(id: 'batch', data: validBatch()),
      );
      await repository.saveEntity(
        farm.id,
        EntityKind.harvestBatches,
        const StoredEntity(id: 'batch', data: {'crop': 'Crop'}),
      );
      final records = await repository
          .watchEntities(farm.id, EntityKind.harvestBatches)
          .first;
      expect(records.single.data, {'crop': 'Crop'});
      await repository.close();
    },
  );
}
