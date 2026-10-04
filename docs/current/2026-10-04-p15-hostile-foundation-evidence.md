# Plane Walker P15 Hostile Foundation Evidence

- Status: Implemented / Current
- Document Role: Current partial-milestone evidence
- Authority Level: Evidence for isolated P15 action, encounter, control, and first native actor foundations
- Applies To: Closed actions, fixed-frame scheduling, strict snapshots, Launch profile selection, pending encounter work, Sentinel domain behavior, and native actor compensation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-04-plane-walker-p15-enemies-bosses.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Partial P15 foundation; production actors, content activation, and whole-repository certification pending

## Delivered Boundaries

`HostileActionContract` validates a closed action record, fifteen handler families and their exact parameter fields, finite geometry, warning/recovery floors, integer frames, bounded schedules, unique hit indices, and deeply isolated normalized data. Unsupported handlers reject; parsing alone does not certify a handler's production implementation.

`HostileActionCoordinator` advances sequential accepted frames through warning, active, recovery, and idle. It freezes quantized source/target geometry, allocates separate generations for each threat primitive, emits one logical scheduled hit for a geometry union, enforces cooldowns, and retires every owned threat on completion or cancellation. Native fact conversion uses the existing strict `HostileTelegraphFact` contract. Restore validates the configured identity/content digest, frame/phase consistency, frozen geometry, generation floors, cooldowns, pause duration, and exactly the scheduled hit claims that should already exist. Stop advances the accepted runtime clock while preserving action state and emits compare-and-swap threat expiry extensions.

`HostileThreatRegistry.extend_fact_through` accepts only an existing source/generation with the exact expected expiry and a strictly later replacement expiry. It revalidates the copied fact and changes no other geometry or identity. Missing, retired, foreign, stale, and shortening requests reject without mutation; existing M1 registry paths remain unchanged.

`LaunchEncounterProfile` validates the five existing profile identities and their exact five-combat/three-elite recipe ID sets. `LaunchEncounterCatalog` resolves those profiles, forty recipe records, and five Boss references using the current ContentRegistry interface. Configuration requires all twenty-two ordinary identities, five Boss identities, ten affix identities, and five profiles, with closed actor/template references and per-wave threat budgets. Selection uses SeedService, respects room templates, and avoids an immediate repeat when another compatible recipe exists. Unknown Launch references return empty definitions.

`LaunchEncounterRuntime` uses fixed frames for wave delay, continuous warning, spawn requests, and terminal completion. Stable source IDs replace Node instance IDs in its domain roster. Nonterminal life states remain counted. Unique final-death receipts, unacknowledged spawns, and bounded pending projectiles/zones/constructs/links/portals/summons prevent premature completion. Failure and cancellation reject further frames. Strict checkpoints support deterministic mid-combat reconstruction without observable mutation on rejection.

`HostileControlRuntime` owns bounded fixed-frame source maps for Stop, Rift, weakpoint, and vulnerability. Duplicate sources cannot restart lifetimes. Stop sources expire independently; Rift takes the strongest source with a `0.40` movement floor; weakpoint takes the largest active bonus; independent vulnerability sources combine under a `3.0` damage multiplier cap. JSON numeric normalization and strict identity/frame/expiry checks protect checkpoint restoration. Terminal cleanup removes every control source.

`LaunchEnemyRuntime` currently implements only the Sentinel mechanism. It uses the common coordinator, seeded initial attack staggering, pursuit, the paired sweep, and a nineteen-pixel retreat over forty-eight accepted action frames. Unsupported native mechanisms reject explicitly. Its action/control/mechanism checkpoint validates together, and action interruption is distinct from terminal cancellation.

`LaunchHostileActor` is an inactive native Sentinel adapter. It reuses EnemyBase's damage and weapon/status helpers, replaces physics and timer gameplay with accepted-frame preparation/commit/compensation, predicts movement through native collision in test-only mode, and projects the authoritative action into a four-frame raster. Its real HealthComponent resolves weakpoint and vulnerability damage. Final Health death clears control/status state and emits one stable encounter receipt; room economy remains an external authority.

`LaunchElementalStatusRuntime` adds complete native compensation snapshots to the existing status implementation. These retain deterministic seed, both slow floors, elapsed tick clocks, ownership, and live burn source/attacker references. They are native transaction records, not persisted Save/Replay seals. Health compensation uses the existing once-only frozen ledger contract; restoring or discarding a checkpoint consumes it.

`tools/generate_launch_enemy_assets.py` produces an original `128 x 32` four-frame Sentinel bitmap and a provenance/hash manifest. The scene has real body and hurtbox collision, HealthComponent, and Sprite2D; its compatibility Polygon2D is hidden. This asset and scene are not in the active content pack.

## Focused Verification

Each new test first failed with a named missing-implementation assertion. Implementation then passed on Godot `4.6.1.stable.official.14d19694e`:

