# P16P Native Training Evidence

- Status: Approved / Current
- Document Role: Current focused native training implementation evidence
- Authority Level: Verification evidence below P16P
- Applies To: Native sandbox, issued frame observations and physical Profile rewards
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16p-native-training-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p16p-native-training.md`
- Last Verified: 2026-10-05
- Implementation Status: Native foundation verified; usable arena, UI and Boss conversion are subsequent gates
- Exit Gate: Actual Player/World actions, 150 loadouts, sealed persistence and exact retirement pass

## Implemented Boundary

`NativeTrainingFlow.configure(registry, service)` binds the actual activated
Registry and physical Profile service. `start(request)` creates an independent
Launch Player/World with the requested task, seed, character, weapon and two
distinct time abilities. Training uses no active launch receipt, unlock,
settlement, kill statistic or launch sequence. All 150 authored combinations
configure through the existing native Player pipeline.

The service issues `TrainingRuntime` only for the exact native attempt. It
freezes Player identity, World ownership, task/run ID and the actual loadout
seed. Only successful, monotonically increasing native frames produce FIFO
observations. Movement requires committed input plus actual displacement;
dash, skill and time require accepted arbitration. Primary requires a real
accepted press/release that leaves HOLD. Public frame signals, rejected frames,
dead/paused Players, stale owners and an unreleased HOLD cannot grant progress.

`TutorialRuntime.prepare_observation` advances only the selected authored
training task. `ProfileRuntimeService.observe_training` persists the exact
issued observation and its native checkpoint. Failed physical promotion keeps
the pending observation. Native drift or callback detachment after promotion
returns `NATIVE_PUBLICATION_PENDING` while durable claims remain saved. Saved
signals occur after promotion and refuse reentrant mutation.

Reset drains pending saves before replacing the actual Player, refills native
resources and preserves durable claims. Close calls the existing Player reset
to clear weapon-owned payloads outside its subtree, then retires the subtree.
A native Replay clock rollback permanently retires that adapter even after
the clock catches up.

## Verification

- Missing endpoint RED: `planewalker-tests.Tg4JK1` named the absent native flow.
- Unreleased primary HOLD RED: `planewalker-tests.xFOtgM` exposed real five-weapon premature completion.
- Deterministic identity RED: `planewalker-tests.iklzvI` exposed missing native seed and task/seed rebinding acceptance.
- Final native gate: `planewalker-tests.qW9dFc`, 1/1 passed. This includes all 150 combinations, actual five-weapon press/release, T-01/02/03/04/06, physical retry, selected-task rewards, reset/restart reward-once, World late refusal, native death, publication drift, callback reentry/detachment, actual Gun external projectile cleanup, actual Rift World cleanup and full-player Replay rollback/catch-up retirement.
- The final engine/stdout logs contain only the deliberate `Fixed-frame event buffer settlement rejected runtime frame 1` refusal. No script errors or leak warnings occur.
- Affected earlier tutorial regressions: `planewalker-tests.DQWDEB`, 7/7 passed. Physical Profile regressions: `planewalker-tests.vaB2DP`, 3/3 passed.
- QA independently reviewed native ownership, sealed observations, physical save boundary, selected tasks and reward-once. Its seed/task binding finding is resolved by the final RED/GREEN gate.
- Pinned direct development dependency audit passed with `python3 -m pip_audit -r requirements-dev.txt --no-deps --disable-pip --cache-dir build/p15-pip-audit-cache --timeout 10 --progress-spinner off`: no known vulnerabilities. Transitive dependencies were not audited.
- `git diff --check` passed. Parent owns documentation index and consolidated governance verification.

Exploratory parser-error runs are excluded from verification evidence. Formal
GDScript line coverage is unsupported; no percentage coverage is claimed.

## Reversible Decisions And Limits

T-05 deliberately returns `TRAINING_BOSS_UNAVAILABLE` and grants no claim.
The next slice will use the existing actual Chrono Warden scene and native
time-stop exposure/contact. The current foundation has no usable 640x360 arena
or training selectors and is not a complete player-facing training feature.
Main's Hub route remains parent-owned. No complete-game, controller hardware,
clean-checkout distributable, production five-Boss or Expansion certification
is asserted. Human playtests remain 0/20. No remote publication is performed.
