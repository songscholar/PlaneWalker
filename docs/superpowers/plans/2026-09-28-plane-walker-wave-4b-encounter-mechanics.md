# Plane Walker Wave 4B Encounter Mechanics Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Verified implementation record
- Applies To: Rewind Echo, Boss telegraphs, elite active mechanic, and authored five-room encounters
- Implementation Status: Code and tests complete; all four lanes are integrated in the M1 candidate
- Owner: Project integration lead
- Depends On: `AGENTS.md`, full-product completion spec, commits `9faa1e2`, `bac5e74`, `f592b0d`
- Supersedes: Generic Wave 4B wording that does not match the owner's explicit scope
- Last Verified: 2026-09-28
- Completion Gate: All four mechanics and their regression tests pass through `./tools/validate_project.sh`
- Completion Evidence: Commits `d17f641`, `651c53b`, `d9aa3f6`, `20bd93f`, and `cd647e2`
- Verified Commits: `d17f641` Rewind Echo, `651c53b` Boss telegraphs, `d9aa3f6` elite active mechanic, `20bd93f` authored encounters, `cd647e2` fail-closed runtime hardening

## Goal

The owner's exact Wave 4B scope is complete and preserved independently from Wave 4C presentation assets:

1. Rewind Echo produces a safe, testable committed rewind path and gameplay afterimage.
2. Every Chrono Warden action has a non-zero, action-specific telegraph and recovery.
3. The M1 elite gains one readable active mechanic rather than only numerical scaling.
4. All five M1 rooms consume one authored encounter definition source.

Wave 4B uses clear proxy shapes and existing audio hooks. Wave 4C replaces or polishes presentation without changing Wave 4B gameplay contracts.

## Shared invariants

- Write failing behavior tests before runtime implementation.
- A committed action resolves at most once.
- Target positions, directions, path samples, and spawn slots are committed at windup/start time and are not silently retargeted at resolution.
- Time Stop delays committed windup/recovery clocks without changing action identity.
- Death, room transition, restart, and rewind cancellation invalidate delayed callbacks and transient proxies.
- Gameplay RNG and presentation RNG remain separate.
- New tests may not introduce ObjectDB/RID leaks.
- Existing rewind, action-state, room lifecycle, localization, save, and HUD tests remain green.

## Lane A — Rewind Echo

**Owned files**

- `scripts/time_system/rewind_recorder.gd`
- `scripts/time_system/time_manager.gd`
- `scripts/time_system/rewind_echo_runtime.gd`
- `scenes/time/rewind_echo_runtime.tscn`
- `scripts/items/item_effect.gd`
- `scenes/player/player.tscn`
- `tests/time/rewind_echo_test.gd`
- `tests/time/rewind_echo_test.tscn`
- focused extensions to existing rewind tests

### Contract

- `RewindRecorder` prepares an immutable transaction containing the target snapshot, origin, destination, and copied path samples.
- `TimeManager` emits a typed committed-rewind signal only after restoration, cost, and cooldown succeed.
- Without the Rewind Echo build effect, normal rewind creates no damaging afterimage.
- Rewind Echo lasts 2 seconds and pulses every 0.5 seconds for `ATK × 0.25` time damage near the committed path.
- The path blessing may add one `ATK × 0.50` path hit per enemy per rewind.
- Failed rewind, empty history, death, room exit, or restart creates no echo and no delayed damage.

### TDD gate

The focused test must prove no-build behavior, failed transaction behavior, one echo per successful commit, deep-copied path samples, pulse timing/damage/type, per-pulse deduplication, blessing deduplication, cleanup, and all existing energy/HP/cooldown/action-cancel invariants.

## Lane B — Boss action telegraphs

**Owned files**

- `scripts/enemies/boss_chrono_warden.gd`
- `scenes/enemies/boss_chrono_warden.tscn`
- `scripts/fx/combat_telegraph_2d.gd`
- `scenes/fx/combat_telegraph_2d.tscn`
- `tests/combat/boss_action_state_test.gd`
- `tests/combat/boss_telegraph_test.gd`
- corresponding `.tscn` files

### Contract

Use one authoritative action-definition table for `MELEE`, `SLAM`, `RADIAL`, `AIMED`, `SUMMON`, and `TIME_CRACK`. Every action has positive windup and recovery, a stable action ID, and a distinct proxy shape: cone, circle, ring, line, summon slots, or target circle.

