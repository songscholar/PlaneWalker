# Native Void Exposure Query Evidence

- Status: Implemented / Current
- Document Role: Current focused Void exposure observation evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Boss exposure and Character-tail cutoff observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-void-exposure-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No FPS, rendered, soak, coverage or human certification

## Verified Boundary

The Void auxiliary owns a current integer exposure-cutoff query. Boss exposure
and Character-tail observations use it while preserving their original Boss
frame comparison, terminal handling, short-circuit order and inclusive cutoff.
The query deliberately adds no auxiliary-clock or terminal condition. A
query-less component retains its original complete-snapshot fallback. Full
snapshots, history, receipts, validation and restoration remain unchanged.

## Focused Contracts

`build/native-void-exposure-red` proves that 32 real Boss and Character-tail
observations capture exactly 32 complete auxiliary histories. The only failures
are the expected zero-copy count and missing native API assertions. There are
no script/parse errors or leaks. GREEN is retained in
`build/native-void-exposure-green`.

The real Boss reaches phase two through actual accepted body damage, waits the
complete phase cue and commits the authored tentacle action. Observations
preserve both original boolean algorithms through initial state, phase change,
phase-two idle, warning, tentacle activation, exact inclusive cutoff, expiry,
terminal state and active/initial historical rollback. Actual tentacle exposure
lasts exactly thirty accepted frames. At each observation boundary 16 exposure
and 16 Character-tail checks take zero complete auxiliary snapshots and leave
all typed domain bytes unchanged.

Direct current cutoff changes are observed immediately. Auxiliary retirement
does not introduce a new Boss cutoff rule. An unconfigured query returns the
absent-cutoff sentinel. Query-less fallback takes exactly one original capture
per Boss or Character-tail check. Historical restoration remains validated and
reproduces complete initial state after the direct-mutation fixture.

| Contract | Retained Logs | Scenes |
| --- | --- | ---: |
| Void unit contracts, including the exposure observation | `build/native-void-exposure-units` | 9 |
| Complete five-Boss state equality | `build/native-void-exposure-boss_comparison` | 1 |
| Full five-Boss runtime and conversion contracts | `build/native-void-exposure-boss_runtime` | 1 |
| Actual Boss UI observations | `build/native-void-exposure-boss_ui` | 1 |
| Actual Void Player frame | `build/native-void-exposure-void_player_frame` | 1 |

All final paired stdout/Godot logs pass strict scoped runtime validation. The
Void Player frame retains its exact expected synchronous refusal scope. There
are no unexpected errors, warnings, script/parse failures or object/RID leaks.
Godot is `4.6.1.stable.official.14d19694e`; line coverage is unsupported.

## Remaining Measurement

Counted observations prove eliminated copies, not a measured complete-frame
improvement. Uninstrumented integrated native timing, sustained throughput,
rendered performance, 45-minute soak, visual UI acceptance and human
playtesting remain open.
