# Farm data, ownership and persistence

`Farm` is the validated, versioned aggregate shared by manual user input, imported files, explicit Sample Farm, and all engines. Units are explicit: acres, acre-feet, pounds of nitrogen, and the selected ISO currency. Each crop defines its yield unit. Fields, crops, expenses and debts carry provenance with source and timestamps. External assumptions can include provider, retrieval/effective dates and quality metadata. Import relabels every imported assumption and preserves its original source in quality metadata; it never imports ownership.

## Cloud schema

`farms/{farmId}` contains `schemaVersion: 1`, immutable `ownerId`, `name`, `source`, server `createdAt` / `updatedAt`, and `data: Farm.toJson()`. The typed aggregate is the authoritative location for fields, crop profiles, crop history, expenses, debts, constraints, scenarios configured as farm stress assumptions, and farm settings. Replacing it is one atomic Firestore write: related inputs cannot be partially saved. A 900,000-byte application limit leaves headroom below Firestore's document limit. Oversized farms return a typed failure, never truncate.

Subcollections `scenarios`, `optimizationRuns`, `simulationRuns`, and `harvestBatches` contain records with `schemaVersion: 1`, server timestamps and a `data` map. Scenario library records are separate saved variants; the farm aggregate's scenarios are current stress assumptions. Only calculated run summaries are stored, not candidate populations or raw simulation draws. `members/{uid}` supports owner-assigned editor/viewer access in rules; current farm listing shows the signed-in owner's farms. Member invitation/discovery is not a shipped UI feature.

`users/{uid}` holds versioned opt-in settings and an update timestamp. Consent also persists locally so SDK collection is configured before fetching cloud settings. All three optional consents default off. Emulator use disables telemetry regardless of saved consent. Platform manifests must also disable Firebase telemetry's native startup defaults.

`publicHarvestPassports/{id}` is server-authored and read-by-ID only. Publication copies an explicitly selected allowlist from a private batch, marks it farmer supplied, and excludes farm IDs, user IDs and financial fields. Server-only reverse indexes allow account/farm deletion to remove publications. Deletion callables freeze writes and recursively remove descendants; clients cannot directly delete farm containers and leave orphaned records.

## Offline and conflict behavior

Native Firestore persistence is enabled. Loaded farms can be read from cache and edits enter Firestore's pending write queue; listeners receive local changes immediately. The save future resolves when the server acknowledges the write, so disconnected writes may remain pending. Pending writes are not represented as server-confirmed saves. Cloud creation, account changes, publication and recursive deletion need connectivity. Web uses memory cache, appropriate for shared browsers holding sensitive farm data.

Aggregate changes use Firestore's last-write-wins semantics. Simultaneous editing of the same farm from different devices can overwrite the older aggregate. There is currently no collaborative merge UI; this limitation must be reviewed before enabling farm membership in the product.

## Explicit Sample Farm

`SampleFarmRepository` begins empty, has no Firebase dependency, and imports bundled input JSON only when `loadSample()` is called. Its local preferences workspace is labelled sample, supports the same repository methods and domain engines, and survives restarts. Reset re-reads input data and removes saved sample run summaries. Corrupt local data yields a typed failure and stays untouched. Local mutations are serialized to prevent concurrent saves losing records. Shared preferences are for the sample workspace and consent, not a fallback store for private production farms.

## Migration and export

`FarmDataCodec` validates IDs, finite JSON values, size and domain rules. Unversioned farm exports migrate to version 1 by adding structural version/scenario metadata only; required business assumptions remain required. Unknown future versions fail with an update instruction. `FarmExportService` exports a versioned, human-readable JSON object containing all aggregate assumptions and provenance. Saved run summaries and harvest batches are separately owned repository entities and are not included in an aggregate export. Export never uploads data. Import validates before returning a new farm; the UI explicitly saves the returned farm under a new ID.
