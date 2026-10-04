# P16R Native Training Arena Evidence

- Status: Approved / Current
- Document Role: Current focused native training arena implementation evidence
- Authority Level: Verification evidence below P16R
- Applies To: Independent arena, native controls, physical training saves and actual Boss conversion
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16r-training-arena-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p16r-training-arena.md`
- Last Verified: 2026-10-05
- Implementation Status: Actual arena, six drills and native presentation verified locally
- Exit Gate: Actual selectors, safe retirement, physical reward-once and bilingual native rendering pass

## Implemented Boundary

`TrainingFlowCoordinator` owns an independent 640x360 raster arena, four real
collision walls, Camera2D, native Player and Health/Hurtbox practice target. Main
uses `configure(registry, service)`, `open(task_id = "")`, `close()`,
`is_training_active()` and `closed`. Four OptionButtons expose six authored
drills, five characters, five weapons and six time pairs. Symbolic practice,
configure, reset and back tools have localized tooltips. Configuration stops
only the owned Player and target clocks; it never pauses the SceneTree.

Selection, reset and back drain issued observations before retirement. Failed
physical promotion keeps the original Player, native objective and selection.
Successful automatic retry clears the actual saved error state. Global pause
refuses retirement. A dead or freed Boss can reset or close only with an empty
observation queue and no pending publication recovery. Invalid bindings with an
unsaved objective remain refused. If requested and previous configurations both
become unavailable after safe retirement, the coordinator closes its camera,
panel and focus scope and emits the normal Hub handoff.

T-05 inherits the actual Chrono Warden scene and action engine. The issued
adapter freezes Boss, Health, parent and stable native identity. A conversion
requires accepted Stop in either time slot, actual TimeManager target contact,
the exact installed source and a committed WINDUP/RECOVERY action with positive
delay and exposure. The adapter records and validates actual before/after
native state; idle contact, foreign sources, wrong abilities, stale participants,
public frame signals and a late rejected native frame produce no objective.
Physical retry and a fresh service reload preserve the one-time fifteen-shard
claim. Training changes no formal launch sequence or run statistics.

Seven deterministic project-authored PNGs have CC0 provenance and SHA-256
records in `data/content_packs/base/assets/training/generated_assets.json`.
`tools/generate_training_assets.py` regenerates the original floor, target,
training Warden and four tool symbols without external dependencies.

## Verification

- Missing arena endpoint RED: `planewalker-tests.Uo4yui`.
- Paused-retirement/task-five RED: `planewalker-tests.sZwHfv`.
- Automatic retry/dead Boss retirement RED: `planewalker-tests.8XA1v0`.
- Unavailable requested and prior Boss restart RED: `planewalker-tests.NW3jo8`.
- Final headless gate: `./tools/run_tests.sh --filter training --timeout 30`, `planewalker-tests.4PzhpZ`, 3/3 passed. It includes Main Hub integration, the P16P 150-loadout/five-weapon foundation and the expanded arena gate.
- Arena assertions cover actual controller direction events, saved counters/claims, physical back/reset/selection failure and retry, automatic status recovery, global pause, real Boss warning/contact, physical reward reload, stale Health/parent, foreign source, late World refusal, wrong ability, second-slot Stop, Boss death/free and failed restart handoff.
- Final native rendering: fresh `PLANEWALKER_TEST_DATA_DIR=/private/tmp/plane-walker-p16r-render.sFtKxG`, `godot --path . --rendering-method gl_compatibility --log-file .../engine.log res://tests/integration/training/training_arena_flow_test.tscn`, exit 0 and `PASS: all assertions succeeded`.
- Eight screenshots in `build/visual-evidence/p16r-training-arena/` cover Chinese/English, text scale 1.0/1.5 and 640x360/1280x720 windows. `actual-boss.png` shows the real Player and Warden together. Native containment/text-width assertions pass, dense arena pixel sampling exceeds twelve colors, and screenshots were inspected for readable assets and control overlap.
- Logs are retained under `build/test-logs/p16r-training-arena/`. The only engine error is deliberate `Fixed-frame event buffer settlement rejected runtime frame 1` from the refusal assertion. No script errors, parse errors or leak warnings occur in final headless or native logs.
- Independent QA reviewed native contact proof, complete saved Boss checkpoint, safe empty-queue retirement, owned configuration clocks and failed restart handoff. Its paused-retirement and empty-arena findings are fixed by the final tests.
- No external dependencies were introduced. The pinned direct development dependency audit recorded by P16P remains applicable.
- Final coordinated Profile/Main regression: `planewalker-tests.EVvXJq`, 3/3 passed; pinned direct dependency audit was repeated with the P16P command and returned no known vulnerabilities. Documentation governance returned zero violations and `git diff --check` passed before precise local staging.

The first graphics run's periodic 8px sampling aligned with floor cells and
asserted before collecting the complete region; the final dense 3px sampling
fixes that false rejection. Exploratory parser runs and the sandboxed macOS
WindowServer failure are excluded from completion evidence. Formal GDScript
line coverage is unsupported; no percentage coverage is claimed.

## Reversible Decisions And Limits

This slice uses the proven Chrono Warden engine for training. Full weapon
damage conversion, complete production five-Boss combat and legacy Boss
rollback certification remain separately declared gates. Main, localized
content hashes and native checkpoint synchronization are coordinated integration
work, with their own evidence. No complete-game, physical-controller hardware,
three-platform distributable or Expansion certification is asserted. Human
playtests remain 0/20. No remote publication occurred.
