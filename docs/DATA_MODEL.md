# Farm data, ownership and persistence

`Farm` is the validated, versioned aggregate shared by manual user input, imported files and all engines. Units are explicit: acres, acre-feet, pounds of nitrogen, and the selected ISO currency. Each crop defines its yield unit. Fields, crops, expenses and debts carry provenance with source and timestamps. External assumptions can include provider, retrieval/effective dates and quality metadata. Import relabels every imported assumption and preserves its original source in quality metadata; it never imports ownership.

## Cloud schema

`farms/{farmId}` contains `schemaVersion: 1`, immutable `ownerId`, `name`, `source`, server `createdAt` / `updatedAt`, and `data: Farm.toJson()`. The typed aggregate is the authoritative location for fields, crop profiles, crop history, expenses, debts, constraints, scenarios configured as farm stress assumptions, and farm settings. Replacing it is one atomic Firestore write: related inputs cannot be partially saved. A 900,000-byte application limit leaves headroom below Firestore's document limit. Oversized farms return a typed failure, never truncate.

Subcollections `scenarios`, `optimizationRuns`, `simulationRuns`, and `harvestBatches` contain records with `schemaVersion: 1`, server timestamps and a `data` map. Scenario library records are separate saved variants; the farm aggregate's scenarios are current stress assumptions. Only calculated run summaries are stored, not candidate populations or raw simulation draws. Creation includes `members/{uid}` with `userId`, `role: owner`, and a server creation timestamp in the same batch. Additional memberships support owner-assigned editor/viewer access in rules; current farm listing shows the signed-in owner's farms. Member invitation/discovery is not a shipped UI feature.

The aggregate also stores onboarding `country`, `region`, `declaredAcres`, and the chosen currency in `settings.currencyCode`. Declared acreage is separate from the sum of entered fields, so onboarding never fabricates a field.

`Field.currentCropId`, `compatibleCropIds`, and `cropHistory` reference stable `CropProfile.id` values. Eligibility requires explicit ID membership and the crop's irrigation requirements to be satisfied. An empty current ID represents incomplete setup and cannot be calculated or optimized. New fields select neither a current crop nor compatible IDs automatically. See [CROP_COMPATIBILITY.md](CROP_COMPATIBILITY.md) for strict validation and legacy record repair.

`users/{uid}` holds versioned opt-in settings and an update timestamp. Consent also persists locally so SDK collection is configured before fetching cloud settings. All three optional consents default off. Emulator use disables telemetry regardless of saved consent. Platform manifests must also disable Firebase telemetry's native startup defaults.

`publicHarvestPassports/{id}` is server-authored and read-by-ID only. Publication copies an explicitly selected allowlist from a private batch, marks it farmer supplied, and excludes farm IDs, user IDs and financial fields. Server-only reverse indexes allow account/farm deletion to remove publications. Deletion callables freeze writes and recursively remove descendants; clients cannot directly delete farm containers and leave orphaned records.

## Offline and conflict behavior

Native Firestore persistence is enabled. Loaded farms can be read from cache and edits enter Firestore's pending write queue; the SDK emits pending snapshots immediately, while the application retains confirmed edits and withholds pending creations. The save future succeeds only when the server acknowledges the write; the bounded wait throws a visible pending failure if disconnected. Pending writes are not represented as server-confirmed saves. Cloud creation, account changes, publication and recursive deletion need connectivity. Web uses memory cache, appropriate for shared browsers holding sensitive farm data.

Aggregate changes use Firestore's last-write-wins semantics. Simultaneous editing of the same farm from different devices can overwrite the older aggregate. There is currently no collaborative merge UI; this limitation must be reviewed before enabling farm membership in the product.

## Test fixtures

The synthetic domain fixture is in `test/fixtures/farm.json`. It is not bundled in the application. SharedPreferences stores privacy preferences only; real farm data belongs to Firestore.

## Migration and export

`FarmDataCodec` validates IDs, finite JSON values, size and domain rules. Unversioned farm exports migrate to version 1 by adding structural version/scenario metadata only; required business assumptions remain required. Unknown future versions fail with an update instruction. `FarmExportService` exports a versioned, human-readable JSON object containing all aggregate assumptions and provenance. Saved run summaries and harvest batches are separately owned repository entities and are not included in an aggregate export. Export never uploads data. Import validates before returning a new farm; the UI explicitly saves the returned farm under a new ID.

Legacy crop display-name references normalize only when unambiguous; exact IDs take precedence. The legacy `allowedCropIds` alias becomes `compatibleCropIds`, while conflicting lists fail validation. Missing compatibility stays empty. Normalization never writes automatically or invents compatible crops.