| Command | Passed Scenes | Log Directory |
|---|---:|---|
| `./tools/run_tests.sh --filter hostile_action --timeout 15` | 2 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.6ws0tB` |
| `./tools/run_tests.sh --filter hostile_threat_registry --timeout 15` | 1 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.H9t65m` |
| `./tools/run_tests.sh --filter launch_encounter --timeout 15` | 2 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.HO3TMt` |
| `./tools/run_tests.sh --filter hostile_control_runtime --timeout 15` | 1 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.aleU8Y` |
| `./tools/run_tests.sh --filter launch_enemy --timeout 15` | 2 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.IQA7nG` |

The focused logs contain zero failures and zero known/unknown leak warnings. Manual log scans also check generic engine errors. GDScript line coverage is unavailable in this installed engine; no coverage percentage is claimed.

Tests cover missing/extra fields, Boolean-as-number, fractional frame rejection, JSON integral-number normalization, nonfinite values, handler parameter closure, warning/active/recovery boundaries, frozen aim, paired geometry generations, repeated overlap, multi-hit replay, cancellation, deep snapshot isolation, corrupted generation/phase/hit claims, quantized geometry reconstruction, five-floor/Boss routing, every authored recipe ID, missing collections/references, illegal affix pairs, wave delay, spawn/death deduplication, dormant roster retention, pending death-zone work, room budgets, and failed spawn handling.

Additional RED cases reproduced a central gap in the sentinel's paired sweep and an offset target-circle disagreement with the real threat registry. The corrected sweep covers the intended front half-plane and preserves the rear safe side; target circles commit their rotated authored offset into the registry's `target_point`. Stop tests verify sequential runtime frames, frozen action phase/hit claims, one semantic effect per active edge, and strict expiry extension.

## Production Integration Contract

- Action coordinator configuration receives `{id, actor_kind, actions}` and identity `{run_id, hostile_source_id, next_generation_floor, runtime_frame}`. Frame observations are `{runtime_frame, source_position, target_position, facing_direction, target_id}`; points contain exactly numeric `x` and `y`.
- `request_action` returns JSON-safe `threat_facts`, a root attack generation, cue ID, and handler ID. Convert each fact with `HostileActionCoordinator.native_threat_fact` before native registry registration.
- `advance_frame` returns `hit_facts`, first-active-frame `effect_requests`, `retired_generations`, and `threat_extensions`. The integration authority must apply each scheduled geometry union once through DamageInfo/HealthComponent, dispatch semantic effects only to implemented handlers, and apply Stop expiry extensions transactionally through `extend_fact_through`.
- Encounter configuration receives a resolved encounter and `{run_id, room_id, runtime_frame, encounter_generation}`. `advance_frame(frame, {})` returns `wave_started`, `spawn_warnings`, `spawn_requests`, and `encounter_completed`.
- Bind actual actors through `register_spawned(spawn_id, source_id)`. Domain life transitions call `set_life_state`. Final authenticated HealthComponent death receipts call `notify_entity_defeated`; dormant/recovering actors cannot submit a normal death receipt. An authenticated sigil finalization first installs the `FINAL` life state.
- Payload creation/retirement reserves/releases `pending_work`. The bridge owns atomic frame preparation, live effect commit, compensation, and publication; these pure objects do not independently run physics or publish EventBus facts.
- Native actor frame APIs are `prepare_launch_frame(frame, observations) -> {ok, ticket, batch}`, `can_commit_launch_frame(ticket) -> bool`, `commit_launch_frame(ticket) -> bool`, `rollback_launch_frame(ticket) -> bool`, and `publish_launch_frame(ticket) -> bool`. Preparation predicts an isolated domain/status/transform candidate. Commit installs that candidate. It does not apply registered geometry or target damage; the shared effect authority owns those effects.
- `launch_transaction_snapshot`, `can_restore_launch_transaction_snapshot`, `restore_launch_transaction_snapshot`, and `discard_launch_transaction_snapshot` own native frame-start actor/Health compensation. They are distinct from the prepared actor frame ticket, which only restores domain/status/transform. The bridge must not duplicate the same Health frozen-ledger ownership in another participant.

## Remaining Scope

This evidence does not certify twenty-two implemented species, complete native actor/effect integration, the forty-eight Boss moves, complete raster/audio assets, full affix behavior, a production frame bridge, or production routing. The catalog test registry is a unit fixture for canonical identity/reference/selection behavior. The Sentinel runtime tests currently use an explicit normalized action projection, not authoritative EnemyDefinition content. Neither fixture replaces ContentRegistry or counts as a completed Launch content pool.

No new hostile content has entered the active Base Pack. Existing Main, RunRuntimeHost, RunRuntimeFacade, ContentRegistry, EncounterCatalog, and EncounterRunner are unchanged by this foundation. SaveEnvelope and Replay versions remain unchanged. Schema files, authoritative hostile JSON, full native effects/actors, complete time-source integration, Save/Replay seals, visual QA, and the production/synthetic hostile matrices remain required by the P15 plan.

Before the shared frame bridge can certify atomicity, Health's three typed combat EventBus observations need a validated publication adapter. Its existing frame transaction buffers `damaged`, `healed`, and `died`, but currently emits `damage_about_to_apply`, `hit_confirmed`, and `damage_applied` synchronously. Player's `hit_confirmed` observer also records mastery and Replay facts from live settlement state. Deferring that observer without preserving per-hit settlement semantics would change same-frame multi-hit facts. This integration gap remains explicitly open in the partial milestone.

The full P15 milestone remains active. Authentic external playtests remain `0 / 20`, and formal M1 status remains `M1 Candidate - External Validation Pending`.
