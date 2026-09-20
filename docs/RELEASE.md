# Release configuration and outstanding gates

## Identity and environment

The app display name is FarmTwin and version/build number comes from `pubspec.yaml`. Debug Android uses `org.farmtwin.farmtwin.dev`. Every Android release requires an explicitly supplied registered `FARMTWIN_APPLICATION_ID` Gradle property and a real upload key; the build never silently signs a release with the debug key.

Copy `config/staging.example.json` or `config/production.example.json` to a local ignored JSON file. Fill the platform's Firebase public client identifiers and HTTPS passport URL. These are public client configuration, not server secrets. Staging and production reject missing Firebase configuration and demo project IDs. Emulator use is allowed only in development with a demo project. Android/iOS production App Check providers are Play Integrity and App Attest with DeviceCheck fallback; browser cloud access requires the configured reCAPTCHA site key. Actual provider registration/enforcement must be verified in Firebase.

Use distinct Firebase projects and distinct registered mobile apps for staging and production. Configure email/password Auth, rules, indexes, server cleanup functions, and required billing/IAM. Deploying this repository is not authorized automatically by running tests. See [FIREBASE_ARCHITECTURE.md](FIREBASE_ARCHITECTURE.md).

## Android

Install Android SDK, a compatible JDK, and accept the SDK license. The local development setup uses Java 21 and Android platform 36; Gradle resolves plugin-required SDK components.

```sh
flutter build apk --debug
```

In this Windows workspace, OneDrive converted some resource files to reparse points that Gradle could not snapshot. The verified debug build used an ordinary local copy at `C:\Users\kokek\.cache\farmtwin\android-build-20260920`, then copied the resulting APK back to the workspace. If the error says a resource is "not a regular file," build a local copy outside OneDrive rather than disabling Gradle's input tracking. The debug artifact built without environment defines offers the explicit local Sample Farm; cloud accounts require the appropriate Firebase build configuration.

Create an ignored `android/key.properties` containing `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Keep the keystore outside Git. Use an upload key registered with Google Play App Signing. Set the Gradle property using an environment variable, then run:

```powershell
$env:ORG_GRADLE_PROJECT_FARMTWIN_APPLICATION_ID = 'your.registered.identifier'
flutter build appbundle --release --dart-define-from-file=config/production.json
```

Production cloud configuration must match the signed package. Run FlutterFire configuration for the actual native apps so Google services resources, Crashlytics Gradle setup/mapping uploads, and iOS symbols are configured. No native Firebase project files or signing keys are fabricated here. Firebase explains the required [Flutter setup](https://firebase.google.com/docs/flutter/setup) and [Crashlytics setup](https://firebase.google.com/docs/crashlytics/flutter/get-started).

## iOS

Use macOS with Xcode and a registered App Store Connect bundle identifier. Set the Runner target's `PRODUCT_BUNDLE_IDENTIFIER` and signing team in the local release configuration/build settings to match Firebase and provisioning profiles; do not publish the development identifier. Configure the native Firebase app and symbol upload as described above. Then:

```sh
flutter build ipa --release --dart-define-from-file=config/production.json
```

iOS build, signing, real-device App Attest, archive validation, and submission cannot be verified from this Windows workspace.

## Privacy and permissions

Analytics and Crashlytics native auto-collection defaults are disabled; authenticated account consent controls the SDK switches. Cloud assistant consent is separate. Logs avoid farm payloads and prompts. The app requests internet access and no camera/location/storage/notification permissions. QR codes are generated from sanitized public passport links; camera scanning is not implemented or exposed.

Publish an accurate privacy policy and support contact, provide account/data deletion instructions and store privacy disclosures, select a project license, and review third-party licenses. The in-app deletion route removes owned farm data through durable server cleanup; test operational retries and monitoring in staging.

## Required verification before a store submission

- Provision actual staging/production projects, app identifiers, App Check registrations/enforcement, indexes/TTLs, IAM, quotas, and deletion monitoring.
- Verify full signup → arbitrary farm inputs → optimization → simulation → scenarios → saved runs → reopen/sign-in recovery on Android and iOS.
- Verify native offline persistence, queued edits, reconnection, conflicts, cache handling on shared devices, and deletion retries on actual devices.
- Verify signed release builds, Crashlytics symbolication with consent, disabled telemetry without consent, public QR destination, and no secrets/debug endpoints in build artifacts.
- Measure startup, frames, memory, and large-farm workloads on target mobile devices. Desktop benchmark results are not mobile performance claims.
- Complete accessibility/text-scale/manual interaction checks, privacy/support URLs, screenshots, app review access, versioning, and release signing.

No store-ready claim should be made until these external checks are complete.
