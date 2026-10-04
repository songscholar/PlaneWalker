# Plane Walker P15D Native Semantic Effects Evidence

- Status: Implemented / Current
- Document Role: Current focused semantic transaction and native healing evidence
- Authority Level: Below Full Product completion and P15 hostile specification
- Applies To: Sealed semantic batches, native support healing, bounded zone projection and support controls
- Owner: Project owner
- Depends On: `../superpowers/plans/2026-10-05-plane-walker-p15d-native-semantic-effects.md`
- Last Verified: 2026-10-05
- Implementation Status: Transaction foundation verified; complete enemy semantics remain in progress

## Verified Mechanics

`LaunchSemanticEffectAuthority` authenticates the actual Launch Actor script and its sealed prepared frame batch. Healing excludes self, Bosses, dead/finalized actors, recovering actors and support-only peers. Targets use HP ratio and stable ID. Encounter counters retain source and shared recipient caps; simultaneous support sources reserve the remaining native missing HP before charging their budgets.

The authority prepares without mutation, validates exact bounded checkpoints, refuses forged tickets, commits native raster zone projections and status sources, and compensates on rollback. Zone reservations retain delayed decisions. Admission first counts every surviving active hazard, then admits pending effects under both the twelve-zone room limit and authored owner cap. A delayed effect receives its own warning and finite lifetime from admission.

Fixed-frame controls now accept attack/speed buffs up to 1.25 and attack debuffs down to 0.80. Each category uses its strongest source; buffs and debuffs multiply once. Original callers retain the unchanged default modifier dictionary after expiry. Enemy hit facts multiply the accepted attack control. Boss temporal relocation uses a sealed motion flag, tests arrival overlap and preserves the historical landing independently of movement slow.

HP history now records only actual observations, retains at most 180 accepted frames and rejects stale-history checkpoints. Native Priest tests distinguish a target first observed injured from one observed at full HP before subsequent damage. Only the latter can recover historical health, capped at thirty percent of its own maximum. Watcher final death applies its authored 0.80 attack modifier only to recipients that it actually healed.

Titan final death retains two independent native warnings: sixty frames before the forty-point corpse explosion, and sixty-one before the finite lava pool. The canonical `corpse_pool_radius_px=32`, `corpse_pool_damage=8`, `corpse_pool_tick_frames=60` and `pool_lifetime_frames=180` produce exactly three pool ticks, then retire their registry facts and native nodes. These new content fields have their own focused canonical contract commit.

The authority supplies `work_records_for_snapshot` and a foreign active-zone capacity input for the coordinated shared twelve-zone budget. `bind_native_targets` projects cold restored statuses onto actual actors and Player. `dispose_native_effects` removes only its `launch_semantic|movement` Player source and `semantic_*` Actor controls, preserving other owners' modifiers.

Zone records now distinguish `initial_damage` from recurring `damage`, with independent `tick_damage_type`. Ordinary corridors/pulses apply their authored initial hit once and preserve only their slow afterward. The canonical Bramble growth, Rift fusion, time storm and flame breath retain their declared DOT damage from the actual action hit schedule. Fissure pool damage uses the canonical Forge lava-pool baseline; Chaos outburst periodic burn uses its existing authored burn damage and Fire damage type. The multiplier comes from the sealed current hit fact, retaining accepted-frame control and species scaling. Boss periodic zones still require their separate per-mechanism verification.

Guard and Hound native lethal preparation now authenticates the active Health transaction frame. A bounded lifecycle claim in the existing mechanism claim ledger prevents counting that same lethal frame as elapsed recovery time. Guard retains all ninety subsequent frames, and Hound all three hundred; actual Router healing restores fifty-four and thirty-five HP respectively. Direct domain damage keeps its existing frame-zero behavior. This change adds no checkpoint fields or canonical content changes.

## Verification

All logs are under the platform temporary test root. Godot line coverage is unsupported.

- `launch_semantic_effects`: missing authority RED `d3M477`; complete-budget RED `Gc293B`; foundation and pending-admission GREEN `aBauh9`.
- `launch_semantic_effects`: actual two-healer Router/Health sink GREEN `kdKO32`, 1/1, zero engine errors/leaks. Three missing HP produces one three-point heal observation and charges only the first source; the later source retains its budget.
- `hostile_control_runtime`: missing support kinds RED `NDHIDE`; strongest-only, bounds, expiry and strict restore GREEN `Xv0Vnl`, 1/1, zero engine errors/leaks.
- Existing twenty-two enemy domain regression: `4BE4Ac`, 1/1 GREEN, zero engine errors/leaks.
- Real historical healing and Watcher final-death recipient penalty: meaningful RED `hX5ObA`, GREEN `JZPxix`, clean logs.
- Actual finite Titan terminal hazards: `Hn9OAk` and canonical-data rerun `pEcPuc`, 1/1 GREEN, clean logs; refreshed enemy definition/domain contract `qBBY7w`, 1/1 GREEN.
- Cold status binding and precise room disposal: `gdB553`, 1/1 GREEN, clean logs. An intermediate `nXPwB7` used exact float equality for 1.15 times 0.80; corrected to the existing tolerance-aware assertion and reran.
- Initial-versus-periodic correction: coordinated actual Guard corridor RED `NRSHko` (frame 126 repeated another 28 damage), then Router GREEN `WkmAen`; full owned semantic/history/death/disposal rerun `nXHLTT`, 1/1 GREEN, clean logs.
- Buffered native recovery RED `pfFV40` reproduced both timers ending one frame early. GREEN `vQZTAn` certifies complete recovery intervals, independent Stop, exact actor/Health rollback, stable retry, one healing publication, retained counted parent and one final-death receipt after the next lethal. Existing direct-domain recovery and all twenty-two species regression GREEN `kE2m53`, both 1/1 with clean logs.
- Final typed-frame gate rejects malformed decision Variants without coercion; refreshed native recovery GREEN `ZO2qYn` and twenty-two species/domain GREEN `oKpqpd`, both 1/1 with clean logs.

The initial module parse run `8w2Bfb` and incorrectly named native configuration test run `HrFBw3` are not counted as GREEN. Both issues were fixed before the final native sink run.

## Remaining Work

The paired shared Router, Boss and mixed room-budget tests land in coordinated milestones. Wall, summon, link and portal handlers currently reject explicitly. Storm death pulse and Spore residual reservation paths exist but are not yet certified by focused native assertions. This foundation does not certify whole enemy kits, actual sigils, split/chain hazards, elemental swaps, elite affixes, full replay or whole-room completion. Boss zone timing and values remain per-mechanism native gates rather than inferred from generic zone coverage.
