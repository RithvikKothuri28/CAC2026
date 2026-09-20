import 'dart:convert';
import 'dart:io';

import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<String> sampleAsset(String path) => File(path).readAsString();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sample workspace is empty until explicit load and requires no Firebase',
    () async {
      final repository = await SampleFarmRepository.open(
        loadAsset: sampleAsset,
      );
      expect(await repository.watchFarms().first, isEmpty);
      expect(Firebase.apps, isEmpty);
      final farm = await repository.loadSample();
      expect(farm.provenance.source, DataSourceType.sample);
      expect(await repository.watchFarms().first, hasLength(1));
      expect(Firebase.apps, isEmpty);
      await repository.close();
    },
  );

  test(
    'farm edits and entity CRUD survive reopening, then reset removes summaries',
    () async {
      var repository = await SampleFarmRepository.open(loadAsset: sampleAsset);
      final initial = await repository.loadSample();
      await repository.saveFarm(initial.copyWith(name: 'Edited sample'));
      await repository.saveEntity(
        initial.id,
        EntityKind.scenarios,
        const StoredEntity(
          id: 'scenario-1',
          data: {'name': 'Farmer scenario', 'priceMultiplier': 0.8},
        ),
      );
      await repository.saveEntity(
        initial.id,
        EntityKind.optimizationRuns,
        const StoredEntity(id: 'run-1', data: {'candidatesGenerated': 12}),
      );
      await repository.close();
      repository = await SampleFarmRepository.open(loadAsset: sampleAsset);
      expect((await repository.readFarm(initial.id)).name, 'Edited sample');
      expect(
        (await repository.watchEntities(initial.id, EntityKind.scenarios).first)
            .single
            .data['priceMultiplier'],
        0.8,
      );
      await repository.deleteEntity(
        initial.id,
        EntityKind.scenarios,
        'scenario-1',
      );
      expect(
        await repository.watchEntities(initial.id, EntityKind.scenarios).first,
        isEmpty,
      );
      final reset = await repository.loadSample();
      expect(reset.name, initial.name);
      expect(
        await repository
            .watchEntities(initial.id, EntityKind.optimizationRuns)
            .first,
        isEmpty,
      );
      await repository.deleteFarm(initial.id);
      await repository.close();
      repository = await SampleFarmRepository.open(loadAsset: sampleAsset);
      expect(await repository.watchFarms().first, isEmpty);
      await repository.close();
    },
  );

  test('concurrent local saves preserve both records', () async {
    final repository = await SampleFarmRepository.open(loadAsset: sampleAsset);
    final farm = await repository.loadSample();
    await Future.wait([
      repository.saveEntity(
        farm.id,
        EntityKind.scenarios,
        const StoredEntity(id: 'a', data: {'name': 'A'}),
      ),
      repository.saveEntity(
        farm.id,
        EntityKind.scenarios,
        const StoredEntity(id: 'b', data: {'name': 'B'}),
      ),
    ]);
    expect(
      await repository.watchEntities(farm.id, EntityKind.scenarios).first,
      hasLength(2),
    );
    await repository.close();
  });

  test(
    'malformed persisted data yields typed failure and is not silently replaced',
    () async {
      SharedPreferences.setMockInitialValues({
        SampleFarmRepository.storageKey: '{broken json',
      });
      await expectLater(
        SampleFarmRepository.open(loadAsset: sampleAsset),
        throwsA(isA<StorageFailure>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          SampleFarmRepository.storageKey,
        ),
        '{broken json',
      );
    },
  );

  test(
    'JSON export/import preserves all economics and explicitly labels imported assumptions',
    () async {
      final original = FarmDataCodec.decodeFarm(
        Map<String, dynamic>.from(
          jsonDecode(await sampleAsset('assets/sample/sample_farm.json'))
              as Map,
        ),
      );
      const transfer = FarmExportService();
      final imported = transfer.importFarm(
        transfer.exportFarm(original),
        id: 'imported-farm',
      );
      expect(imported.id, 'imported-farm');
      expect(imported.provenance.source, DataSourceType.imported);
      expect(imported.crops.first.provenance.source, DataSourceType.imported);
      expect(
        imported.crops.first.pricePerUnit,
        original.crops.first.pricePerUnit,
      );
      expect(imported.fields.first.acres, original.fields.first.acres);
      expect(imported.settings.toJson(), original.settings.toJson());
      expect(imported.provenance.quality, contains('sample'));
    },
  );

  test(
    'imports reject unsupported versions, invalid IDs, missing assumptions and nonfinite JSON',
    () async {
      final data = Map<String, dynamic>.from(
        jsonDecode(await sampleAsset('assets/sample/sample_farm.json')) as Map,
      );
      expect(
        () => FarmDataCodec.decodeFarm({...data, 'schemaVersion': 99}),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => FarmDataCodec.decodeFarm({...data, 'id': '../escape'}),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => FarmDataCodec.decodeFarm({...data}..remove('settings')),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => FarmDataCodec.validatePayload({'value': double.nan}),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(
        () => const FarmExportService().importFarm('{bad json', id: 'new'),
        throwsA(isA<DataValidationFailure>()),
      );
    },
  );

  test(
    'unversioned data migrates structure without inventing economic inputs',
    () async {
      final data =
          Map<String, dynamic>.from(
              jsonDecode(await sampleAsset('assets/sample/sample_farm.json'))
                  as Map,
            )
            ..remove('schemaVersion')
            ..remove('scenarios');
      final farm = FarmDataCodec.decodeFarm(data);
      expect(farm.schemaVersion, 1);
      expect(farm.scenarios, isEmpty);
      expect(
        farm.crops.first.pricePerUnit,
        ((data['crops'] as List).first as Map)['pricePerUnit'],
      );
    },
  );

  test(
    'deployment safeguards forbid production emulators and incomplete production',
    () {
      const demo = FirebaseOptions(
        apiKey: 'emulator-key',
        appId: 'emulator-app',
        messagingSenderId: 'test-sender',
        projectId: 'demo-farmtwin',
      );
      expect(
        () =>
            const AppConfig(environment: AppEnvironment.production).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(
        () => const AppConfig(
          environment: AppEnvironment.production,
          firebaseOptions: demo,
          useEmulators: true,
        ).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(
        () => const AppConfig(
          environment: AppEnvironment.development,
          firebaseOptions: demo,
          useEmulators: true,
        ).validate(),
        returnsNormally,
      );
      expect(
        () => const AppConfig(
          environment: AppEnvironment.development,
          publicPassportBaseUrl: 'javascript:bad',
        ).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
    },
  );

  test(
    'privacy consent defaults off and persists only explicit choices',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final privacy = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      await privacy.restore();
      expect(privacy.current.analyticsConsent, isFalse);
      expect(privacy.current.cloudAssistantConsent, isFalse);
      await privacy.apply(const UserSettings(cloudAssistantConsent: true));
      final reopened = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      await reopened.restore();
      expect(reopened.current.cloudAssistantConsent, isTrue);
      expect(reopened.current.crashReportingConsent, isFalse);
    },
  );
}
