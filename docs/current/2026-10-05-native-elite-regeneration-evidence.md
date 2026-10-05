# Native Elite Regeneration Evidence

- Status: Verified Locally / Partial Milestone
- Document Role: Current milestone retention evidence
- Authority Level: Below P15 hostile specification
- Applies To: Native Regenerating affix, actual Health publication and typed physical cold checkpoints
- Owner: Plane Walker implementation team
- Depends On: `../superpowers/plans/2026-10-05-native-elite-affixes.md`, `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Native regeneration and physical checkpoint regressions pass; complete seeded affix selection and remaining dynamic mechanisms stay tracked

## Verified Behavior

The canonical Regenerating affix now has a native fixed-frame runtime. Actual
elite Health heals three percent of maximum HP every 120 accepted unpaused
source frames. Total actual gain cannot exceed thirty percent of maximum HP for
that encounter. The actual 160-HP sentinel heals 4.8 HP per eligible interval,
with a 48-HP total cap. Authentic heavy Player hits interrupt regeneration for
120 accepted frames; both current-frame and next-frame damage acceptance are
covered. Stop pauses the source clock through the exact expiry boundary, and
final native death terminates both species and affix clocks.

Affix preparation reserves a bounded candidate amount. The existing native
Effects authority applies Health and publishes the authentic health-gain fact
after the Actor commits. Actual gain settles the affix expenditure, including
zero gain when a support actor first fills the Health deficit. A real Rift
Watcher completes its thirty-frame warning at the same frame-120 regeneration
boundary. With one missing HP, support restores one and regeneration charges
zero; with seven missing HP, support restores five and regeneration charges two.
Rejected shared frames restore actual Health, species facts, semantic healing
ledgers, affix spending and both clocks before a deterministic retry.

An actual Player/HostileFrameBridge late World rejection at frame 120 retains
the complete Player and Actor checkpoints and publishes no heal. Retrying that
accepted frame publishes exactly one native 4.8-HP observation. Closed runtime
configuration validates canonical sorted IDs, legal floors/exclusions, immutable
fixed multipliers, pending identities and bounded source identity. Cold restore
refuses cap overflow, pre-120 healing, and inconsistent affix/species terminal
states. Native cold capture refuses an active Health signal transaction.

The definition compiler revision participates in its existing digest. New native
compiler revision 2 carries the affix runtime; explicit revision 1 reconstructs
the committed static compiler and its exact prior signature. Historical
regeneration metadata therefore keeps its no-heal behavior for that saved room.
Both variants pass actual SaveService primary-file write, fresh-service read,
typed Actor/effects/threat reconstruction and identical continued native
branches. No authored content hash or Save schema changes in this slice.

## Reproducible Evidence

- Initial missing native healing/clock RED: `planewalker-tests.ROB2bt`.
- Shared real support/healing expenditure RED: `planewalker-tests.f0sfMw`.
  Its named assertions reproduce phantom expenditure and a false last-heal
  frame. Exploratory fixtures `ktixez`, `ZpVzmZ` and `fcCfOw` are not accepted
  as that clean reproduction.
- Final native regeneration, real support collision, physical SaveService
  roundtrip at the first heal and exhausted fractional cap, legacy compiler,
  stale settlement refusal, heavy interruption, Stop and late Player rollback:
  `./tools/run_tests.sh --filter launch_elite_regeneration --timeout 90`,
  GREEN `u9nSwD`; earlier shared-healing GREEN `EkZ2Et`.
- Static native affix regression: `launch_elite_affix`, GREEN `JXnTS9`.
- Native Actor transaction regression: `launch_actor_transaction`, GREEN
  `ATs0Vt`.
- Native enemy Actor regression: `launch_enemy_actor`, GREEN `yezn0r`.
- Existing native semantic heal/zone/router regression:
  `launch_semantic_effects`, GREEN `efp0Sp`.
- Real production encounter regression: `production_launch_encounter`, GREEN
  `SV6liR`.
- Complete physical native combat checkpoint scene with fifteen internal cases:
  `./tools/run_tests.sh --filter native_combat_checkpoint --timeout 150`,
  GREEN `XcGEhT`. The ninety-second attempt `m4mphm` timed out and is not passing
  evidence.

The strict runner and an explicit log scan found no script errors, deferred
method failures, ObjectDB leaks or RID leaks in these passing directories.
Regeneration's Player test deliberately emits the frame-120 rejection diagnostic;
it verifies rollback and retry rather than treating that diagnostic as failure.
Scene-runner line coverage is not collected by the stock Godot binary. The
isolated instrumented coverage provider is a separate certification lane.

## Retention And Remaining Scope

This focused milestone is reversible through its exact local commit and
preserves the explicit historical compiler. It certifies actual Actor, Player,
Effects and physical SaveService fixtures, not natural full-Main selection of
Regenerating. Authored encounters still use their fixed affix IDs; seeded
`elite_affix_v1:<floor>:<node>:<spawn>` selection and its historical encounter
definition compatibility require a separate implementation gate.

Shielded, Nullified, Anchored, Teleporting, Chaining, Splitting and Mirroring,
complete cues/child ownership, legal-pair matrices and full P15 production
certification remain in the approved plan. Actual player gameplay feedback and
external publication are not supplied by these local tests.
