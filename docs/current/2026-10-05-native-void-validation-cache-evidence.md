# Native Void Validation Cache Evidence

- Status: Verified
- Document Role: Current
- Authority Level: Implementation evidence below approved native hostile contracts
- Applies To: Void auxiliary replay validation and native frame performance
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [native Void arena evidence](2026-10-05-native-void-arena-evidence.md)

## Retained Behavior

Void auxiliary validation retains at most four successful exact checks. Each
cache entry stores native typed bytes of the complete candidate, complete
authored definition, full initial replay state and accepted-boundary mode.
The original header checks still run; a miss still replays every event and
compares the complete derived state. Failure verdicts are never cached.

Typed bytes preserve integer-versus-float event authority, Boolean fields and
all nested values without mutable caller Dictionary references. A Mutex
protects cache reads, duplicate suppression and FIFO eviction across native
recording threads. Fresh runtime instances can reuse a fully validated exact
candidate while source, origin, initial-state and boundary changes remain
independent checks. Cache entries contain no gameplay objects.

The replay's final equality check first uses native complete equality and then
the existing JSON precision comparison when necessary. Historical numeric
representation and rounding compatibility remain covered. Every cold
candidate must still match the canonical event replay; cache reuse does not
authenticate a different candidate or skip a previously unverified boundary.

## Executable Evidence

- RED: `build/native-void-cache-assertion-red`, successful replay lacked the bounded positive cache.
- GREEN: `build/native-void-cache-final-contract`, one scene covers schema/event float rejection, event and derived Boolean types, deleted/modified events, forged casts/statuses, source and full initial-state isolation, external source mutation, original numeric fallback, staged-versus-accepted boundary separation, four-entry capacity and five concurrent workers making 200 valid and 200 forged checks.
- GREEN: `build/native-void-cache-final-regression`, all five existing/new auxiliary lifecycle, actual native settlement, domain, Boss snapshot and cache scenes pass with error/leak scanning.
- GREEN: `build/native-void-cache-player-cold-green`, actual Player frame late-refusal rollback/retry, pickup energy, paid Stop and fresh native owner reconstruction pass.

The first development lifecycle run used an insufficient 60-second limit.
The final run uses 300 seconds and passes without weakening failure checks.
Stock Godot does not emit line coverage; the repository's independent runtime
provider is required for complete-program coverage certification.

## Measured Scope

The isolated probes use the retained native source at `9a48007`, then overlay
only this Void auxiliary change. No attack values or weapon damage change.
Native Player and Boss transaction frames remain real. Logs and probe sources
are retained under `build/` as local development artifacts.

| Probe | Before | After | Scope |
| --- | ---: | ---: | --- |
| 20 repeat validations, 240 events/120 casts | 418,726 us | 16,418 us | 25.5x faster repeated complete auxiliary validation |
| 300 actual Player/Void frames, 8 events/4 casts | 14,796,472 us | 14,114,031 us | 4.6% lower total time in this short-history fixture |

Logs: `build/native-void-validation-performance-probe.log`,
`build/native-void-validation-cached-performance-probe.log`,
`build/native-void-whole-frame-original.log` and
`build/native-void-whole-frame-cached.log`. Thirteen authentic auxiliary history
checkpoints and forged derived counters retain their previous verdicts.
The short-history result does not establish a complete-matrix speedup;
per-frame definition construction remains a measured follow-up candidate.

## Reversibility

This change affects one auxiliary runtime and its focused validation contract.
Snapshots, authored content bytes and external cold envelopes keep their
existing formats. Removing the cache restores unconditional event replay.
Remote publication and full-program certification remain separate gates.
