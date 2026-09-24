# FarmTwin verification

## Crop compatibility fix

Verified on September 23, 2026. Read-only inspection of real Firestore records confirmed the reported failure: the crop IDs were valid and explicitly selected, but Corn required irrigation while Field 1 was marked as not irrigated. The old form created this contradictory assignment; validation caught it only during financial rendering. No existing farm's irrigation or compatibility values were changed automatically.

The shared compatibility check now applies to model validation, field selection, Firestore writes and optimizer candidates. New fields start unassigned with no compatible crops selected. Existing invalid assignments open for explicit correction with a setup message; calculations remain blocked. Unambiguous legacy crop names normalize to stable IDs on read and persist only on an explicit successful save. See [CROP_COMPATIBILITY.md](CROP_COMPATIBILITY.md) for the repair instructions and migration boundaries.

Verification for this change:

- `dart format .`: completed.
- `flutter analyze`: no issues.
- `flutter test`: **104 tests passed**, including compatibility acceptance/rejection, irrigation requirements, empty-field handling, safe legacy normalization, Firestore round trips and explicit repair, filtered selectors, write acknowledgement and compatible candidates in both exhaustive and bounded optimization.
- `integration_test/user_flow_test.dart`: passed with the Auth/Firestore/Functions emulators. Exercises create farm → add crops → add field → save → optimize; compatibility changes exclude a more profitable disallowed crop and survive server reload and sign-in.
- `integration_test/production_flow_test.dart`: passed with the same isolated emulators. The real repository rejects an incompatible current crop before writing, retains the previously accepted IDs, excludes disallowed optimizer candidates, and preserves IDs through edits and sign-in recovery. Offline acknowledgement, saved calculations, publication and cleanup regressions also pass. Evidence: `crop-production-flow.log`.
- `integration_test/live_crop_compatibility_test.dart`: passed against **real `farmtwin-f64bd` Firebase**, using the actual UI and authenticated Firestore SDK. Creates a new verification farm, enters an irrigation-required Corn profile, verifies a new rainfed field cannot assign it, explicitly enables irrigation and selects its ID, saves, verifies the server record, optimizes, edits compatibility, saves an explicitly unassigned field, recreates the app without a rendering exception, restores the assignment, and signs out/signs back in. Server reads confirm the same crop/field IDs and compatibility values throughout.
- `flutter build web --release --no-wasm-dry-run`: passed with the default production Firebase configuration; artifact at `build/web`.

The live verification record remains available for inspection:

- Farm: `farms/779c2ae1-fddd-4460-9e8e-e5548ad21224`
- Crop ID: `2ecc8356-8f2f-46a1-b237-ab125fa17075`
- Field ID: `572c4408-3d45-43a8-8f47-49b76e67b213`
- Owner: the dedicated verification account `zHpdrgnNQwf1deYX2sBU6a6KXYB3`.