- No damage, projectile, summon, or crack may resolve before windup ends.
- Aim direction, target point, and summon slots are captured at action start.
- Resolution occurs once, then recovery blocks the next action.
- Time Stop extends the current committed phase and does not create or replace an action.

### TDD gate

Tests iterate every action and assert positive timings, zero early effects, one boundary resolution, correct recovery, telegraph identity/shape, captured targeting, mutual exclusion, and Time Stop behavior in idle/windup/recovery.

## Lane C — Elite active mechanic

**Starts after Lane B's shared telegraph primitive is stable.**

**Owned files**

- `scripts/enemies/enemy_base.gd`
- `scripts/enemies/enemy_tank.gd`
- `scenes/enemies/enemy_tank.tscn`
- `tests/combat/elite_active_mechanic_test.gd`
- `tests/combat/elite_active_mechanic_test.tscn`
- focused enemy timing regressions

### Contract

The M1 elite Tank gains `OVERLOAD_PULSE`:

- five-to-seven-second deterministic cooldown;
- 0.9-second circular telegraph;
- one committed damage resolution followed by visible recovery;
- shared action clock with its primary attack, preventing double hits;
- Time Stop freezes windup/recovery;
- normal Tank never triggers the elite action;
- death and room exit cancel the telegraph and callback.

`EnemyBase` remains the only owner of the action phase clock. Subclasses supply definitions and resolution behavior rather than creating parallel timers.

## Lane D — Five-room authored encounters

**Integration-owner files**

- `data/encounters/m1_encounters.json`
- `scripts/dungeon/m1_room_plan.gd`
- `scripts/dungeon/run_director.gd`
- `scripts/dungeon/encounter_catalog.gd`
- `scripts/dungeon/encounter_runner.gd`
- `scripts/dungeon/room_controller.gd`
- `scripts/application/run_runtime_facade.gd`
- `scripts/application/legacy_run_adapter.gd`
- `scenes/rooms/combat_room_01.tscn`
- encounter contract/unit tests and M1 smoke extensions

### Contract

- Exactly five M1 room definitions exist and every room references one unique encounter ID.
- Rooms 1–3 are authored normal encounters, room 4 contains exactly one elite with `OVERLOAD_PULSE`, and room 5 contains the Chrono Warden.
- Waves define stable enemy IDs, spawn-slot IDs, delays, elite mechanism IDs, and target-duration budgets.
- `EncounterRunner` exclusively owns wave progression and alive-count completion, including summons.
- `RoomController`, `RunRuntimeFacade`, and tests consume the same plan/catalog; no parallel fixed-sequence derivation remains.
- Same version and seed produce identical encounter and slot choices.

### TDD gate

Contract tests reject duplicate/missing encounter IDs and invalid enemy/slot/mechanic references. Unit tests prove wave completion and alive counting. M1 smoke asserts exact room encounter IDs, waves, enemy identities, the active elite, and Boss terminal flow.

## Integration order

1. Complete Lane A and Lane B in parallel.
2. Merge and verify Lane B's telegraph primitive.
3. Implement Lane C on the shared primitive.
4. Implement Lane D as the single integration-owner lane.
5. Run focused tests after each lane, then `./tools/validate_project.sh`.
6. Scan all logs; only the already recorded legacy `reward_system_smoke` warning may remain.
7. Create focused reversible commits per lane and one Wave 4B evidence/status commit.

## Verification commands

```bash
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter boss
./tools/run_tests.sh --filter enemy_attack
./tools/run_tests.sh --filter time_stop
./tools/run_tests.sh --filter dungeon
./tools/run_tests.sh --filter m1_runtime
VALIDATION_LOG_DIR=/tmp/planewalker-wave4b-validation ./tools/validate_project.sh
git diff --check
git status --short
```

## Completion outcome

Wave 4B code and tests are complete. Rewind Echo, the six Chrono Warden action telegraphs, Elite Tank `OVERLOAD_PULSE`, and the five authored M1 encounter definitions are integrated into exact candidate commit `79a20fd183fb57b8bdf62019ab80ff3f6e430635`. The repository release Gate passes, and the two authoritative 30-seed candidate runs match digest `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`.

This plan is now historical. Its mechanics, single-clock rules, committed targeting, authored encounter authority, fail-closed behavior, and regression tests remain binding contracts for later development.
