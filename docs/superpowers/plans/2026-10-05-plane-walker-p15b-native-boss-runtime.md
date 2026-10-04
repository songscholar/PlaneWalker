# P15B Native Boss Runtime Implementation Plan

- Status: Active / Current
- Document Role: Current focused native Boss runtime implementation plan
- Authority Level: Execution below approved P15 fixed-frame Boss specification
- Applies To: Five Boss domain runtimes, native scenes and Player frame transaction adapters
- Owner: Project native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Domain and native actor foundation verified locally; production mechanisms and effects remain active
- Exit Gate: All five Bosses preserve authored action, phase, control and transaction contracts with actual native actors

> **For agentic workers:** Execute the existing P15 specification with native scene RED/GREEN gates and independent review. Standing project authorization permits implementation without another approval pause.

**Goal:** Give all five authored Boss definitions a deterministic runtime and real native adapter compatible with the existing HostileFrameBridge.

**Architecture:** LaunchBossRuntime owns fixed-frame domain state and uses the proven HostileActionCoordinator and HostileControlRuntime. LaunchBossActor extends LaunchHostileActor through a runtime factory, preserving existing Player frame tickets, Health buffering, native movement, rollback and effect publication. Production encounter routing remains the separate runner lane.

**Tech Stack:** Godot 4.6.1, GDScript, authored BossDefinition, SeedService, actual Health/Hurtbox scenes, original production actor PNG atlases.

## Global Constraints

- Preserve M1 Warden and existing Launch enemy behavior.
- Use exact authored five-Boss IDs, 48 primary actions, four time responses, HP, phases and enrage thresholds.
- Advance gameplay only through sequential accepted 60 Hz frames; rendering and native physics callbacks do not advance domain state.
- Phase damage settlement cancels pending primary geometry, retains monotonic phase and creates a 60-frame nonattacking cue.
- Boss Stop converts each new source into 30-66 frames of warning/recovery delay and 45 frames of exposure. Rift movement multiplier is at least 0.70.
- Freeze native Boss/Health identity and all transaction state. Failed frames restore clocks, damage claims, exposure and action geometry.
- Shared LaunchHostileActor factory is coordinated with the runner lane; Profile and RunRuntimeHost remain runtime-lane ownership.
- Do not activate unsupported arena, summon, heal, zone or construct effects. Report each unclosed production effect gate explicitly.

### Task 1: Closed domain runtime and deterministic decision state

Files: create `scripts/enemies/launch/launch_boss_runtime.gd`, `tests/unit/enemies/launch_boss_runtime_test.gd/.tscn`; modify `scripts/enemies/launch/boss_definition.gd` and `tests/unit/enemies/boss_definition_test.gd` to preserve `collision_radius_px` in the runtime projection.

Interfaces: `configure(definition, identity)`, `request_action(action_id, context)`, `motion_for_frame(frame, observations)`, `advance_frame(frame, observations, select_action = true, external_action_paused = false)`, `snapshot()`, `can_restore_snapshot(value)`, `restore_snapshot(value)`, `cancel(reason)`, `cancel_action(reason)`, `add_control_source`, `clear_control_source`, `control_modifiers`, `accept_damage_fact`, `species_damage_taken_multiplier` and `charge_contact_fact` match the existing native actor dependency.

- [x] Add missing-runtime RED with dynamic `load` and all five real parsed definitions.
- [x] Preserve the thirteenth collision field and reject unknown fields, foreign action IDs, malformed identity and forged snapshots.
- [x] Implement authored phase availability, weighted deterministic decisions, maximum consecutive action counts, exact HP thresholds, 60-frame phase cue and accepted-frame enrage.
- [x] Convert Stop/Rift sources with duplicate claims and bounded clocks; validate all nested action/control/damage state on restore.
- [x] Verify restored next-frame batches match a fresh deterministic twin and fail-closed mutations leave live state unchanged.

Representative native fixture:

```gdscript
var parser := BossDefinition.new()
suite.assert_true(parser.configure(P15HostileFixtures.boss(id)).ok, "authored Boss parses")
var runtime = implementation.new()
suite.assert_true(runtime.configure(parser.runtime_projection(), identity).ok, "real Boss binds")
var checkpoint: Dictionary = runtime.snapshot()
var first: Dictionary = runtime.advance_frame(1, P15ActionFixtures.context(1))
suite.assert_true(runtime.restore_snapshot(checkpoint), "exact domain checkpoint restores")
suite.assert_equal(runtime.advance_frame(1, P15ActionFixtures.context(1)), first, "restored batch is deterministic")
```

Run: `./tools/run_tests.sh --filter launch_boss_runtime --timeout 60` and `./tools/run_tests.sh --filter boss_definition --timeout 30`. RED must name missing runtime/physical collision projection; GREEN must have no unexpected engine errors or leaks.

### Task 2: Five actual native actors and atomic frame boundary

Files: create `scripts/enemies/launch/launch_boss_actor.gd`, five `data/content_packs/base/assets/bosses/launch/boss_<id>.tscn`, `tests/integration/combat/launch_boss_actor_test.gd/.tscn`; modify only the coordinated runtime factory in `scripts/enemies/launch/launch_hostile_actor.gd`.

Interfaces: preserve `configure_launch_definition(definition, context)`, `configure_launch_room_motion(room, template)`, all `launch_transaction_snapshot`/restore and prepare/commit/rollback/publish methods. Add the approved Boss UI, weapon conversion and strict Character exposure endpoints before production activation.

- [x] Add missing-scenes RED for five canonical scene resources.
- [x] Replace three EnemyRuntime construction sites with an overridable `_create_launch_runtime` factory, retaining EnemyRuntime by default.
- [x] Build real CharacterBody2D, CircleShape body/Hurtbox, actual HealthComponent and manifested raster Sprite2D scenes for every Boss.
- [x] Verify `_physics_process` cannot advance gameplay, actual prepare/commit/rollback preserves complete checkpoints and final death emits one encounter receipt.
- [x] Verify real Player weapon/time/Character endpoints and HostileFrameBridge acceptance/refusal through actual actor scenes.
- [x] Independently review the shared factory and Boss adapter, then commit exact tested paths.

The transaction test uses the actual actor contract:

```gdscript
var before: Dictionary = actor.launch_runtime_snapshot()
var prepared: Dictionary = actor.prepare_launch_frame(1, observations)
suite.assert_true(prepared.ok and actor.launch_runtime_snapshot() == before, "prepare isolates live Boss")
suite.assert_true(actor.commit_launch_frame(prepared.ticket), "Boss commits staged frame")
suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "Boss compensates rejected frame")
suite.assert_equal(actor.launch_runtime_snapshot(), before, "complete native Boss state restores")
```

Run: `./tools/run_tests.sh --filter launch_boss_actor --timeout 60`, existing `launch_enemy_actor`, `hostile_frame_bridge`, Boss exposure and weapon conversion regressions. Native raster screenshots and pixel checks accompany the actor gate; no script errors or leaks are acceptable.

### Task 3: Production integration and retained evidence

- [ ] Hand stable native actor API and five scene paths to the runner lane.
- [ ] Close every declared Boss effect handler with real transactional payloads/constructs before enabling each production encounter.
- [ ] Certify authored phase/arena/time-response behavior, all 750 loadout/Boss combinations, hostile Save/Replay and safe-route geometry under the existing P15 plan.
- [ ] Record exact tests, native artifacts, remaining gates and reversible choices in a Current evidence document; root adds index entries.
- [ ] Pass documentation governance, dependency audit, affected regressions and `git diff --check` before precise commits.

Foundational runtime or scene GREEN is not complete five-Boss product certification. Unsupported handlers and unverified arena policies remain explicit production blockers until Task 3 closes them.

Foundation evidence: `docs/current/2026-10-05-p15b-native-boss-foundation-evidence.md`. The shared runtime/status factories and authenticated native death guard were retained in the coordinated P15N commit; production UI ViewState, full phase-specific art tracks, arena constructs, time responses and all specialized mechanics remain part of Task 3.
