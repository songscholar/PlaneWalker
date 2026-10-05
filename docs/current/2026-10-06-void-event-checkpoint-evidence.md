# Void Event Replay Checkpoint Evidence

- Status: Focused Verified / Integrated performance pending
- Document Role: Current retained deterministic work and authority evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Void auxiliary historical replay validation across accepted frames
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-void-event-checkpoint-plan.md`

## Reproduced Work and Repair

The unified native profile attributes 3.752 ms/frame to Void auxiliary
validation. The original complete-snapshot cache requires identical complete
bytes, so a new runtime_frame forces replay of an unchanged event history.
The new counted scene confirms this: four actual cast/damage events are replayed
36 times across nine new accepted frames. Its behavioral assertions otherwise
pass. This RED remains in `build/void-event-checkpoint-red/`; its two expected
test failures are the repeated-work count and the absence of a checkpoint.

The candidate retains one event-time replay checkpoint inside each authority.
Reuse requires exactly equal native typed event bytes and full configured
definition/initial-state bytes, safe serializable inputs and a requested frame
at or after the final authenticated event. The retained state precedes final
expiry refresh, so reconstructing an earlier accepted frame cannot lose a
previously expired burn/status. Staged next-frame histories use full replay.
Every candidate still refreshes at its own frame and compares its complete
derived state, including the existing JSON numeric compatibility fallback.
Only a successful complete verdict can publish a new checkpoint.

Checkpoint storage contains privately owned typed bytes, with an instance
mutex, at most 524,288 context bytes, 524,288 event bytes and 1,048,576 replay
bytes. Oversized inputs use the complete original replay path. Configuration
and initial-origin binding release retained checkpoints. There is no event,
state, schema, wire format or public verdict change.

## Verification

Final focused scene is 1/1 strict PASS at
`build/void-event-checkpoint-final-green/`. It proves four _apply calls, instead
of 36, with actual scepter burn and bolt slow history at frames 0, 1, 2, 119,
120, 121, 179, 180 and 181. The same frames are checked against fresh authorities
after explicitly clearing the shared complete-snapshot cache. An independent
review identified the original fresh-call cache hit; the corrected comparison
and later expanded final test pass separately. Earlier attempts remain intact.

The test covers earlier-frame rollback, forged derived values, altered/deleted
events, integer-versus-float event authority, wrong run identity, configured
initial-state mutation, JSON precision compatibility, staged next-frame
refusal, actual phase/terminal events, concurrent distinct accepted frames,
byte-based bounded retention and reconfiguration/origin/run isolation. Actual
domain and caller bytes remain unchanged. Independent read-only review found
no production defect after the fresh-call test correction.
The final scene also passes independently with matching candidate/test hashes
and strict logs at `build/test-evidence/void-event-checkpoint-independent-green/`.

Seven neighboring scenarios pass with paired strict runtime logs: five
`void_auxiliary` scenes at `build/void-event-checkpoint-neighbor-regressions/`,
the complete Boss validation-cache scene at
`build/void-event-checkpoint-boss-cache-regression/` and actual Player/Void
frame scene at `build/void-event-checkpoint-player-frame-regression/`.
Exact declared refusal diagnostics are permitted only inside completed scene
test scopes. No unexpected script/parse errors or leaks are ignored.

| Source | SHA-256 |
| --- | --- |
| Original Void auxiliary at `ee642a7` | `a60428ed9da2f9bdbeccf459ce37658ff064fd32f1a24048c190fe5c19719de0` |
| Candidate Void auxiliary | `b6629255a2bc3c918cf00bb37c5cee7ae6796ce2179bd1ff5a582ba233fff86e` |
| Final counted scene script | `746e517c8bcce3355b1779250432bc260870e1d01f861ad383567227c867d748` |
| Final scene resource | `8a046eb6a47d727cc6ce793974f5d399924e0e95aa4641a0262cb2d850f3061e` |

## Limits

This deterministic work-count gate does not claim milliseconds, FPS or long-run
throughput. Uninstrumented integrated native measurements, complete matrix,
clean validation/line coverage, rendered performance, 45-minute recording,
entity/memory loads and UI completion remain pending. Human playtests are 0/20.
