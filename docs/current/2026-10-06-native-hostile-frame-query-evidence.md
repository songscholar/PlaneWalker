# Native Hostile Frame Query Evidence

- Status: Implemented / Current
- Document Role: Current focused verification and performance evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native hostile frame queries and private Boss preparation previews
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-frame-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

The three production paths add Boss-owned current-frame, terminal and detached
action queries, then use them at internal observation sites. Other hostile
runtimes retain their complete-snapshot fallback. Public complete snapshots
retain their schema and detached mutable descendants.

Each actual hostile retains at most one body and one arena preview. Exact
`var_to_bytes` configuration equality includes definition, identity, and the
Boss's actual arena origin and body position. Every use restores and validates
the complete requested snapshot before preparing a frame. Changed typed
configuration rebuilds or refuses. The previews never replace live actor state,
physical geometry checks, receipt authentication, or transaction rollback.

## Focused Contracts

The missing-query RED is retained in `build/native-hostile-frame-query-red`.
It produces the scoped missing-API assertion without script/parse errors or
object/RID leaks. Final GREEN is retained in
`build/native-hostile-frame-query-green-2` and exercises all five authored Bosses.
It checks current queries, detached action descendants, actual advance,
terminal mutation, historical rollback, preserved original cold-validator
verdicts, separate body/arena ownership, mandatory restore before preview reuse,
changed origin, typed configuration changes, invalid configuration refusal,
and safe retry.

The following strict scene runs pass without runtime errors, warnings, or leaks:

| Contract | Retained Logs |
| --- | --- |
| 39 enemy unit scenes | `build/native-hostile-frame-query-regressions` |
| Native hostile Bridge | `build/native-hostile-frame-query-bridge` |
| Actual Boss actor | `build/native-hostile-frame-query-native-actor` |
| Actor transaction and rollback | `build/native-hostile-frame-query-native-transaction` |
| Actual Void Player frame | `build/native-hostile-frame-query-void-frame` |
| Forest native auxiliary | `build/native-hostile-frame-query-forest-native` |
| Forge native arena | `build/native-hostile-frame-query-forge-native` |

Godot is `4.6.1.stable.official.14d19694e`. Line coverage is unsupported.
Documentation governance and diff whitespace checks pass. No dependency,
gameplay value, recorder buffer, or admission budget changes.

## Uninstrumented Comparison Baseline

The clean `54866d42fb0bf46e55f9afa4bb442595dab14c25` archive at
`build/retained-checkout/native-recording-after-54866d4-20261006` runs
`build/floor4-phase2-uninstrumented-baseline-120/report.json` without timing
instrumentation. Its runtime aggregate SHA-256 is
`468f88a7b2796fcb6a3ea1758a39ba9bf7018b34503812a35c39cf9b059cf160`.
Authoritative content aggregate SHA-256 is
`838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`.

Real Sword admission reaches fifth-floor Void phase index 2 after 2,501 native
frames, then accepts all 120 requested frames 2,502 through 2,621. The physical
tape is `INTERRUPTED`, has 121 observations, no recording failure, and exact
fresh first/last typed-byte readbacks. Its first observation SHA-256 is
`99ac84d00d33f0adcaa628441a2a97cbc9446ec9b31661db83cf60a4e798aca4` and last is
`28a6598b75adc82640b0a850c5c326a2b8558f971c84d8d296ca5f45c0c11f79`.
Strict stdout and Godot logs pass.

| Complete Player Advance | Mean | p95 | Maximum |
| --- | --- | --- | --- |
| Uninstrumented baseline | 55.765 ms | 59.371 ms | 80.675 ms |

Native duration is 2 seconds, wall duration 7.682 seconds, physical retention
14.987 seconds, and peak Godot native static allocation 590,235,928 bytes.
Native static allocation is not process RSS. Other frozen long-running
five-floor validation processes remain concurrently active. This is a focused
headless timing baseline, not an uncontended 60 FPS or rendered performance gate.

## Remaining Measurement

Overlay only this slice's three committed production files onto the same
`54866d4` base, import twice, and repeat the uninstrumented 120-frame interval.
Compare complete typed observations and full Player advance times before
another performance slice. Sustained recording still requires the combined
committed source to pass the separate 600-frame tape/readback gate.
