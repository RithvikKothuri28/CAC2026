# FarmTwin

FarmTwin is a Flutter farm planning application for Android and iOS, with a web target for development and testing. It connects fields, crop economics, resource constraints, debt, allocation optimization, risk simulations, scenarios, and harvest records.

**Inputs may be sample data. Outputs are always calculated.** The welcome screen never loads a farm automatically. Choose **Load Sample Farm** to use the bundled input dataset, or configure Firebase and create an account and an empty farm.

## Run locally

Use Flutter 3.47.5 / Dart 3.13.4 (the versions used during development):

```sh
flutter pub get
flutter run -d chrome
```

On the current Windows workspace, Flutter is installed at `C:\Users\kokek\.cache\farmtwin\flutter`. If it is not on PATH:

```powershell
& "$env:USERPROFILE\.cache\farmtwin\flutter\bin\flutter.bat" run -d chrome
```

The Sample Farm works without Firebase or an AI provider. Its edits and saved summaries persist on the device. Settings → Reset Sample Farm restores only sample inputs and clears its local saved runs. All farms use the same domain engines.

## Cloud development

Install Node 22 and Java 21+. In a separate terminal:

```sh
cd functions
npm ci
npm run build
npx firebase emulators:start --project demo-farmtwin --config ../firebase.json --only auth,firestore,functions
```

From the repository root:

```sh
flutter run -d chrome --dart-define-from-file=config/development.example.json
```

This configuration contains emulator-only public identifiers. On an Android emulator, override `FIREBASE_EMULATOR_HOST=10.0.2.2` and the public passport base URL accordingly. Cloud tests require loopback and the exact `demo-farmtwin` project. They never select a production project.

For staging/production, copy the matching `config/*.example.json` to an ignored configuration file and supply the actual Firebase app identifiers. Enable email/password Authentication, deploy the Firestore rules and backend, configure App Check, and set the passport URL. [Deployment details](docs/FIREBASE_ARCHITECTURE.md) and [release setup](docs/RELEASE.md) explain the external steps. No real Firebase project has been deployed by this implementation.

## Workflows

- **My farm:** create and edit crop profiles, fields, compatibility/history, expenses, debt, and hard/preference/disabled constraints. Review configurable objective weights and uncertainty assumptions.
- **Optimize:** run actual candidate generation, financial/constraint evaluation, normalized scoring, and Pareto extraction. Select alternatives, compare allocations, save a reproducible summary, or apply a plan.
- **Risk & outlook:** simulate paired current/selected cash distributions with a shared seed, inspect statistics, and calculate rotation/debt/inflation projections.
- **Scenario lab:** save editable market, yield, cost, water-limit, and interest multipliers, re-optimize, and simulate/save the resulting cash distributions.
- **Assistant:** explain current engine results locally. Optional consent-based cloud prose uses a secured backend; failures fall back to calculated local explanations.
- **Harvest passports:** save private batches and explicitly select fields for public publication and a QR link in a configured cloud deployment.
- **Settings:** export/import JSON, inspect/delete saved runs, manage privacy, sign out, and delete farms/accounts through server cleanup.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
cd functions
npm test
npm audit --omit=dev
```

Browser integration tests use a ChromeDriver matching Chrome, listening on port 4444:

```sh
chromedriver --port=4444
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/sample_flow_test.dart -d web-server --browser-name=chrome --headless
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/production_flow_test.dart -d web-server --browser-name=chrome --headless --dart-define-from-file=config/development.example.json
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/user_flow_test.dart -d web-server --browser-name=chrome --headless --dart-define-from-file=config/development.example.json
```

The production repository and new-user UI flows require the Auth, Firestore, and Functions emulators above. The UI flow enters an arbitrary farm through the actual forms and checks calculations, saving, application/controller recreation, sign-out/sign-in recovery, and deletion. On a connected Android/iOS device, use `flutter test integration_test/sample_flow_test.dart -d DEVICE_ID`. Run cloud integration only against the configured emulators. Current evidence and remaining verification are recorded in [VERIFICATION.md](docs/VERIFICATION.md).

## Architecture and model limits

`lib/domain` contains pure Dart immutable input models and deterministic engines. `lib/data` contains versioned codecs, Firestore repositories, optional cloud services, and the isolated persisted sample workspace. `lib/features` contains forms, controllers, and calculated views. Native computations use Flutter `compute` isolates. Browser `compute` runs on the main thread; large browser models need separate worker support before a public web launch.

The optimizer exhaustively evaluates small compatible search spaces and uses bounded seeded exploration for larger ones. Hard constraints always decide feasibility. A bounded frontier is explicitly labeled approximate. The resilience objective is an analytical revenue-risk proxy; it is not a Monte Carlo percentile. Five-year allocation is a deterministic rotation heuristic with annual feasibility checks, not a globally optimal multi-year agricultural plan. Assumptions remain the farmer's responsibility and are not externally verified.

Units are acres, acre-feet of water, pounds of nitrogen, crop-specific yield units, and the selected ISO currency. Financial metrics exclude unmodeled taxes, subsidies, and insurance. A zero uncertainty input means no modeled uncertainty, not certainty in the real world. Read [technical model definitions](docs/TECHNICAL_OVERVIEW.md) before interpreting outputs.

## Release status

This is an implemented and testable development application, **not a store-approved production release**. Production Firebase provisioning, real App Check/device checks, registered identifiers, signing credentials, privacy/support URLs, and platform release validation must be supplied and verified before publication. iOS archives require macOS/Xcode. See [the release checklist](docs/RELEASE.md).

No project license has been selected; bundled Roboto fonts retain their license in `assets/fonts/LICENSE.txt`.
