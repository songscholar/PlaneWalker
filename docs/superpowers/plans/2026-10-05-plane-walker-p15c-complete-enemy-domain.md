# P15C Complete Enemy Domain Implementation Plan

- Status: In Progress / Current
- Document Role: Current focused enemy domain implementation plan
- Authority Level: Below P15 enemy and Boss specification
- Applies To: Twenty-two enemy projections, deterministic species state and native lethal transitions
- Owner: Project owner
- Depends On: `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Canonical projections, deterministic checkpoints and native lethal tests pass; semantic production slice remains explicitly tracked

> **For agentic workers:** Execute this focused plan task by task with failing native tests and exact file-list commits.

**Goal:** Make all twenty-two canonical enemy/elite projections run deterministic authored actions and species state transitions.

**Architecture:** Keep `HostileActionCoordinator` as the warning/hit-generation writer. `EnemyMechanismHandlers` owns species counters and `LaunchEnemyRuntime` owns frame admission, movement, lifecycle decisions and snapshots. Native semantic effects use a separate transaction authority and are not inferred from domain tests.

**Tech Stack:** Godot 4.6.1, GDScript, actual Base enemy JSON, existing scene test runner.

## Global Constraints

- Canonical Base content is the sole authored action/mechanism source.
- Floor one warning floor is 30 frames; later enemies use 23 frames.
- Stop holds action/transit warning; Hound dormancy advances on unscaled accepted frames.
- Only final death retires a counted actor or emits reward observations.
- Damage claims and once-only revival/overheat counters survive strict checkpoint restore.
- Every transform/effect is prepared before native publication.

## Task 1: Canonical Content Admission

- [x] Add `tests/unit/enemies/complete_enemy_runtime_test.gd` and its scene. Loop actual Base catalog for enemy/elite projections, strict round trips and deterministic sequential frames.
- [x] Run `./tools/run_tests.sh --filter complete_enemy_runtime --timeout 45`; expect rejection of later canonical species.
- [x] Replace duplicate five-species action lists with `EnemyDefinition.ACTION_IDS`; use canonical warning floors and all contract handlers.
- [x] Verify malformed extra mechanisms and mismatched action lists still reject atomically.

## Task 2: Species State And Lifecycle

- [x] Test Guard recovery, once-only Hound dormancy/sigil, Titan thresholds, Chaos committed-action form transitions, Archer kiting and Blink Stop/Rift transit. Caller stagger and native sigil projection remain in the semantic slice.
- [x] Implement closed species fields in `enemy_mechanism_handlers.gd`, frozen runtime lifecycle prepare/commit checks, and deterministic movement in `launch_enemy_runtime.gd`.
- [x] Run complete-enemy, launch-enemy and Ruins mechanism tests; inspect logs for script errors/leaks.
- [x] Write evidence distinguishing domain completion from native semantic effect/lifecycle assembly; commit exact files.

## Task 3: Native Semantic Assembly

- [x] Create a separate semantic authority using existing sealed Actor batches, bounded payload budgets and prepare/commit/rollback/publish API; see the P15D plan.
- [x] Coordinate shared router changes with its owner, including typed heal/restore requests and authenticated lethal Health hooks.
- [ ] Verify actual native Health, collision, summons, zones, constructs, links and portals before counting these as production completion.
