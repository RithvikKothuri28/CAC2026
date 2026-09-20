import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import 'cloud_services.dart';
import 'firebase_auth_repository.dart';
import 'firebase_failure.dart';
import 'firebase_privacy_service.dart';
import 'firestore_farm_repository.dart';
import 'user_settings.dart';

class FirebaseServices {
  const FirebaseServices({
    required this.auth,
    required this.farms,
    required this.settings,
    required this.privacy,
    required this.passports,
    required this.explanations,
    required this.features,
  });
  final FirebaseAuthRepository auth;
  final FirestoreFarmRepository farms;
  final FirestoreSettingsRepository settings;
  final FirebasePrivacyService privacy;
  final HarvestPassportService passports;
  final CloudExplanationService explanations;
  final FeatureConfig features;
}

class FirebaseBootstrap {
  static Future<FirebaseServices?> initialize(AppConfig config) async {
    config.validate();
    final options = config.firebaseOptions;
    if (options == null) return null;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      throw const ConfigurationFailure(
        'Cloud services are supported on Android, iOS, macOS and web. Use an explicit local Sample Farm on this platform.',
      );
    }
    try {
      final app = await Firebase.initializeApp(options: options);
      final auth = FirebaseAuth.instanceFor(app: app);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      final functions = FirebaseFunctions.instanceFor(
        app: app,
        region: config.functionsRegion,
      );
      if (config.useEmulators) {
        await auth.useAuthEmulator(
          config.emulatorHost,
          config.authEmulatorPort,
        );
        firestore.useFirestoreEmulator(
          config.emulatorHost,
          config.firestoreEmulatorPort,
        );
        functions.useFunctionsEmulator(
          config.emulatorHost,
          config.functionsEmulatorPort,
        );
      } else {
        await FirebaseAppCheck.instanceFor(app: app).activate(
          providerAndroid: config.isDevelopment && kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: config.isDevelopment && kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
          providerWeb: kIsWeb
              ? ReCaptchaV3Provider(config.webAppCheckSiteKey)
              : null,
        );
      }
      // Native persistence supports local reads and queued writes. Browser
      // persistence is opt-in because this app can contain financial records.
      if (!kIsWeb) {
        firestore.settings = const Settings(persistenceEnabled: true);
      }
      final privacy = FirebasePrivacyService(
        preferences: await SharedPreferences.getInstance(),
        analytics: FirebaseAnalytics.instanceFor(app: app),
        crashlytics: kIsWeb ? null : FirebaseCrashlytics.instance,
        allowCollection: !config.useEmulators,
      );
      // Do not restore another account's device-level consent before auth is known.
      await privacy.apply(const UserSettings());
      var features = const FeatureConfig();
      if (!config.useEmulators) {
        try {
          final remote = FirebaseRemoteConfig.instanceFor(app: app);
          await remote.setDefaults({
            'cloud_assistant_enabled': false,
            'harvest_publishing_enabled': false,
          });
          await remote.setConfigSettings(
            RemoteConfigSettings(
              fetchTimeout: const Duration(seconds: 8),
              minimumFetchInterval: const Duration(hours: 1),
            ),
          );
          await remote.fetchAndActivate();
          features = FeatureConfig(
            cloudAssistantEnabled: remote.getBool('cloud_assistant_enabled'),
            harvestPublishingEnabled: remote.getBool(
              'harvest_publishing_enabled',
            ),
          );
        } on Object catch (error) {
          SafeAppLogger(
            development: config.isDevelopment,
          ).warning('remote_config_fetch', code: firebaseFailure(error).code);
        }
      } else {
        // Explicit emulator deployment supports testing publishing without any
        // request to production Remote Config or analytics.
        features = const FeatureConfig(harvestPublishingEnabled: true);
      }
      return FirebaseServices(
        auth: FirebaseAuthRepository(auth, functions),
        farms: FirestoreFarmRepository(firestore, auth, functions),
        settings: FirestoreSettingsRepository(firestore, auth),
        privacy: privacy,
        features: features,
        passports: HarvestPassportService(functions, config, features),
        explanations: CloudExplanationService(functions, features, privacy),
      );
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw ConfigurationFailure(
        'Cloud services could not start. Check environment configuration or retry. Local sample inputs remain an explicit option.',
        cause: error,
      );
    }
  }
}
