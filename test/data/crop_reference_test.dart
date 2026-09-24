import 'dart:convert';
import 'dart:io';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> input() {
  final data =
      jsonDecode(File('test/fixtures/farm.json').readAsStringSync())
          as Map<String, dynamic>;
  final crop = Map<String, dynamic>.from((data['crops'] as List).first as Map)
    ..['id'] = 'crop-uuid-corn-001'
    ..['name'] = 'Corn'
    ..['requiresIrrigation'] = true;
  final field = Map<String, dynamic>.from((data['fields'] as List).first as Map)
    ..['id'] = 'field-uuid-001'
    ..['name'] = 'Field 1'
    ..['currentCropId'] = crop['id']
    ..['compatibleCropIds'] = [crop['id']]
    ..['cropHistory'] = [crop['id']]
    ..['irrigated'] = true;
  data['crops'] = [crop];
  data['fields'] = [field];
  return data;
}

Map<String, dynamic> field(Map<String, dynamic> data) =>
    (data['fields'] as List).single as Map<String, dynamic>;
void main() {
  test(
    'Firestore aggregate round-trip preserves stable IDs after crop rename',
    () {
      final farm = FarmDataCodec.decodeFarm(input());
      final edited = farm.copyWith(
        crops: [farm.crops.single.copyWith(name: 'Corn renamed')],
      );
      final reopened = FarmDataCodec.decodeFarm(
        FarmDataCodec.encodeFarm(edited),
      );
      expect(reopened.fields.single.currentCropId, 'crop-uuid-corn-001');
      expect(reopened.fields.single.compatibleCropIds, ['crop-uuid-corn-001']);
      expect(reopened.fields.single.cropHistory, ['crop-uuid-corn-001']);
      reopened.validatePlan(reopened.currentPlan);
    },
  );
  test(
    'legacy exact names and allowedCropIds normalize without adding compatibility',
    () {
      final data = input();
      final f = field(data);
      f['currentCropId'] = 'Corn';
      f['allowedCropIds'] = ['Corn'];
      f.remove('compatibleCropIds');
      f['cropHistory'] = ['Corn'];
      final farm = FarmDataCodec.decodeFarm(data);
      expect(farm.fields.single.currentCropId, farm.crops.single.id);
      expect(farm.fields.single.compatibleCropIds, [farm.crops.single.id]);
      expect(farm.fields.single.cropHistory, [farm.crops.single.id]);
      expect(
        field(FarmDataCodec.encodeFarm(farm)).containsKey('allowedCropIds'),
        isFalse,
      );
      expect(
        f['currentCropId'],
        'Corn',
        reason: 'Read migration must not mutate caller input.',
      );
    },
  );
  test('stable ID wins over another crop display name', () {
    final data = input();
    final crops = data['crops'] as List;
    crops.add({
      ...Map<String, dynamic>.from(crops.single as Map),
      'id': 'second-id',
      'name': 'crop-uuid-corn-001',
    });
    expect(
      FarmDataCodec.decodeFarm(data).fields.single.currentCropId,
      'crop-uuid-corn-001',
    );
  });
  test('ambiguous or missing legacy names surface actionable validation', () {
    final data = input();
    final crops = data['crops'] as List;
    crops.add({
      ...Map<String, dynamic>.from(crops.single as Map),
      'id': 'second-id',
    });
    field(data)['currentCropId'] = 'Corn';
    expect(
      () => FarmDataCodec.decodeFarm(data),
      throwsA(
        isA<DataValidationFailure>().having(
          (e) => e.message,
          'message',
          contains('multiple profiles'),
        ),
      ),
    );
    field(data)['currentCropId'] = 'Unknown';
    expect(
      () => FarmDataCodec.decodeFarm(data),
      throwsA(
        isA<DataValidationFailure>().having(
          (e) => e.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
  });
  test('conflicting compatibility aliases are rejected rather than merged', () {
    final data = input();
    field(data)['allowedCropIds'] = [];
    expect(
      () => FarmDataCodec.decodeFarm(data),
      throwsA(
        isA<DataValidationFailure>().having(
          (e) => e.message,
          'message',
          contains('Conflicting'),
        ),
      ),
    );
    final crops = data['crops'] as List;
    crops.add({
      ...Map<String, dynamic>.from(crops.single as Map),
      'id': 'second-id',
    });
    field(data)['compatibleCropIds'] = ['crop-uuid-corn-001', 'second-id'];
    field(data)['allowedCropIds'] = [
      'crop-uuid-corn-001',
      'crop-uuid-corn-001',
    ];
    expect(
      () => FarmDataCodec.decodeFarm(data),
      throwsA(
        isA<DataValidationFailure>().having(
          (e) => e.message,
          'message',
          contains('Conflicting'),
        ),
      ),
    );
  });
  test('missing compatibility never implies all crops are allowed', () {
    final data = input();
    field(data).remove('compatibleCropIds');
    expect(
      () => FarmDataCodec.decodeFarm(data),
      throwsA(isA<DataValidationFailure>()),
    );
    final editing = FarmDataCodec.decodeFarmForEditing(data);
    expect(editing.fields.single.compatibleCropIds, isEmpty);
    expect(editing.fields.single.currentCropId, 'crop-uuid-corn-001');
    expect(
      () => FarmDataCodec.encodeFarm(editing),
      throwsA(isA<DataValidationFailure>()),
    );
  });
  test(
    'legacy irrigation mismatch is editable but never silently repaired or calculable',
    () {
      final data = input();
      field(data)['irrigated'] = false;
      expect(
        () => FarmDataCodec.decodeFarm(data),
        throwsA(
          isA<DataValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('irrigation'),
          ),
        ),
      );
      final editing = FarmDataCodec.decodeFarmForEditing(data);
      expect(editing.fields.single.irrigated, isFalse);
      expect(editing.fields.single.currentCropId, 'crop-uuid-corn-001');
      expect(
        () => FarmDataCodec.encodeFarm(editing),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => const OptimizationEngine().run(editing),
        throwsA(isA<ValidationFailure>()),
      );
      final corrected = editing.copyWith(
        fields: [editing.fields.single.copyWith(irrigated: true)],
      );
      final saved = FarmDataCodec.decodeFarm(
        FarmDataCodec.encodeFarm(corrected),
      );
      saved.validatePlan(saved.currentPlan);
    },
  );
  test(
    'empty field assignment and compatibility survive persistence as incomplete inputs',
    () {
      final data = input();
      field(data)['currentCropId'] = '';
      field(data)['compatibleCropIds'] = [];
      final farm = FarmDataCodec.decodeFarm(
        FarmDataCodec.encodeFarm(FarmDataCodec.decodeFarm(data)),
      );
      expect(farm.fields.single.currentCropId, isEmpty);
      expect(
        () => farm.validate(requireReady: true),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );
}
