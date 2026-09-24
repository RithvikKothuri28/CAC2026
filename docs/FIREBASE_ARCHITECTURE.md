# Firebase architecture and setup

FarmTwin calculations run locally in Dart. Firestore persists farmer inputs and useful result summaries. The default application uses the registered options in `lib/firebase_options.dart` for the real project `farmtwin-f64bd`. `main` awaits `FirebaseBootstrap.initialize` before starting the workspace. Missing or invalid configuration produces a visible startup error; there is no alternative farm store. The backend never uploads every optimization candidate or Monte Carlo draw.

The default Firestore database is in `nam5`, and email/password Authentication is enabled. Rules were deployed at `2026-09-21T04:08:46Z` as ruleset `427e4f41-0974-4a42-9084-00171e93a646`. Project billing was disabled at inspection, which blocks Functions cleanup deployment. Check [VERIFICATION.md](VERIFICATION.md) for current end-to-end evidence rather than inferring deployment from the source files.

## Document contract

| Path | Shape and purpose |
| --- | --- |
| `users/{uid}` | `{schemaVersion:1, settings:map, updatedAt:serverTimestamp, createdAt?:timestamp}` |
| `farms/{farmId}` | `{schemaVersion:1, ownerId, name, source, createdAt, updatedAt, data:Farm.toJson()}` |
| `farms/{farmId}/members/{uid}` | `{userId:uid, role:'owner'|'viewer'|'editor', createdAt:serverTimestamp}`; owner record is immutable |
| `farms/{farmId}/{collection}/{id}` | `{schemaVersion:1, createdAt, updatedAt, data:map}` for allowed private entity collections |
| `farms/{farmId}/passportPublications/{batchId}` | Server-only write: public passport reverse mapping |
| `publicHarvestPassports/{id}` | Validated selected public fields; anonymous get only |
| `farmDeletionRequests/{farmId}` | Durable, server-only recursive cleanup job |
| `accountDeletionRequests/{uid}` | Durable, server-only user cleanup job/write freeze |
| `deletedAccounts/{uid}` | Temporary old-ID-token write denial; TTL |
| `aiUsage/{uid}/days/{date}` | Transactional private quota; TTL |
| `aiGlobalUsage/{date}` | Transactional aggregate quota; TTL |
| `developmentDiagnostics/{uid}/checks/{id}` | `{schemaVersion:1,ownerId:uid,projectId:'farmtwin-f64bd',createdAt:serverTimestamp}`; own developer account only |

Allowed entity collections are `fields`, `cropProfiles`, `cropHistory`, `expenses`, `debts`, `constraints`, `scenarios`, `optimizationRuns`, `simulationRuns`, `harvestBatches`, and `settings`. The current Flutter repository stores the interdependent farm model in `farms.data` as an atomic snapshot. Scenarios, saved result summaries, harvest batches, and settings can use their entity collections. The collection rules also permit normalized entity CRUD for future repository migrations. Do not mix aggregate and normalized data as competing authoritative sources.

New farm `source` must be `userEntered` or `imported`. Historical `sample` records remain readable/editable for compatibility; production cannot create new ones. Every farm/entity envelope uses schema version one. Domain serialization/migration handles changes within `data`; unknown future versions return a typed failure rather than being overwritten. Parent owner and creation timestamp are immutable. Creation commits the farm and `members/{ownerUid}` together; rules use `getAfter` to require that atomic owner record and reject another UID's ownership. Queries for owned farms use `where('ownerId', isEqualTo: uid)`; rules are not result filters. Membership access is supported by rules, but adding shared-farm discovery requires its own indexing/query design.

`FirestoreFarmRepository` captures the authenticated UID, writes the entered aggregate and server timestamps, and awaits the Firebase SDK write future. Listeners do not promote pending local creations or edits to confirmed workspace state. If acknowledgment exceeds the bounded wait, the form receives `write-pending`; Firestore may still finish its queued write, and the same farm ID is retained for retry. Successful navigation and saved UI state require acceptance by Firestore.

## Manual connection diagnostic

Run a debug build with `--dart-define-from-file=config/development-live.example.json`, sign in with a dedicated development account, and select **Settings → Check Firebase connectivity**. Trusted administrative tooling must first grant that account the custom claim `farmtwinDeveloper: true`; refresh the user's token or sign in again after granting it. Claims are not granted by the application.

The diagnostic checks initialization, the exact project, current authentication, and an acknowledged write/server-read/delete/server-read sequence in `developmentDiagnostics/{uid}/checks/{id}`. Rules permit only that UID with the developer claim, only the fixed schema, and no listing or updating. Temporary records contain no farm payload. It is available only with `ENVIRONMENT=development`, `ENABLE_FIREBASE_DIAGNOSTIC=true`, and a debug build, and runs only when requested. Account cleanup removes interrupted diagnostic records. Debug connection logs contain UID, project, document path and write results; they exclude passwords, tokens and farm financial payloads.

## Local tests

Install Node 22 and Java 21 or newer. On Windows a portable JRE under `~/.cache/farmtwin/jdk` is discovered by `scripts/backend-test.ps1`.

```powershell
cd functions
npm ci
cd ..
./scripts/backend-test.ps1
```

The test script runs strict TypeScript compilation, pure validation tests, and Auth/Firestore emulators under the hardcoded safe test project `demo-farmtwin`. Emulator hosts bind to `127.0.0.1`: Auth 9099, Firestore 8080, callable/HTTP Functions 5001. Tests perform an independent runtime check of project and host before creating data. No Firebase login is needed. Generated logs and compiled output should remain ignored.

