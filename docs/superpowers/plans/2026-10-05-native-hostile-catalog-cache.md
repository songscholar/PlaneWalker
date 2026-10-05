# Native Hostile Catalog Cache Plan

- Status: Implemented / Current
- Document Role: Current completed focused verification plan
- Authority Level: Below approved full-product completion contract
- Applies To: Native summon and enemy spatial catalog configuration
- Owner: Plane Walker verification lane
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-06
- Exit Gate: Exact raw-source isolation, cold validation, bounded concurrency and measured real-frame regression checks pass

## Completion Criteria

The confirmed frame profile repeatedly reparses nine summon definitions,
ordinary enemy projections, parent summon actions and five spatial actions.
Retain at most four completely accepted catalog results per runtime class,
keyed by the exact current raw file bytes. Store detached typed bytes,
synchronize shared reads and writes, and decode fresh instance dictionaries.
Native run/frame/pending checks and snapshot boundary validation remain intact.
Changed or malformed raw sources must miss the cache and run all existing
definition/action parsers; failed catalogs never become reusable entries.

- [x] Add the cache contract and retain missing-cache RED before implementation.
- [x] Add the two bounded, synchronized exact-source caches.
- [x] Verify raw-source mutation, typed forged fields, instance isolation, native boundary guards, eviction and concurrent workers.
- [x] Run focused native summon/spatial admission, lifecycle and checkpoint regression scenes with strict log validation.
- [x] Measure frozen actual Main Player frames before and after the combined catalog/action cache change; no isolated attribution is claimed.
- [x] Retain focused source, tests and evidence in a reversible local commit.

## Retained Evidence

See `docs/current/2026-10-06-native-hostile-cache-retention-evidence.md` for the
assertion RED, final GREEN, 15 regression scenes, frozen source identities,
actual Player timing distributions and exact physical replay comparison.
The bounded cache milestone is complete; whole-game performance, the native
750-case matrix, clean certification and human playtesting remain separate.
