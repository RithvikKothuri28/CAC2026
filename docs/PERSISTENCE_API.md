# Persistence integration

Imports are exported by `lib/data/data.dart` and `lib/app/config/app_config.dart`.

`AppConfig.fromEnvironment()` selects the generated options for `farmtwin-f64bd` by default. Emulators require explicit development configuration and a `demo-` project. `FirebaseBootstrap.initialize(config)` returns `FirebaseServices` before `runApp`; initialization failures show a retry screen and cannot open a local workspace.

`FirebaseServices` properties: `auth` (`FirebaseAuthRepository`), `farms` (`FirestoreFarmRepository`), `settings` (`FirestoreSettingsRepository`), `privacy` (`FirebasePrivacyService`), `passports` (`HarvestPassportService`), `explanations` (`CloudExplanationService`), `features` (`FeatureConfig`).

Auth: `authStateChanges` stream; `currentUser`; `signIn(email,password)`; `signUp(email,password, displayName: name)`; `resetPassword(email)`; `signOut()`; `deleteAccount()` (server cleanup, recent login required); `reauthenticate(email,password)`.

`FarmRepository`: `watchFarms()` -> Stream<List<Farm>>; `readFarm(id)` -> Future<Farm>; `saveFarm(Farm)` -> Future<void>; `deleteFarm(id)` -> Future<void>; `watchEntities(farmId,EntityKind)` -> Stream<List<StoredEntity>>; `saveEntity(farmId,kind,StoredEntity)`; `deleteEntity(farmId,kind,id)`; `close()`.

`EntityKind`: scenarios, optimizationRuns, simulationRuns, harvestBatches. `StoredEntity({required String id, required Map<String,dynamic> data})`. Stores input scenarios and calculated summaries; do not upload candidate populations or Monte Carlo draws.

Fields, crop profiles, constraints, expenses, debts and histories use the typed Farm aggregate: edit lists via `copyWith` then `saveFarm`. Creation atomically writes both `/farms/{farmId}` and `/farms/{farmId}/members/{uid}` with an immutable owner role. Aggregate edits are atomic. No partial mirror collections are treated as an authoritative second copy.

Crop references persist as stable profile IDs. `watchFarms()` uses the codec's read-only editing path to preserve existing incompatible current assignments for explicit repair; all other model and reference checks remain enforced. This does not make an invalid farm ready for calculations. `readFarm()`, `saveFarm()` and domain engines use strict validation. Legacy name/ID normalization is persisted only by a subsequent explicit successful save. See [CROP_COMPATIBILITY.md](CROP_COMPATIBILITY.md).


`FarmExportService.exportFarm(Farm)` -> JSON string; `importFarm(String,{required String id})` -> validated Farm with imported provenance. No implicit save or change to owner from imported JSON.

`UserSettings` has `analyticsConsent`, `crashReportingConsent`, `cloudAssistantConsent`. `FirestoreSettingsRepository.read()/save(settings, expectedUid: uid)`. Settings and farm writes share bounded acknowledgment tracking. A 15-second timeout returns `NetworkFailure(code: write-pending)` while the SDK queue remains active; it never indicates success. Forms keep their inputs and expose failures. New farms are withheld from listeners until server acceptance; pending edits retain the previously confirmed version. The account captured by a privacy action must match before its cloud write. `FirebasePrivacyService.bindAccount(uid, readRemote)` restores only that account's consent; `apply(settings)` persists the choice and updates SDK switches. Settings default false. Browser analytics initialization is deferred until consent; emulators never instantiate telemetry SDKs.

The current Flutter repository and workspace expose owner accounts only; member-management UI is not implemented. The adapter checks the active account and cached parent ownership before exposing records or queueing edits, including after asynchronous reads. This is necessary because a Firestore device-cache read does not itself re-evaluate server security rules. The backend role rules are tested separately from this owner-only client scope.

`HarvestPassportService.publish({farmId,batchId,fields})` -> public ID; `unpublish({farmId,passportId})`; `publicUrl(id)` -> configured URL (throws if missing). Batch entity `data` fields: crop, field, plantingDate, harvestDate, practices, inputRecords, handlingEvents, storageEvents, notes. Only explicitly selected fields are copied by server; crop is required.

`CloudExplanationService.explain({farmId,question,context})` -> String. Caller must check opt-in and `features.cloudAssistantEnabled`; on typed provider failure run the deterministic domain explanation and label its source.
