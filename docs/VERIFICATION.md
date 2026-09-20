# Verification record

This file distinguishes checks executed in the development workspace from release prerequisites. Last verified: September 20, 2026.

Executed on Windows with Flutter 3.47.5 / Dart 3.13.4, Node 22.20.0, Java 21:

- Android debug APK compiled successfully at `build/app/outputs/flutter-apk/app-debug.apk`. A local source copy outside OneDrive avoided a Gradle reparse-point error; copied source hashes match the workspace. APK SHA-256: `20ad5ce4570412036eb85fa38b0629b7d7c1dc2cdb3bd81323727575a395b177`.
- Web release compilation succeeded at `build/web`.
- Dart formatting and `flutter analyze` passed with no issues. All **70 Flutter tests** passed across domain, data, controller, and widget suites.
- Responsive Flutter widget tests passed for empty startup/explicit sample, all navigation pages, mobile layout, fractional numeric form edits, and whole-number decimal/exponent input validation.
- Domain tests passed for independent financial math, constraints, normalized objective scoring, exact/approximate search diagnostics, Pareto invariants, seeded Monte Carlo properties, cross-field correlations, scenarios, rotation/debt projection, and dynamic explanations.
- Data tests passed for durable local sample CRUD/reopen/reset, validation/migrations/import provenance, consent boundaries, deferred analytics initialization, late write acknowledgment/failure, cached records across account changes, and harvest record validation. Controller tests reject stale calculations and save completions after a workspace switch.
- Firebase backend strict TypeScript compile, 6 unit tests, and 9 Auth/Firestore emulator tests passed. Deployed runtime `npm audit --omit=dev` found no vulnerabilities; development CLI advisories are tracked separately.

All three browser integration targets passed with Chrome 153 and local `demo-farmtwin` emulators:

- `sample_flow_test.dart`: explicit input loading, real optimization/simulation, form-edited water constraint changing the allocation, saved summaries, calculated explanations, and persisted sample recovery after application/controller recreation.
- `production_flow_test.dart`: actual Firebase signup, arbitrary farm CRUD, independently checked financial results, optimization, simulation, scenarios, settings, offline write queue/reconnection, repository/sign-in recovery, sanitized publication/unpublication, farm deletion, and account deletion.
- `user_flow_test.dart`: account and farm creation through actual UI forms; crop, field, expense, debt, and constraint entry; optimization and simulation; scenario re-optimization and risk simulation; saving/recovering three summaries; application/controller recreation; sign-out/sign-in; canceled reauthentication stopping deletion; and completed account deletion.

Browser restart checks recreate application/controllers or repositories within the test process. They do not establish native force-stop/cold-start recovery. Real-device checks remain below. The GitHub workflow now includes these browser targets; its shell/YAML and environment wiring were checked locally, but the hosted workflow has not been run.

Actual baseline profiling is reproducible with:

```sh
dart run test/domain/benchmark.dart
```

Measured on this Windows machine in a cold Dart VM run: sample optimization 584,050 microseconds, paired five-year projection 9,584 microseconds, 5,000-draw simulation 48,415 microseconds. The sample generated/evaluated 15,625 assignments, rejected 11,414, and found 4,211 feasible. Its frontier limit retained 300 points and reported approximation. The process used 209,125,376 bytes RSS before and 243,290,112 after, with 288,428,032 maximum RSS. These are development measurements of that input/runtime, not promises for phones or other farms.

Not yet established by these checks: store approval, signed Android release, iOS build/signing, real mobile App Check, native offline/device behavior, production deployment, mobile frame/startup profiling, Firestore read/write cost profiling, or operational deletion monitoring. No live agricultural provider is connected. See [RELEASE.md](RELEASE.md).
