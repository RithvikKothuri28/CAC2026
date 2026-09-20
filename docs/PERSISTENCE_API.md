# Persistence integration

Imports are exported by `lib/data/data.dart` and `lib/app/config/app_config.dart`.

`AppConfig.fromEnvironment()` validates explicit development/staging/production compile-time configuration. `FirebaseBootstrap.initialize(config)` returns `FirebaseServices?`; null means no Firebase configured in development. Configuration/init failures are typed `AppFailure` exceptions and must be visible; never load sample inputs automatically. Missing cloud setup still allows explicit Sample Farm.

`FirebaseServices` properties: `auth` (`FirebaseAuthRepository`), `farms` (`FirestoreFarmRepository`), `settings` (`FirestoreSettingsRepository`), `privacy` (`FirebasePrivacyService`), `passports` (`HarvestPassportService`), `explanations` (`CloudExplanationService`), `features` (`FeatureConfig`).

Auth: `authStateChanges` stream; `currentUser`; `signIn(email,password)`; `signUp(email,password)`; `resetPassword(email)`; `signOut()`; `deleteAccount()` (server cleanup, recent login required); `reauthenticate(email,password)`.

`FarmRepository`: `watchFarms()` -> Stream<List<Farm>>; `readFarm(id)` -> Future<Farm>; `saveFarm(Farm)` -> Future<void>; `deleteFarm(id)` -> Future<void>; `watchEntities(farmId,EntityKind)` -> Stream<List<StoredEntity>>; `saveEntity(farmId,kind,StoredEntity)`; `deleteEntity(farmId,kind,id)`; `close()`.

`EntityKind`: scenarios, optimizationRuns, simulationRuns, harvestBatches. `StoredEntity({required String id, required Map<String,dynamic> data})`. Stores input scenarios and calculated summaries; do not upload candidate populations or Monte Carlo draws.

Fields, crop profiles, constraints, expenses, debts and histories use the typed Farm aggregate: edit lists via `copyWith` then `saveFarm`. Aggregate writes are atomic. No partial mirror collections are treated as an authoritative second copy.

`SampleFarmRepository.open()` returns an empty persisted local repository on first use. `loadSample()` explicitly reads `assets/sample/sample_farm.json`, resets this repository's farm and saved entities, and returns `Farm`. It never initializes or calls Firebase. `close()` closes its stream. Persisted sample changes survive restarts. All calculation/model code is shared with real farms.

`FarmExportService.exportFarm(Farm)` -> JSON string; `importFarm(String,{required String id})` -> validated Farm with imported provenance. No implicit save or change to owner from imported JSON.

`UserSettings` has `analyticsConsent`, `crashReportingConsent`, `cloudAssistantConsent`. `FirestoreSettingsRepository.read()/save(settings, expectedUid: uid)`. Settings and farm writes share bounded acknowledgment tracking so offline writes remain queued without blocking forms indefinitely. The account captured by a privacy action must match before its cloud write. `FirebasePrivacyService.bindAccount(uid, readRemote)` restores only that account's consent; `apply(settings)` persists the choice and updates SDK switches. Settings default false. Browser analytics initialization is deferred until consent; emulators never instantiate telemetry SDKs.

The current Flutter repository and workspace expose owner accounts only; member-management UI is not implemented. The adapter checks the active account and cached parent ownership before exposing records or queueing edits, including after asynchronous reads. This is necessary because a Firestore device-cache read does not itself re-evaluate server security rules. The backend role rules are tested separately from this owner-only client scope.

`HarvestPassportService.publish({farmId,batchId,fields})` -> public ID; `unpublish({farmId,passportId})`; `publicUrl(id)` -> configured URL (throws if missing). Batch entity `data` fields: crop, field, plantingDate, harvestDate, practices, inputRecords, handlingEvents, storageEvents, notes. Only explicitly selected fields are copied by server; crop is required.

`CloudExplanationService.explain({farmId,question,context})` -> String. Caller must check opt-in and `features.cloudAssistantEnabled`; on typed provider failure run the deterministic domain explanation and label its source.