For manual full-stack emulator use:

```powershell
cd functions
npm run build
npx firebase emulators:start --project demo-farmtwin --config ../firebase.json --only auth,firestore,functions
```

The optional AI function uses Secret Manager when deployed. Normal security/persistence tests do not require any provider secret or network inference. The Auth/Firestore suite executes the backend services against real emulators; the browser suites also exercise callable middleware using the explicit development emulator configuration. Real Firebase tests have separate opt-in guards and ignored credentials.

## Callable and public API

All callables use Firebase callable protocol in `us-central1`. They require Firebase Auth and deployed App Check.

| Function | Request | Response |
| --- | --- | --- |
| `publishHarvestPassport` | `{farmId,batchId,fields:string[]}` | `{passportId}` |
| `deleteHarvestPassport` | `{farmId,passportId}` | `{deleted:true}` |
| `deleteFarm` | `{farmId}` | `{deleted:true}` |
| `deleteAccount` | `{}` with recent Auth login | `{deleted:true}` |
| `explainFarm` | `{farmId,question,context:Record<string,number>}` | `{explanation,source:'cloudExplanation',metrics}` |

`publicPassport` is an unauthenticated, read-only HTTP endpoint supporting `/publicPassport/<passportId>` and `/publicPassport?id=<passportId>`. Configure Flutter's `PUBLIC_PASSPORT_BASE_URL` to the actual function's deployed base URL after deployment. The endpoint renders only the published allowlist and returns 404 after unpublication. A QR code contains that URL.

The explanation context supports these numeric keys: `revenue`, `operatingExpense`, `operatingIncome`, `debtService`, `cashAfterDebtService`, `waterUsage`, `nitrogenUsage`, `acreage`, `cropDiversity`, `practiceSatisfied`, `practiceTotal`, `candidatesGenerated`, `candidatesPruned`, `candidatesEvaluated`, `feasiblePlans`, `paretoPlans`, `mean`, `median`, `standardDeviation`, `p05`, `p25`, `p75`, `p95`, `probabilityNegativeCashFlow`, `probabilityPositiveCashFlow`. Send only metrics relevant to the explicit question. Additional/nested private context is rejected. Domain context names should be mapped explicitly to this transport contract.

## Production setup

The current application intentionally restricts non-emulator builds to `farmtwin-f64bd`. Production and staging example configurations omit Firebase identifier overrides and use the generated platform options. The staging environment label does not isolate a second database. Separate project isolation would require deliberate app registration, configuration and validation changes.

Register the supported App Check provider for each platform and validate issued tokens before enabling service enforcement. Android uses Play Integrity and iOS uses App Attest with DeviceCheck fallback; explicitly configured native debug development uses debug providers. Web activates reCAPTCHA v3 when `APP_CHECK_WEB_SITE_KEY` is supplied. No web provider/site key or service enforcement was configured at inspection; omitting the key skips client provider activation and never disables server enforcement. Once a service enforces App Check, its clients need valid tokens. Deployed callables already require App Check by source configuration. App identifiers must match signed builds, and Analytics/Crashlytics collection remains controlled by consent.

Deployment is an explicit operator step, never part of tests:

```powershell
cd functions
npm ci
npm run build
npx firebase deploy --project farmtwin-f64bd --config ../firebase.json --only firestore:rules
```

Enable the required billing plan and APIs before deploying Functions. Deploy indexes separately, including the `members.userId` collection-group index required by account cleanup; TTL policies in the index configuration also need compatible billing. Then deploy the non-AI functions if no AI provider is configured:

```powershell
npx firebase deploy --project farmtwin-f64bd --config ../firebase.json --only firestore:indexes
npx firebase deploy --project farmtwin-f64bd --config ../firebase.json --only "functions:farmtwin:publishHarvestPassport,functions:farmtwin:deleteHarvestPassport,functions:farmtwin:publicPassport,functions:farmtwin:deleteFarm,functions:farmtwin:deleteAccount,functions:farmtwin:cleanupDeletedAuthUser,functions:farmtwin:cleanupDeletedHarvestBatch,functions:farmtwin:retryDeletions"
```

Cloud Scheduler and second-generation Functions need their associated APIs/billing/IAM enabled. The Auth deletion trigger uses first-generation Auth events; the other functions use second-generation functions.

Optional AI uses an OpenAI-compatible chat-completions transport. Set server parameters from `functions/.env.example`, including an explicitly chosen provider HTTPS endpoint, allowed hostname, model, quotas, and timeout. Set `AI_PROVIDER_KEY` through `firebase functions:secrets:set` for `farmtwin-f64bd`, then deploy `explainFarm`. That function declares the deployed secret even when `AI_ENABLED=false`, which is why initial deployment selects the non-AI functions. Never use an actual provider token in source or client configuration. The client also requires the user's cloud-assistant consent and uses calculated local explanations on typed failures. Server disabled/quota/failure states cannot fabricate metrics.

Before production deployment, run the same emulator suite, verify indexes/TTL policies deployed successfully, test Firestore App Check enforcement on signed devices, verify publication and deletion end to end, configure cleanup-failure alerts, review quotas/provider data retention, and perform the app release checks. No successful emulator test implies that these external release steps have occurred.
