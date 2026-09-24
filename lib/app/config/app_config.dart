import 'package:firebase_core/firebase_core.dart';

import '../../core/errors/app_failure.dart';
import '../../firebase_options.dart';

enum AppEnvironment { development, staging, production }

/// Public client configuration. Server credentials never belong in this class.
class AppConfig {
  const AppConfig({
    required this.environment,
    this.firebaseOptions,
    this.useEmulators = false,
    this.emulatorHost = '127.0.0.1',
    this.authEmulatorPort = 9099,
    this.firestoreEmulatorPort = 8080,
    this.functionsEmulatorPort = 5001,
    this.functionsRegion = 'us-central1',
    this.webAppCheckSiteKey = '',
    this.publicPassportBaseUrl = '',
    this.enableConnectivityDiagnostic = false,
    this.usesGeneratedFirebaseOptions = false,
  });

  final AppEnvironment environment;
  final FirebaseOptions? firebaseOptions;
  final bool useEmulators;
  final String emulatorHost;
  final int authEmulatorPort;
  final int firestoreEmulatorPort;
  final int functionsEmulatorPort;
  final String functionsRegion;
  final String webAppCheckSiteKey;
  final String publicPassportBaseUrl;
  final bool enableConnectivityDiagnostic;
  final bool usesGeneratedFirebaseOptions;
  bool get isDevelopment => environment == AppEnvironment.development;
  bool get firebaseConfigured => firebaseOptions != null;

  factory AppConfig.fromEnvironment() {
    const environmentName = String.fromEnvironment(
      'ENVIRONMENT',
      defaultValue: 'production',
    );
    final environment = AppEnvironment.values
        .where((item) => item.name == environmentName)
        .firstOrNull;
    if (environment == null) {
      throw const ConfigurationFailure(
        'ENVIRONMENT must be development, staging, or production.',
      );
    }
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final supplied = [
      projectId,
      apiKey,
      appId,
      senderId,
    ].where((item) => item.isNotEmpty).length;
    if (supplied != 0 && supplied != 4) {
      throw const ConfigurationFailure(
        'Firebase configuration is incomplete. Supply project, API key, application ID, and sender ID.',
      );
    }
    final config = AppConfig(
      environment: environment,
      firebaseOptions: supplied == 0
          ? DefaultFirebaseOptions.currentPlatform
          : const FirebaseOptions(
              projectId: projectId,
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: senderId,
              authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
              storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
              iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
              measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
            ),
      usesGeneratedFirebaseOptions: supplied == 0,
      enableConnectivityDiagnostic: const bool.fromEnvironment(
        'ENABLE_FIREBASE_DIAGNOSTIC',
      ),
      useEmulators: const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
      emulatorHost: const String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      ),
      authEmulatorPort: const int.fromEnvironment(
        'FIREBASE_AUTH_EMULATOR_PORT',
        defaultValue: 9099,
      ),
      firestoreEmulatorPort: const int.fromEnvironment(
        'FIREBASE_FIRESTORE_EMULATOR_PORT',
        defaultValue: 8080,
      ),
      functionsEmulatorPort: const int.fromEnvironment(
        'FIREBASE_FUNCTIONS_EMULATOR_PORT',
        defaultValue: 5001,
      ),
      functionsRegion: const String.fromEnvironment(
        'FIREBASE_FUNCTIONS_REGION',
        defaultValue: 'us-central1',
      ),
      webAppCheckSiteKey: const String.fromEnvironment(
        'APP_CHECK_WEB_SITE_KEY',
      ),
      publicPassportBaseUrl: const String.fromEnvironment(
        'PUBLIC_PASSPORT_BASE_URL',
      ),
    );
    config.validate();
    return config;
  }

  void validate() {
    if (useEmulators &&
        (!isDevelopment ||
            !(firebaseOptions?.projectId.startsWith('demo-') ?? false))) {
      throw const ConfigurationFailure(
        'Emulators require development and a demo- Firebase project ID.',
      );
    }
    if (firebaseOptions == null) {
      throw const ConfigurationFailure(
        'Firebase configuration is required to start FarmTwin.',
      );
    }
    if (!isDevelopment &&
        (firebaseOptions?.projectId.startsWith('demo-') ?? false)) {
      throw const ConfigurationFailure(
        'A demo Firebase project cannot be used in staging or production.',
      );
    }
    if (!useEmulators && firebaseOptions?.projectId != 'farmtwin-f64bd') {
      throw const ConfigurationFailure(
        'FarmTwin cloud builds must use project farmtwin-f64bd.',
      );
    }
    if (enableConnectivityDiagnostic && !isDevelopment) {
      throw const ConfigurationFailure(
        'The Firebase diagnostic requires an explicit development environment.',
      );
    }
    if (publicPassportBaseUrl.isNotEmpty) {
      final uri = Uri.tryParse(publicPassportBaseUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' && !(isDevelopment && uri.scheme == 'http'))) {
        throw const ConfigurationFailure(
          'Public passport base URL must be a valid HTTPS URL.',
        );
      }
    }
  }
}

class FeatureConfig {
  const FeatureConfig({
    this.cloudAssistantEnabled = false,
    this.harvestPublishingEnabled = false,
  });
  final bool cloudAssistantEnabled;
  final bool harvestPublishingEnabled;
}
