# Firebase architecture and setup

FarmTwin calculations run locally in Dart. Firestore persists farmer inputs and useful result summaries. The backend never uploads every optimization candidate or Monte Carlo sample. No real Firebase project is included or automatically selected in this repository.

## Document contract

| Path | Shape and purpose |
| --- | --- |
| `users/{uid}` | `{schemaVersion:1, settings:map, updatedAt:serverTimestamp, createdAt?:timestamp}` |
| `farms/{farmId}` | `{schemaVersion:1, ownerId, name, source, createdAt, updatedAt, data:Farm.toJson()}` |
| `farms/{farmId}/members/{uid}` | `{userId:uid, role:'viewer'|'editor', createdAt?:timestamp}` |
| `farms/{farmId}/{collection}/{id}` | `{schemaVersion:1, createdAt, updatedAt, data:map}` for allowed private entity collections |
| `farms/{farmId}/passportPublications/{batchId}` | Server-only write: public passport reverse mapping |
| `publicHarvestPassports/{id}` | Validated selected public fields; anonymous get only |
| `farmDeletionRequests/{farmId}` | Durable, server-only recursive cleanup job |
| `accountDeletionRequests/{uid}` | Durable, server-only user cleanup job/write freeze |
| `deletedAccounts/{uid}` | Temporary old-ID-token write denial; TTL |
| `aiUsage/{uid}/days/{date}` | Transactional private quota; TTL |
| `aiGlobalUsage/{date}` | Transactional aggregate quota; TTL |

Allowed entity collections are `fields`, `cropProfiles`, `cropHistory`, `expenses`, `debts`, `constraints`, `scenarios`, `optimizationRuns`, `simulationRuns`, `harvestBatches`, and `settings`. The current Flutter repository stores the interdependent farm model in `farms.data` as an atomic snapshot. Scenarios, saved result summaries, harvest batches, and settings can use their entity collections. The collection rules also permit normalized entity CRUD for future repository migrations. Do not mix aggregate and normalized data as competing authoritative sources.

Farm `source` is `userEntered`, `imported`, or `sample`. New user farms must not silently receive sample inputs. Every farm/entity envelope uses schema version one. Domain serialization/migration handles changes within `data`; unknown future versions must return a typed failure rather than be overwritten. Parent owner and creation timestamp are immutable. Queries for owned farms must use `where('ownerId', isEqualTo: uid)`; rules are not result filters. Membership access is supported by rules, but adding a shared-farm discovery UI requires a deliberate indexing/query design.

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

The optional AI function uses Secret Manager when deployed. To emulate it, provide a locally ignored `functions/.secret.local` only when testing a real provider integration; normal security/persistence tests do not require any provider secret or network inference. The Auth/Firestore suite executes the backend services against real emulators; separate full-stack smoke tests should exercise callable middleware on a real configured staging app.

## Callable and public API

All callables use Firebase callable protocol in `us-central1`. They require Firebase Auth and deployed App Check.

| Function | Request | Response |
| --- | --- | --- |
| `publishHarvestPassport` | `{farmId,batchId,fields:string[]}` | `{passportId}` |
| `deleteHarvestPassport` | `{farmId,passportId}` | `{deleted:true}` |
| `deleteFarm` | `{farmId}` | `{deleted:true}` |
| `deleteAccount` | `{}` with recent Auth login | `{deleted:true}` |
| `explainFarm` | `{farmId,question,context:Record<string,number>}` | `{explanation,source:'cloudExplanation',metrics}` |

`publicPassport` is an unauthenticated, read-only HTTP endpoint supporting `/publicPassport/<passportId>` and `/publicPassport?id=<passportId>`. Configure Flutter's `PUBLIC_PASSPORT_BASE_URL` to this function's deployed base URL. The URL is environment-specific; do not hardcode a cloud project into the application. The endpoint renders only the published allowlist and returns 404 after unpublication. A QR code contains that URL.

The explanation context supports these numeric keys: `revenue`, `operatingExpense`, `operatingIncome`, `debtService`, `cashAfterDebtService`, `waterUsage`, `nitrogenUsage`, `acreage`, `cropDiversity`, `practiceSatisfied`, `practiceTotal`, `candidatesGenerated`, `candidatesPruned`, `candidatesEvaluated`, `feasiblePlans`, `paretoPlans`, `mean`, `median`, `standardDeviation`, `p05`, `p25`, `p75`, `p95`, `probabilityNegativeCashFlow`, `probabilityPositiveCashFlow`. Send only metrics relevant to the explicit question. Additional/nested private context is rejected. Domain context names should be mapped explicitly to this transport contract.

## Staging and production setup

Create distinct Firebase projects yourself, enable email/password Auth and Firestore, and generate platform app configurations using FlutterFire. Supply the app's environment-specific configuration. Register supported App Check providers for each platform and enable enforcement. App identifiers must match signed builds. Review Analytics/Crashlytics consent and collection settings in the mobile release configuration.

Deployment is an explicit operator step, never part of tests:

```powershell
cd functions
npm ci
npm run build
npx firebase deploy --project YOUR_STAGING_PROJECT --config ../firebase.json --only firestore
```

Deploy the non-AI backend functions first if no AI provider is configured:

```powershell
npx firebase deploy --project YOUR_STAGING_PROJECT --config ../firebase.json --only "functions:farmtwin:publishHarvestPassport,functions:farmtwin:deleteHarvestPassport,functions:farmtwin:publicPassport,functions:farmtwin:deleteFarm,functions:farmtwin:deleteAccount,functions:farmtwin:cleanupDeletedAuthUser,functions:farmtwin:cleanupDeletedHarvestBatch,functions:farmtwin:retryDeletions"
```

Cloud Scheduler and second-generation Functions need their associated APIs/billing/IAM enabled. The Auth deletion trigger uses first-generation Auth events; the other functions use second-generation functions.

Optional AI uses an OpenAI-compatible chat-completions transport. Set server parameters from `functions/.env.example`, including an explicitly chosen provider HTTPS endpoint, allowed hostname, model, quotas, and timeout. Set `AI_PROVIDER_KEY` through `firebase functions:secrets:set` for the selected staging project, then deploy `explainFarm`. Never use an actual provider token in source or client configuration. Set `AI_ENABLED=false` to disable cloud inference. The client must also require the user's cloud-assistant consent and use local explanations on any typed failure. Server disabled/quota/failure states cannot fabricate fallback metrics.

Before production deployment, run the same emulator suite, verify indexes/TTL policies deployed successfully, test Firestore App Check enforcement on signed devices, verify publication and deletion end to end, configure cleanup-failure alerts, review quotas/provider data retention, and perform the app release checks. No successful emulator test implies that these external release steps have occurred.