[Inspect the crop compatibility verification farm](https://console.firebase.google.com/project/farmtwin-f64bd/firestore/databases/-default-/data/~2Ffarms~2F779c2ae1-fddd-4460-9e8e-e5548ad21224). Ignored local evidence: `crop-tests.log`, `crop-analyze.log`, `crop-user-flow.log`, `crop-live-flow.log`, and `test-results/crop-live-verification.json`. The live test recreates the Flutter app and its workspace; the separate browser refresh/process-restart evidence below belongs to the earlier connectivity test.

An independent administrative server read at `2026-09-24T00:45:36.986Z` confirmed that verification farm's owner, current crop ID, explicit compatibility list and irrigation requirements match the UI's accepted inputs. This read did not modify the record. Evidence: `test-results/crop-live-server-read.json`.

## Firebase connectivity verification

Verified on September 22, 2026 (America/Denver), using Flutter 3.47.5 / Dart 3.13.4, Node 22, Java 21, and Chrome 153 on Windows.

## Real Firebase evidence

The actual project is `farmtwin-f64bd`, with a native Firestore `(default)` database in `nam5` and email/password Authentication enabled. Its previous deployed rules denied every read and write. The corrected ownership rules were deployed at `2026-09-21T04:08:46Z`, ruleset `427e4f41-0974-4a42-9084-00171e93a646`.

The opt-in `integration_test/live_connectivity_test.dart` passed against that real project. It exercised the actual UI to create an account, sign out/sign in, select **Add New Farm**, enter farm details, save, recreate the application, rename the farm, and sign out/sign back in. Firestore server reads verified the entered country, region, acreage and currency, owner UID, server timestamps, and the atomic owner membership record.

One clearly named verification farm remains for Firebase Console inspection:

- Document: `farms/fd48735c-24e4-4aa9-b8cf-a3b17c259125`
- Owner UID: `zHpdrgnNQwf1deYX2sBU6a6KXYB3`
- Owner membership: `farms/fd48735c-24e4-4aa9-b8cf-a3b17c259125/members/zHpdrgnNQwf1deYX2sBU6a6KXYB3`
- Current name: `Firebase connectivity verification edited`
- Created: `2026-09-22T00:01:46.248Z`; edited: `2026-09-22T00:01:49.425Z`.

[Inspect the farm in Firebase Console](https://console.firebase.google.com/project/farmtwin-f64bd/firestore/databases/-default-/data/~2Ffarms~2Ffd48735c-24e4-4aa9-b8cf-a3b17c259125).

An independent authenticated administrative server read also confirmed the farm and owner record exist. Creation and editing were performed by the application with the user's Firebase Auth token and enforced rules, not by the administrative read.

ChromeDriver then tested the normal `lib/main.dart` application, served from a debug web build. A full page refresh and a newly launched browser process using the same browser profile both restored authentication and the same edited farm. Firestore web cache is memory-only, so the new browser process reloaded the farm from Firestore. This check completed at `2026-09-23T00:52:52.661Z`.

The manually invoked development diagnostic passed initialization, project, authenticated user, server write, server read, delete and post-delete server-read checks. The dedicated test account temporarily received `farmtwinDeveloper: true`; that claim was removed afterward. An administrative check found **zero remaining diagnostic documents**. Production builds cannot invoke the diagnostic.

Ignored local evidence files:

- `live-connectivity.log`: successful live UI integration run.
- `test-results/live-verification.json`: browser refresh/restart and diagnostic results.
- `test-results/live-farm-restarted.png`: actual app after a browser process restart.
- `test-results/firebase-diagnostic-events.json`: development UID/project/path events, without credentials or financial payloads.
- `config/live-test.json`: local test-account credentials; deliberately ignored and never included in the app's normal build.

## Automated verification

- `dart format .`: completed.
- `flutter analyze`: no issues.
- `flutter test`: **80 tests passed**. Includes atomic write acknowledgement, authentication/ownership boundaries, surfaced permission and timeout failures, pending snapshot filtering, onboarding serialization, retained form inputs on failure, controller concurrency and domain calculations.
- `cd functions; npm test`: **6 unit tests and 11 Auth/Firestore emulator tests passed**. Includes actual Firebase Auth tokens, cross-account/anonymous denial, mandatory atomic owner membership, owner immutability, claimed developer diagnostics and cleanup.
- `integration_test/production_flow_test.dart`: passed against explicit `demo-farmtwin` Auth/Firestore/Functions emulators. Covers actual repository writes, offline pending failure and reconnect acknowledgement, server reload, sign-in recovery, publication/unpublication, recursive farm deletion and account cleanup.
- `integration_test/user_flow_test.dart`: passed against the same explicit emulators. Covers account/onboarding forms, all farm input forms, calculations and saved summaries, sign-in recovery, reauthentication cancellation, and completed account cleanup.
- Web debug build with the explicit development-live diagnostic configuration and default production release build: passed. The release build returned exit code 0, restored the real farm, and exposed no development diagnostic. The artifact check bypassed the test browser's cached older development service worker while preserving its Auth session.

The emulator suites are isolated from the real project. Test fixtures now live under `test/fixtures`; the application has no sample farm repository or bundled sample farm asset.

## Remaining external requirements

The actual project still reports `billingEnabled: false`. Cloud Functions has not been deployed, so production farm/account deletion and other callable features are **not verified or available**. Their intended cleanup path passed emulator tests; direct client farm deletion remains denied to prevent orphaned records. Enable the appropriate billing plan, deploy the cleanup functions and required indexes, configure valid App Check clients, then verify actual production cleanup. The app surfaces callable failures rather than reporting a successful deletion.

No web App Check provider/site key or service enforcement was configured at inspection. This fix did not disable server enforcement. A configured web site key activates the provider; deployed callables require valid App Check. Native signed-device attestation still needs verification.

Browser restart evidence does not establish Android/iOS force-stop recovery. Android/iOS device tests, signed release builds, iOS compilation, store approval, telemetry consent checks on actual devices and operational cleanup monitoring remain release requirements. Older APK/release artifacts predate this connectivity fix and do not establish current native verification. See [RELEASE.md](RELEASE.md).
