# Native Boss Arena Constructs Implementation Plan

- Status: Active
- Document Role: Current implementation plan
- Authority Level: Execution details below the approved P15 specification
- Applies To: Five Boss arena constructs, native collision, accepted damage, Save and Replay
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Every authored arena construct executes native interaction, accepted-frame rollback and current/historical cold recovery; safe-route, loadout and visual certification pass with no script errors or leaks.

**Goal:** Execute the declared Boss arena interactions as native gameplay with complete accepted-frame compensation and cold reconstruction.

**Architecture:** Pure arena state owns construct identities, geometry, hit points and once-only facts. Native bodies project that state and carry accepted weapon collisions to the owning Boss runtime. Arena targets never become counted enemy roster bodies or independent room rewards. Native checkpoints carry the explicit arena state; exact historical runtime versions normalize through a pure compatibility entry point before full reconstructed-state comparison.

**Tech Stack:** Godot 4.6.1, GDScript, deterministic accepted 60 Hz frames, raster production atlas tooling.

## Constraints

- The P15 specification is already approved under continuing project authorization.
- Cover, walls and core hit points are domain state, not hidden metadata or strings in another claim ledger.
- Saved identities use run/source/construct keys, never Node instance IDs.
- Native targets remain outside counted `enemies` and `bosses` groups.
- All geometry preserves the authored 48 px central/perimeter escape requirements.
- New runtime snapshots require exact fields; only exact historical snapshots receive the declared default migration.
- Base descriptor bindings remain unchanged while the native scene is code-owned. Full actor/art asset declaration is a separate content-pack closure gate.

## Task 1: Ruin Cover

Files: `scripts/enemies/launch/boss_arena_runtime.gd`, `scripts/enemies/launch/launch_boss_construct.gd`, `scripts/enemies/launch/launch_boss_actor.gd`, `scripts/enemies/launch/launch_boss_runtime.gd`, `scripts/dungeon/native_launch_encounter_driver.gd`, `tests/integration/combat/boss_arena_native_test.gd`, production raster generator and evidence.

Interfaces: `BossArenaRuntime.configure(definition: Dictionary, identity: Dictionary) -> Dictionary`; `snapshot() -> Dictionary`; `accept_damage_fact(fact: Dictionary) -> Dictionary`; `advance_frame(frame: int) -> bool`; `can_restore_snapshot(value: Dictionary) -> bool`; `restore_snapshot(value: Dictionary) -> bool`; `LaunchBossActor.native_arena_snapshot() -> Dictionary`; `receive_native_construct_hit(id: String, damage: RefCounted) -> float`.

- [x] Write a native RED proving the current Ruin scene has no four actual destructible covers.
- [x] Add strict initial four HP80/radius14 covers at canonical interior positions, permanent destruction, source/run/frame damage claims and central/perimeter clearance validation.
- [x] Project actual StaticBody2D obstacles and weapon Hurtboxes; execute real Sword/Bow/Gun/Staff/Gauntlets collision routes against their authoritative HP.
- [x] Upgrade only the Ruin Boss runtime from version1 to version2 with `arena_state`. Normalize exact version1 snapshots to the documented initial arena state; reject unknown fields and malformed version2 state.
- [x] Verify accepted hits, duplicate rejection, sibling frame refusal/retry, geometry tampering, cold recovery and charge collision exposure. Commands: `./tools/run_tests.sh --filter boss_arena_native --timeout 120`, `./tools/run_tests.sh --filter native_combat_checkpoint --timeout 120`.
- [x] Retain original raster provenance, native resolution screenshots, focused evidence and precise local commit. Evidence: `docs/current/2026-10-05-p15b-native-ruin-cover-evidence.md`.

## Task 2: Ruin Dynamic Effects

- [x] Add slam aftershock at the authored 60f impact delay containing20f dormant plus40f own warning and12 damage/radius32. Accepted-frame refusal/retry, owner phase/death retirement and actual dormant/warning cold checkpoints are verified in `docs/current/2026-10-05-p15b-native-ruin-aftershock-evidence.md`.
- [x] Retire all surviving declared covers at the actual first enrage impact after its complete75f warning. Preserve prior partial HP and broken covers, whole-frame rollback/retry and fresh current native cold reconstruction.
- [x] Add HP150/TTL600 wall segments with32px passage and40f collapse warning, actual native HP/collision, safe activation, refused-frame retry and current/historical focused cold reconstruction. Evidence: `docs/current/2026-10-05-p15b-native-ruin-wall-evidence.md`.
- [x] Add debris HP20/TTL480/cap4 with safe placement, real room physics, accepted Encounter work and shared construct budget. Focused current/historical payload compatibility and fresh native Actor/effects/Encounter continuation: `docs/current/2026-10-05-p15b-native-ruin-debris-evidence.md`. Whole Host and full loadout certification remain open below.
- [ ] Verify owner/action retirement, cover-blocked beam and charge, combined48px escapes, rollback and cold restore in actual Host combat.

## Task 3: Forest Arena

- [ ] Add sixHP100 roots, permanent broken segments,45f body exposure and deterministic retirement of three surviving roots inP2.
- [ ] Add fourHP30 sacs, warning interruption and three one-use20HP healing flowers through Player Health.
- [ ] Add two16px erosion steps, warned cages, actual drain healing caps and owned saplings; verify accepted HP loss and safe routes.

## Task 4: Time Responses

- [ ] Authenticate Stop/Rewind/Accelerate/Rift ability generations, shared phase cooldown and recovery deferral.
- [ ] Add40damage counter-Stop Watch interruption, echo exposure, six accelerated-hit shattering and delayed Rift instability without removing paid Player sources.
- [ ] Preserve existing80HP self-rewind behavior and real Watch cold migration.

## Task 5: Forge And Void Arenas

- [ ] Add four ForgeHP120 anvils, fixed vents and permanent cooling pools;30f burn cleanup cooldown and prior-form hazard retirement.
- [ ] Add Void cover debris inP2, reachable core damage conversions and fourHP100 P3 cores;100body damage/60f exposure per core,120f full-round exposure,600f regeneration and two-round cap.
- [ ] Add one30%maximumHP Player heal at P3 and authenticated cap4/+5energy pickups, never revive a dead Player.

## Certification

- [ ] Every construct state and native projection matches after rejected and accepted frames.
- [ ] Whole native Host checkpoints recover current and exact historical runtime versions.
- [ ] Five weapons, six time pairs, both difficulties and five characters pass the complete750 loadout/Boss matrix.
- [ ] Native desktop/mobile-equivalent supported resolutions, visual cues, path clearance, logs and package startup pass.
- [ ] Document all retained commits, executable evidence, remaining external publication steps and limits.
