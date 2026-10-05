# Replay Prefix Cache Validation Plan

- Status: Approved
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: ReplayRecorder capture digests and event prefix roots
- Owner: Project owner
- Depends On: Approved full-product completion contract
- Last Verified: 2026-10-06

## Observed Failure

The frozen `4735176` native floor-four third-phase probe accepts frames
2502 through 3101 and preserves its physical typed recording. Its Player frame
mean is 347.454 ms. An independent diagnostic with the same boundary hashes
attributes 198.120 ms per frame to `weapon_replay_snapshot`, whose only complete
history operation is `ReplayRecorder.event_prefix_root`. At observation 2741,
weapon events occupy 1,246,548 of the observation's 1,596,244 typed bytes.

## Executable Completion Criteria

1. Establish RED for a bounded exact-source positive digest cache before adding
   the implementation. Cover full-byte equality, detached source ownership,
   entry and retained-source-byte limits, oversized fallback, and concurrent
   lookup/store/eviction.
2. Compare cached capture digests and prefix roots against a retained independent
   copy of the current algorithm. Warm the cache before payload replacement,
   nested mutation, type changes, reorder, append, truncate, restore, invalid
   sequence/gap/count, and unsafe value cases.
3. Preserve canonical hash bytes and existing acceptance, including ignored
   capture-event extra fields and count-zero suffix behavior. Never trust a
   hash-only key, cache invalid results, or change public replay schemas.
4. Bound shared caches with mutex-protected state. Use complete typed source
   bytes as keys only after the source is safe to serialize; otherwise execute
   the original validation path.
5. Run weapon replay, full Player cold restoration, native automatic recorder,
   stream store, and codec regressions with strict error/leak scanning. Freeze a
   clean commit for the real late-phase performance probe and retain first/last
   physical readback equality. Performance certification remains blocked until
   the full native frame and sustained rendered workload meet their gates.

## Evidence Boundaries

Cache hit counters prove reuse, not native FPS. Isolated microbenchmarks and
instrumented diagnostics cannot certify unassisted victory or human playtests.
The existing assisted five-floor and 750-case runs continue on their original
frozen commits without overlays.
