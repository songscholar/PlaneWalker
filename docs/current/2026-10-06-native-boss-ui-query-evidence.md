# Native Boss UI Query Evidence

- Status: Implemented / Current
- Document Role: Current focused native Boss UI observation verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Actual Boss UI observations shared by presentation and combat consumers
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-boss-ui-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

Boss UI input queries read current runtime frame, a detached current action and
the phase, delay and enrage scalars. The existing Actor UI endpoint uses this
projection when present and retains its original complete-snapshot fallback
otherwise. Endpoint field order, types, labels, remaining-time calculation,
actual Health values, translation and exposure authority remain unchanged.
No presentation clock/cache, gameplay value, state schema, restoration,
receipt, cold verifier or physical check changes.
Independent read-only review of both production diffs and the complete
five-Boss focused contract found no actionable issue.

The presentation proxy reads the endpoint every animation process, while the
Host HUD observes it at its original 0.1-second interval. Projectile and
control-conversion consumers share the endpoint. Existing exposure querying
still performs its original authoritative work and can capture auxiliary
state. This slice eliminates complete Boss captures in the UI endpoint; it
does not claim that all auxiliary history observation is removed.

## Focused Contracts

`build/native-boss-ui-red` demonstrates the original repeated captures: each
of the five authored actual Boss actors makes exactly 16 complete Boss
snapshots for 16 UI observations. All original endpoint typed-byte comparisons
pass; the five capture-count assertions fail without script/parse failures or
leaks. The first GREEN exposed incorrect fixture assumptions about Forest
root-sweep target placement and extending Character exposure outside recovery;
the fixture now uses the authored Forest spore action and actual recovery-tail
admission.

Final GREEN is retained in `build/native-boss-ui-green-2`. Counted real runtimes
for all five authored Boss scenes preserve every UI output byte against the
original full-snapshot algorithm through configured idle, warning, active,
recovery, pending and active Character exposure, actual phase change, terminal
state and complete historical rollback. Each set of 16 repeated UI reads takes
zero complete Boss snapshots. Mutating UI output cannot alter complete gameplay
state. Nested action arrays/dictionaries and mechanism query output are also
detached. Unconfigured queries are empty, and query-less runtime fallback takes
one original complete capture with exact original endpoint output.

All 48 focused scenes pass:

| Contract | Retained Logs | Scenes |
| --- | --- | --- |
| Actual five-Boss UI observation | `build/native-boss-ui-green-2` | 1 |
| Native boundary observation | `build/native-boss-ui-hostile_boundary_observation_test` | 1 |
| Native Void geometry observation | `build/native-boss-ui-void_geometry_observation_test` | 1 |
| Native hostile Bridge | `build/native-boss-ui-hostile_frame_bridge_test` | 1 |
| Actor transaction and rollback | `build/native-boss-ui-launch_actor_transaction_test` | 1 |
| Actual Void Player frame | `build/native-boss-ui-void_player_frame_test` | 1 |
| Actual Boss actor | `build/native-boss-ui-launch_boss_actor_test` | 1 |
| Combat presentation feedback | `build/native-boss-ui-combat_feedback_runtime_test` | 1 |
| Enemy unit contracts, including concurrent Void checkpoint slice | `build/native-boss-ui-enemies` | 40 |

Every paired stdout/Godot log passes strict scoped runtime validation. Bridge
declares four exact expected synchronous refusal operations; Void Player frame
declares one. Every scope has its exact message/count, returns false and
completes in both logs. There are no unexpected errors, warnings, script/parse
failures or object/RID leaks. Godot is `4.6.1.stable.official.14d19694e`; line
coverage is unsupported. Documentation governance and diff whitespace checks
pass.

## Remaining Measurement

The earlier unified diagnostic times 3,040 complete Boss snapshots across 120
actual frames, but does not separately attribute UI work. Counted snapshots
establish eliminated observations, not a measured complete-frame speedup.
Integrated native timing, sustained throughput, rendered performance, 45-minute
soak and human playtesting remain separate gates. Visual UI polish is also a
separate product acceptance gate.
