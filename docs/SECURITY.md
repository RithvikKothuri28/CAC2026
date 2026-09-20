# FarmTwin security model

Private data is scoped to `/farms/{farmId}`. A farm has one immutable `ownerId`. Membership documents grant `viewer` or `editor` access; membership cannot grant ownership. Owners administer membership and publish passports. Editors can edit farm inputs and saved summaries. Viewers can read. Anonymous clients cannot access private farms, user settings, memberships, calculation summaries, or AI quotas. Rules deny every undeclared path and disallow client farm deletion to avoid orphaned descendants.

Every write envelope has a schema version and server timestamps. The Dart domain validates agricultural inputs; the rules validate envelope shape, timestamps, access, and ownership. Firestore rules do not certify farmer-entered claims or calculation accuracy. Farm aggregate snapshots are capped by Firestore's document-size limit; the application must return a typed failure if a farm exceeds its supported persistence size.

## Harvest Passport publication

`publishHarvestPassport` authenticates the caller, enforces App Check in deployed environments, and transactionally verifies ownership. It reads the private harvest batch itself. Clients cannot supply a replacement public document. Each selected value is copied through a type/length/date validator from this allowlist:

`crop`, `field`, `plantingDate`, `harvestDate`, `practices`, `inputRecords`, `handlingEvents`, `storageEvents`, `notes`.

The crop is required. Event records permit only `name`, optional ISO `date`, and optional `details`. Selected missing values, unknown keys, duplicate selections, invalid dates, and nested private fields are rejected. Owner IDs, farm IDs, batch IDs, financials, and all unselected fields are excluded. The public document contains only selected values plus `schemaVersion`, `selectedFields`, `provenance: farmerSupplied`, and `publishedAt`. Farmer-written notes can contain sensitive content; publication consent must be based on the actual selected values.

Public documents permit anonymous individual reads; enumeration and client writes are denied. Publication uses an unpredictable ID and a server-only reverse mapping. Re-publication replaces the entire document, so deselected data disappears. `deleteHarvestPassport` removes the public document and reverse mapping. Farm/account deletion removes published passports. Deleting a private batch invokes a retried cleanup trigger. The public HTML endpoint escapes farmer text, restricts its content-security policy, and uses `no-store` caching to make unpublication effective on subsequent requests. Copies previously downloaded by other people cannot be recalled.

## Deletion and account lifecycle

`deleteFarm` requires ownership, writes a durable deletion job, freezes farm writes, deletes associated passports, then recursively removes all descendants. The retry scheduler resumes interrupted work. `deleteAccount` requires a login within the last five minutes, freezes new user writes, deletes owned farms and publications, removes memberships from other farms, deletes user settings/AI usage, and deletes the Auth identity. An Auth deletion trigger covers administrative deletion. All destructive cleanup is scoped to the authorized account/farm and can resume after failure.

A short-lived server-only `deletedAccounts/{uid}` tombstone blocks writes from already-issued ID tokens after Auth deletion. Its configured Firestore TTL expires after one day; TTL cleanup is asynchronous. Tombstones contain no farm values or email. Quota counters have seven-day TTLs. The scheduler should have alerting for repeated failures before production release.

## Optional AI

Cloud AI runs only after an explicit client request and consent. `explainFarm` verifies Firebase Auth, App Check, farm access, exact request shape, and finite allowlisted metrics. The provider receives the user's question and selected numeric metrics; it receives no farm ID, user ID, farm document, field locations, or debt records. A question may itself contain sensitive information, so the consent UI should advise users what is transmitted.

The server owns the provider endpoint, hostname allowlist, model identifier, quotas, and API secret. Endpoints must be HTTPS, contain no credentials/query string, and match the configured hostname. Redirects are refused. Per-user daily, global daily, and minimum-interval quotas are transactional. Quota is consumed on attempted provider requests, including failures. Errors return typed callable failures that let the client use its local explanation engine.

The provider must reference existing metrics with `{{metricName}}` tokens. The server rejects unknown tokens, numerical literals, malformed tokens, and common spelled-out numerical claims, then substitutes values from the submitted calculated context. This protects displayed figures from provider fabrication; it does not independently verify client computations or establish that all provider prose is correct. Provider prose remains an explanation of modeled assumptions. Never use this service to generate a new farm calculation.

Logs deliberately exclude prompts, questions, numeric context, farm IDs, provider response bodies, and credentials. Secrets belong in Secret Manager, never Flutter, Remote Config, Git, or `.env` files.

## Verification and deployment boundary

Run `scripts/backend-test.ps1` on Windows, or `cd functions && npm ci && npm test` with Node 22 and Java 21+ installed. Automated tests refuse any project other than `demo-farmtwin` and any emulator address outside loopback. Rules tests exercise anonymous and cross-account denial, owner/editor/viewer access, immutable ownership, schema/path denial, allowed entity CRUD, public-field isolation, unpublication, cleanup, quotas, offline queue/reconnect, and persistence across new clients/sign-in. These are backend tests, not a substitute for device/store end-to-end verification.

Callable App Check enforcement uses the Firebase [documented enforcement option](https://firebase.google.com/docs/app-check/cloud-functions). The only bypass requires both `FUNCTIONS_EMULATOR=true` and `GCLOUD_PROJECT=demo-farmtwin`. Real devices still need registered App Attest/DeviceCheck/Play Integrity providers and Firestore App Check enforcement enabled in the Firebase console. Emulator success cannot prove production attestation or IAM configuration. Do not deploy against a real project until configuration, privacy disclosures, monitoring, and device checks are reviewed.

`npm audit --omit=dev` is the release dependency gate. The lockfile pins `gaxios`'s `uuid` to patched CommonJS-compatible `11.1.1`. Firebase CLI development dependencies may have advisories separately from deployed runtime dependencies; review `npm audit` when upgrading the CLI.
