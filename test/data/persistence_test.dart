import 'dart:convert';
import 'dart:io';

import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:farmtwin/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<String> fixture(String path) => File(path).readAsString();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'JSON export/import preserves all economics and explicitly labels imported assumptions',
    () async {
      final original = FarmDataCodec.decodeFarm(
        Map<String, dynamic>.from(
          jsonDecode(await fixture('test/fixtures/farm.json')) as Map,
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
        jsonDecode(await fixture('test/fixtures/farm.json')) as Map,
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
              jsonDecode(await fixture('test/fixtures/farm.json')) as Map,
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
    'entered onboarding metadata survives codec roundtrip and edits',
    () async {
      final original = FarmDataCodec.decodeFarm(
        jsonDecode(await fixture('test/fixtures/farm.json'))
            as Map<String, dynamic>,
      );
      expect(original.country, isNull);
      expect(original.region, isNull);
      expect(original.declaredAcres, isNull);
      final entered = original.copyWith(
        country: 'New Zealand',
        region: 'Canterbury',
        declaredAcres: 137.25,
        settings: original.settings.copyWith(currencyCode: 'NZD'),
      );
      final restored = FarmDataCodec.decodeFarm(
        FarmDataCodec.encodeFarm(entered),
      );
      expect(restored.country, 'New Zealand');
      expect(restored.region, 'Canterbury');
      expect(restored.declaredAcres, 137.25);
      expect(restored.settings.currencyCode, 'NZD');
      expect(restored.acreage, original.acreage);
      expect(restored.copyWith(name: 'Edited name').country, 'New Zealand');
      expect(restored.copyWith(name: 'Edited name').declaredAcres, 137.25);
      for (final invalid in <Map<String, dynamic>>[
        {'country': ''},
        {'region': ' '},
        {'declaredAcres': 0},
        {'declaredAcres': -1},
        {'declaredAcres': double.infinity},
        {'declaredAcres': '137.25'},
      ]) {
        expect(
          () => FarmDataCodec.decodeFarm({...entered.toJson(), ...invalid}),
          throwsA(isA<DataValidationFailure>()),
          reason: invalid.keys.single,
        );
      }
    },
  );

  test(
    'default configuration uses generated production Firebase without emulators',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final config = AppConfig.fromEnvironment();
      expect(config.environment, AppEnvironment.production);
      expect(config.usesGeneratedFirebaseOptions, isTrue);
      expect(config.firebaseOptions, DefaultFirebaseOptions.android);
      expect(config.firebaseOptions!.projectId, 'farmtwin-f64bd');
      expect(config.useEmulators, isFalse);
      expect(config.enableConnectivityDiagnostic, isFalse);
      for (final options in [
        DefaultFirebaseOptions.web,
        DefaultFirebaseOptions.android,
        DefaultFirebaseOptions.ios,
      ]) {
        expect(options.projectId, 'farmtwin-f64bd');
        expect(options.appId, startsWith('1:923406327267:'));
      }
    },
  );

  test('only explicit development demo configuration may use emulators', () {
    const demo = FirebaseOptions(
      apiKey: 'emulator-key',
      appId: 'emulator-app',
      messagingSenderId: 'test-sender',
      projectId: 'demo-farmtwin',
    );
    for (final environment in AppEnvironment.values) {
      expect(
        () => AppConfig(environment: environment).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(
        () => AppConfig(
          environment: environment,
          firebaseOptions: demo,
        ).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(
        () => AppConfig(
          environment: environment,
          firebaseOptions: const FirebaseOptions(
            projectId: 'wrong-project',
            apiKey: 'test-key',
            appId: 'test-app',
            messagingSenderId: 'test-sender',
          ),
        ).validate(),
        throwsA(isA<ConfigurationFailure>()),
      );
    }
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
        firebaseOptions: DefaultFirebaseOptions.web,
        useEmulators: true,
      ).validate(),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(
      () => const AppConfig(
        environment: AppEnvironment.development,
        firebaseOptions: DefaultFirebaseOptions.web,
        publicPassportBaseUrl: 'javascript:bad',
      ).validate(),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(
      () => const AppConfig(
        environment: AppEnvironment.production,
        firebaseOptions: DefaultFirebaseOptions.web,
        enableConnectivityDiagnostic: true,
      ).validate(),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(
      () => const AppConfig(
        environment: AppEnvironment.development,
        firebaseOptions: DefaultFirebaseOptions.web,
        enableConnectivityDiagnostic: true,
      ).validate(),
      returnsNormally,
    );
  });

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
