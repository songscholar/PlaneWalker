# Boss Snapshot Validation Cache Evidence

- Status: Focused Verified / Full gameplay certification pending
- Document Role: Current native gameplay performance retention evidence
- Authority Level: Implementation evidence below the gameplay completion plan
- Applies To: Five Launch Boss snapshot validation and production Main recording
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/plans/2026-10-06-gameplay-ui-product-completion.md`
- Last Verified: 2026-10-06
- Contract References: `scripts/enemies/launch/launch_boss_runtime.gd`, `tests/unit/enemies/boss_snapshot_validation_cache_test.gd`

## Retained Change

Each configured Boss retains at most four successful validation results as
detached, exact typed bytes. Every miss runs the original complete validator;
refusals never enter the cache. A mutex protects lookup, insertion, eviction and
reset. This supports concurrent readers; it does not introduce concurrent
configuration or gameplay writers.

The context includes the full normalized Boss definition, configured identity
and digest, both arena origins, child identities/nonempty state, Time response
mechanisms, complete initial arena states, auxiliary definitions and live arena
origins. Ruin's current cover identifiers participate because its validator
consults the live cover lookup. Configuration and every origin-binding attempt
clear the cache before any child may change, including unsuccessful attempts.

General restoration retains its existing allowance for staged next-frame arena
events. `can_restore_native_snapshot` still runs all strict accepted-boundary
child validators after a general cache hit. No save schema, clock, HP, action,
receipt, rollback, historical migration or native authority rule is removed.

## Verification

- RED: `build/test-evidence/boss-snapshot-validation-cache-red` retains five failures for the missing bounded positive cache before implementation.
- GREEN: `build/test-evidence/boss-validation-cache-regressions` includes the new cache scene and all five Bosses' domain, temporal, phase, action, forest, forge, void, response and auxiliary regressions. The batch passed 35 of 36 scenes; its remaining failure was an existing Mirroring test hardcoded to the previous default revision.
- The cache scene checks warm/cold typed verdict equivalence, malformed snapshots, duplicate claims, mutable caller isolation, exact historical rollback, bounded eviction, reconfiguration, changed origins, concurrent readers and a real staged flower event refused by strict native restoration.
- Independent read-only review found no actionable correctness regression in the cache context or accepted-boundary behavior. Remaining input-memory limits and concurrent-writer limitations were explicitly identified.

The unrelated Mirroring test repair is retained separately: default projection
must match `CURRENT_NATIVE_REVISION` (currently 10), while explicit revision 9
still has an executable Mirroring clock and explicit revision 8 remains metadata
only. Its focused RED and GREEN logs are respectively
`build/test-evidence/elite-mirroring-default-red` and
`build/test-evidence/elite-mirroring-default-green`.

## Frozen Performance Pair

Before: `build/retained-checkout/cache-after-c1a24d4-20261006`, report
`build/cache-after-20261006-floor2/report.json` within that snapshot.

After: `build/retained-checkout/boss-validation-cache-after-20261006`, report
`build/boss-validation-floor2-600-hub12/report.json` within that snapshot.
Only `launch_boss_runtime.gd` differs between their runtime source files.
These retained snapshots have source fingerprints, not independent Git HEADs.

Both measured the same floor-2 Boss for 600 actual accepted Player frames at
60 Hz, with 12 Hub frames across all nine functions, concurrent automatic
recording, an explicitly named invulnerability fixture, and fresh physical
readback of the first and last tape samples.

| Player advance metric | Before | After |
|---|---:|---:|
| Mean | 35.111 ms | 28.660 ms |
| p50 | 33.486 ms | 27.518 ms |
| p95 | 65.046 ms | 48.902 ms |
| Maximum | 73.228 ms | 68.539 ms |

Content fingerprints, encounter identity, accepted frames, sample frame range,
observed peak entity counts and both exact tape endpoint hashes match. Each
report passes the native probe validator and strict stdout/engine-log scanning.
These are headless fixed-FPS development timings under concurrent load; they
are not rendered FPS, sustained-load, human or unassisted-victory certification.

An initial after run used 9 Hub frames instead of the before run's 12. Decoding
the physical chunks showed only two Player revision counters differed by three
at both endpoints. That mismatched run is retained as diagnostic evidence; the
reported pair above reran with identical Hub duration and matched exact hashes.

## Remaining Gate

The measured Boss still exceeds the 16.667 ms 60 Hz budget. Arena reconstruction
and native recording remain measured candidates for further work. The complete
five-floor ordinary-input run, all 750 native loadout cases, final clean combined
validation/coverage and rendered sustained performance remain pending. Human
playtesting remains 0/20. UI runtime implementation has not started.
