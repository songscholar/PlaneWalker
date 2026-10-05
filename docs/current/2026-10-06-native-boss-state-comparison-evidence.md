# Native Boss State Comparison Evidence

- Status: Implemented / Current
- Document Role: Current focused complete Boss equality verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Equality-only complete live Boss and component observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-boss-state-comparison-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No FPS, rendered, soak, coverage or human certification

## Verified Boundary

`matches_snapshot(value)` compares the complete live state with a detached
snapshot using the original Godot dictionary equality. Eleven leaf runtime
types own their complete state comparison. Boss composition checks every configured
component, removes overridden composition fields from shallow base maps and
compares every remaining field. Missing, extra and wrong-type component fields
retain the original result. An unconfigured Boss matches only the empty
dictionary. Components without the predicate retain the original complete
snapshot fallback. No internal live references escape through this boolean API.

This API is restricted to equality-only observations. A matching value does
not certify replay safety, schema validity, physical validity or restoration.
Existing full validation, native accepted-boundary checks, historical
restoration, compensation captures and receipt handling are unchanged. Public
snapshots still return deeply detached state. The separate Actor integration
uses the predicate only for the runtime portion of its existing complete
pre-commit comparison.

Independent read-only review found no actionable issue in the production
composition or leaf predicates. The Actor integration was independently read
and likewise preserves its original fields and fallback.

## Focused Contracts

`build/native-boss-comparison-red` fails only the missing Boss API assertion,
without script/parse failures or leaks. The initial GREEN passes. Extending the
fixture to replace every container exposed an invalid test mutation: setting
`null` into a typed Dictionary array. Strict logs correctly reject that run in
`build/native-boss-comparison-green-2` despite its assertion summary. The final
fixture uses allowed container values and separately tests wrong-type child
fields. Final GREEN is retained in `build/native-boss-comparison-green-3`.

All five authored Bosses compare against the original complete snapshot through
configured idle, authored warning/active/recovery/idle, pending and active
Character exposure, actual controls, phase transition, terminal state and full
historical rollback. Every nested scalar and container mutation, missing field,
extra child field and wrong-type child field preserves the original verdict.
Integer/float changes preserve the original Godot numerical equality rather
than introducing a new typed validity requirement.

Sixteen repeated equality observations and all mutation comparisons take zero
complete Boss or configured component snapshots. A query-less real Control
wrapper takes exactly one original capture for each equal or unequal
comparison. A stale composed base field is overridden exactly as in the
original snapshot. Three concurrent read-only workers per Boss preserve equal
and forged verdicts without changing any typed domain bytes. Mutating public
snapshot output also leaves complete live state unchanged.

| Contract | Retained Logs | Scenes |
| --- | --- | ---: |
| Enemy unit contracts, including complete comparison | `build/native-boss-comparison-enemies` | 41 |
| Final extended comparison fixture | `build/native-boss-comparison-green-3` | 1 repeated |
| Native Actor transaction and rollback | `build/native-boss-comparison-launch_actor_transaction` | 1 |
| Actual five-Boss Actor | `build/native-boss-comparison-launch_boss_actor` | 1 |
| Actual Void Player frame | `build/native-boss-comparison-void_player_frame` | 1 |
| Actual Boss UI observation | `build/native-boss-comparison-boss_ui` | 1 |
| Native Void geometry observation | `build/native-boss-comparison-void_geometry` | 1 |

All final paired stdout/Godot logs pass strict scoped runtime validation. The
Void Player frame retains its exact expected synchronous refusal scope. There
are no unexpected errors, warnings, script/parse failures or object/RID leaks.
Godot is `4.6.1.stable.official.14d19694e`; line coverage is unsupported.

## Remaining Measurement

The retained diagnostic identifies repeated complete snapshots, but operation
counts alone do not establish a complete-frame improvement. Uninstrumented
integrated timing, sustained throughput, rendered performance, 45-minute soak
and human playtesting remain separate gates. Visual UI acceptance also remains
open.
