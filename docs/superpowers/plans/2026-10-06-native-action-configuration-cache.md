# Native Action Configuration Cache

- Status: Implemented / Current
- Document Role: Current completed focused implementation and verification plan
- Authority Level: Below approved full-product completion contract
- Applies To: Hostile action definition parsing and native Boss restore cost
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-06
- Exit Gate: Typed source/identity isolation, cold verdict equivalence, bounded concurrent access and actual native before/after measurements pass

## Completion Criteria

The measured Player restore validation repeatedly constructs Boss action
coordinators, reparsing the same authored actions and initial identity.
Cache at most four fully accepted configuration results, keyed by complete
typed bytes for both definition and identity. Decode fresh instance state on
every hit. Snapshot restoration, geometry, receipts and boundary checks still
execute their existing validators.

- [x] Retain missing-cache RED before implementation.
- [x] Implement bounded synchronized positive configuration caching.
- [x] Compare cold and warm verdicts, returned-state mutation, identity changes,
  typed counter changes, eviction and concurrent configuration.
- [x] Run actual action and Boss restore regressions with strict dual-log checks.
- [x] Measure actual native frames before and after combined catalog/action caches, keeping source/load limits explicit.
- [x] Retain source, tests, evidence and a reversible local commit.

## Retained Evidence

See `docs/current/2026-10-06-native-hostile-cache-retention-evidence.md` for
the missing-cache assertion RED and final cold/warm equivalence GREEN.
Integral JSON floats retain the established parser acceptance and normalize
to integer counters; fractional numbers, booleans, foreign actions, unknown
kinds and extra fields retain their complete cold refusal results.
Active snapshot restoration still uses the existing strict validator.
