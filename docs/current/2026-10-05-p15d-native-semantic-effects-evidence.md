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

Native Storm final death retains all thirty-five warning frames before a nondamaging pulse applies the authored 0.70 Player slow. Its warning fact and raster projection retire after activation; its finite status expires independently. Actual Spore burst resolves twelve damage after thirty warning frames, consumes its real Health once after the active window, and retains a separately warned residual pool. The pool ticks five damage exactly three times over its 180-frame life. Residual slowdown follows area membership rather than borrowing the sixty-frame damage interval as an unauthored linger. Leaving and reentering the pool does not reset its tick phase, and expiry removes zone work, registry facts, native nodes and slowdown.

New Storm time fields retain a closed `storm_pattern` decision from the canonical seed, source and generation. Exactly one field starts at 1.25 speed and the other at 0.60 speed. Their clocks start at native admission, swap every ninety accepted frames and warn for the final thirty frames before each swap. Source Stop does not halt independent admitted fields. Both Player and native allies receive area-bound movement control, while periodic Time damage remains Player-only. The nondamaging death pulse also applies its authored slow to native allies. Gold and cyan original raster pools distinguish the fast and slow phases; native matching authenticates the actual texture, animation frame and warning tint before preparation.

The existing V1 checkpoint accepts two closed layouts: original zones without pattern metadata, and new Storm zones with validated bounded metadata. Legacy fields retain their original finite behavior until TTL; restoration never fabricates a historical seed decision. This change adds no checkpoint version or canonical content-hash change. Typed replay codec reconstruction, compensation and retry preserve the actual native pattern phase.

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
- Native Storm pulse and Spore burst/residual RED `f7XhS7` caught the unauthored residual slowdown after expiry. GREEN `dxFX3e`, 1/1, clean engine logs, also verifies membership exit/reentry, original tick phase, exactly three residual damage ticks, one counted consumption receipt and complete finite teardown.
- Native Storm ally death control RED `v00Kfg`; GREEN `TIRkGI`, 1/1, clean logs. An independent fixture Stop holds the ally's own actions without masking its movement modifier.
- Native seeded Storm pattern RED `r0R3vn` reproduced missing pattern metadata. Final GREEN `8rilkl`, 1/1, covers deterministic replicas, complete first warning, exactly three periodic ticks, membership exit/reentry, ally controls without friendly damage, thirty-frame swap warning, ninety-frame boundary, rejected frame 100 compensation/retry, cold typed replay reconstruction, malformed metadata and native presentation refusal, closed legacy restoration and finite teardown. Complete owned semantic regression GREEN `0ktrkj`, 1/1, clean logs.
- Actual OpenGL compatibility window on Apple M4 Pro: `/private/tmp/planewalker-storm-visual.log`, clean PASS with no engine errors or leaks. Six retained screenshots in `build/visual-evidence/p15d-storm-pattern/` cover initial, warning and swapped phases at 640x360 and 1280x720; both fields passed foreground pixel/color checks. Initial, warning and swapped native-size screenshots were inspected and are nonblank, correctly colored and unclipped. The fixture character naturally overlaps the left field.

The initial module parse run `8w2Bfb` and incorrectly named native configuration test run `HrFBw3` are not counted as GREEN. Both issues were fixed before the final native sink run.

## Remaining Work

The paired shared Router, Boss and mixed room-budget tests land in coordinated milestones. Wall, summon, link and portal handlers currently reject explicitly. This foundation does not certify whole enemy kits, actual sigils, Spore chain depth or elite splits, elite Storm stasis and owner immunity, elite affixes, full replay or whole-room completion. Boss zone timing and values remain per-mechanism native gates rather than inferred from generic zone coverage.
