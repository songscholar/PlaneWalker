# Plane Walker Wave 4 与 M1 放行实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: use subagent-driven execution, TDD, focused reviews, and the repository validation entrypoint for every lane.

- Status: Approved / Current
- Authority Level: Current milestone execution plan
- Applies To: Wave 4A, Wave 4B, Wave 4C, Wave 4D, formal M1 decision, and the first post-M1 promotion
- Implementation Status: In progress
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Preserves: verified Wave 0/1, Wave 2, Wave 3A, Wave 3B, P0, and P1 contracts
- Last Verified: 2026-09-28
- Exit Gate: repository gates pass and authentic human evidence is either verified or explicitly reported as externally pending

## Goal

Finish the production-grade M1 five-room slice: close Wave 4A data work, complete Wave 4B mechanics, deliver Wave 4C pixel/audio/combat feedback, execute Wave 4D deterministic validation and evidence reporting, tune only from recorded evidence, and record the M1 decision. After a passing M1 decision, promote exactly one of Bow, Time Rift, or Time Accelerate to Current through a recorded ADR.

## Current delivery boundary

This plan is the complete scope of the current delivery. Five characters, five weapons, five floors, five bosses, Hub, meta progression, full narrative, rankings, replay, Mod support, DLC, and other Next/Launch/Expansion work remain preserved future scope. They are not implemented by this plan unless a compatibility interface is required by an M1 change.

## Architecture

Gameplay remains deterministic and data-driven. Domain and application code own state and mechanics; scenes and feedback nodes render committed facts without becoming alternate authorities. Playtest evidence uses a versioned JSONL contract, and synthetic evidence is permanently excluded from the human-session gate. One project validation command owns import, contracts, scene tests, deterministic-seed checks, and report-generation contracts.

## Tech stack

- Godot 4.6.1 / GDScript
- JSON content and JSON Schema-compatible contracts
- Python 3 standard-library analysis tools
- Bash validation orchestration
- GitHub Actions read-only validation

## Global constraints

- Do not fabricate human playtest sessions.
- A missing authentic 20-session cohort produces `M1 Candidate — External Validation Pending`, never a false pass.
- The same build version, content version, commit, and seed must reproduce the same gameplay choices.
- Gameplay RNG and presentation RNG remain separate.
- Every hostile damaging action has a readable non-zero telegraph.
- New scenes may not add ObjectDB or RID leaks.
- Use precise staging; never use `git add .` in the shared dirty worktree.
- Next/Launch/Expansion remains future scope for this delivery.

---

### Task 1: Close Wave 4A playtest evidence contracts

**Files:**
- Create: `data/schemas/playtest_session_v1.schema.json`
- Create: `scripts/telemetry/playtest_session_schema.gd`
- Create: `scripts/telemetry/playtest_serializer.gd`
- Create: `scripts/telemetry/playtest_recorder.gd`
- Create: `tools/playtest/playtest_data.py`
- Create: `tools/playtest/validate_sessions.py`
- Create: `tools/playtest/deidentify_sessions.py`
- Create: `tools/playtest/summarize_sessions.py`
- Create: `tools/playtest/evidence_gate.py`
- Create: `tests/contract/playtest/test_playtest_data.py`
- Create: `tests/unit/telemetry/playtest_recorder_test.gd`
- Create: `tests/unit/telemetry/playtest_recorder_test.tscn`
- Create: `tests/fixtures/playtest/synthetic_sessions.jsonl`
- Modify: `tools/validate_project.sh`

**Interfaces:**
- Produces: `PlaytestRecorder.begin_session(...)`, room/damage/choice/failure record methods, and `finish_session(...)`.
- Produces: `validate_session(session) -> list[Violation]`.
- Produces: `EvidenceGate(minimum_human_sessions=20).evaluate(sessions) -> EvidenceGateResult`.
- Invariant: `evidence.source == "synthetic"` can never count toward the human gate.

- [x] Write schema, recorder, serializer, analyzer, de-identification, fixture, and contract tests.
- [x] Verify the synthetic fixture contributes zero human evidence.
- [ ] Add the Python contract suite to `tools/validate_project.sh`.
- [ ] Run the focused Python and Godot telemetry tests.
- [ ] Commit only the Wave 4A files and update status evidence.

**Verification:**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.playtest.test_playtest_data
./tools/run_tests.sh --filter playtest_recorder
python3 tools/playtest/evidence_gate.py tests/fixtures/playtest/synthetic_sessions.jsonl --minimum-human 20 --json
```

Expected: contracts and scene test pass; the fixture gate exits non-zero with `human_sessions: 0`.

### Task 2: Complete Wave 4B encounter mechanics

**Files:**
- Existing detailed file ownership and contracts: `docs/superpowers/plans/2026-09-28-plane-walker-wave-4b-encounter-mechanics.md`
- Integration source: `data/encounters/m1_encounters.json`
- Integration runtime: `scripts/dungeon/encounter_catalog.gd`, `scripts/dungeon/encounter_runner.gd`
- Integration consumers: `scripts/dungeon/m1_room_plan.gd`, `scripts/dungeon/run_director.gd`, `scripts/dungeon/room_controller.gd`, `scripts/application/run_runtime_facade.gd`
- Tests: `tests/time/rewind_echo_test.tscn`, `tests/combat/boss_telegraph_test.tscn`, `tests/combat/elite_active_mechanic_test.tscn`, encounter contract/unit tests, and `tests/smoke/m1_runtime_smoke_test.tscn`

**Interfaces:**
- Rewind emits one committed immutable path used by the Rewind Echo runtime.
- Boss actions use one action-definition table with positive windup and recovery.
- Elite Tank owns `OVERLOAD_PULSE` through the shared enemy action clock.
- `EncounterRunner` is the single authority for authored wave progression and alive-count completion.

- [x] Implement and commit Rewind Echo.
- [x] Implement and commit all Chrono Warden telegraphs.
- [x] Implement and commit Elite Tank active behavior.
- [ ] Finish the five-room authored encounter integration.
- [ ] Run all focused regressions and the full validation entrypoint.
- [ ] Record completion evidence and rollback commits.

**Verification:**

```bash
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter boss
./tools/run_tests.sh --filter elite_active
./tools/run_tests.sh --filter encounter
./tools/run_tests.sh --filter m1_runtime
```

### Task 3: Deliver Wave 4C pixel presentation and combat feedback

**Files:**
- Create or modify presentation-only files under `scripts/presentation/`, `scripts/fx/`, `scenes/fx/`, `scenes/player/`, `scenes/enemies/`, and `scenes/ui/`.
- Add deterministic/procedural proxy assets under `assets/` only when they are project-owned or license-compatible.
- Add focused presentation contracts under `tests/contract/presentation/` and runtime feedback scenes under `tests/presentation/`.

**Interfaces:**
- Feedback consumes typed gameplay facts and may not mutate combat or run state.
- Pixel Proxy uses the existing 640×360 logical canvas and nearest-neighbor sampling.
- Core animation states cover idle, move, attack windup/active/recovery, dodge, hurt, death, time-stop, rewind, elite windup, and Boss windup/recovery.
- Combat feedback covers hit flash, readable danger shapes, damage text, time-power identity, restrained camera impulse, VFX cleanup, and UI response.
- Audio uses explicit buses and safe generated/offline placeholders so a clean checkout has no missing assets.

- [ ] Add failing presentation/feedback contracts.
- [ ] Implement Pixel Proxy silhouettes and hostile/time-power palette rules.
- [ ] Implement core animation state feedback without changing gameplay timing authority.
- [ ] Implement combat audio hooks and project-owned placeholder assets.
- [ ] Implement hit, danger, time-power, camera, VFX, and UI feedback.
- [ ] Verify cleanup, canvas scaling, input-independent behavior, and no leaks.
- [ ] Commit presentation code, assets, tests, and evidence.

**Verification:**

```bash
./tools/run_tests.sh --filter presentation
./tools/run_tests.sh --filter feedback
./tools/run_tests.sh --filter pixel_canvas
```

### Task 4: Execute Wave 4D deterministic stability and evidence reporting

**Files:**
- Create: deterministic 30-seed runner and report code under `tools/m1/`.
- Create: tests under `tests/contract/m1/` and any required Godot deterministic simulation scenes.
- Create: `docs/current/2026-09-28-m1-playtest-protocol.md`.
- Create: `docs/current/2026-09-28-m1-release-report.md`.
- Modify: `tools/validate_project.sh` and `.github/workflows/validate.yml` only if the new checks are stable in CI.

**Interfaces:**
- The seed runner executes the canonical seeds `0` through `29` against one recorded build/content cohort.
- Each seed records terminal state, room sequence, encounter IDs, failures, duration proxy, and deterministic digest.
- The report consumes validated session JSONL plus the 30-seed result; it does not consume unvalidated free-form notes as release evidence.
- The release state is one of `M1 Go`, `M1 No-Go`, or `M1 Candidate — External Validation Pending`.

- [ ] Write failing tests for exact seed coverage, duplicate/missing seed rejection, deterministic digest comparison, and gate-state calculation.
- [ ] Implement the 30-seed runner and machine-readable result.
- [ ] Implement report generation from deterministic and human-evidence inputs.
- [ ] Add the playtest protocol, observation form, import instructions, privacy rules, and issue-triage rubric.
- [ ] Run the 30-seed suite twice and compare digests.
- [ ] Evaluate the authentic 20-session gate for the exact build cohort.
- [ ] Commit the toolchain, tests, protocol, and candidate report.

**Verification:**

```bash
python3 -m unittest discover -s tests/contract/m1 -p 'test_*.py'
python3 tools/m1/run_seed_matrix.py --seed-start 0 --seed-count 30 --output /tmp/planewalker-m1-seeds.json
python3 tools/m1/run_seed_matrix.py --seed-start 0 --seed-count 30 --output /tmp/planewalker-m1-seeds-repeat.json
python3 tools/m1/compare_seed_reports.py /tmp/planewalker-m1-seeds.json /tmp/planewalker-m1-seeds-repeat.json
```

### Task 5: Tune values only from recorded evidence

**Files:**
- Modify only the authoritative gameplay data or constants identified by the M1 report.
- Create or modify regression tests adjacent to each tuned system.
- Update: `docs/current/2026-09-28-m1-release-report.md`.

**Interfaces:**
- Every value change records the metric that triggered it, old value, new value, expected effect, and regression test.
- Synthetic seed results may justify stability fixes and deterministic budget corrections.
- Feel, comprehension, perceived fairness, and demand claims require authentic human evidence.

- [ ] Capture the pre-tuning metric baseline.
- [ ] Make one bounded tuning batch per dominant failure signature.
- [ ] Re-run focused tests, 30 seeds, and cohort analysis after each batch.
- [ ] Reject changes that improve one metric by violating telegraph, duration, or build-diversity gates.
- [ ] Record retained and reverted tuning decisions.

### Task 6: Produce the formal M1 decision

**Files:**
- Finalize: `docs/current/2026-09-28-m1-release-report.md`
- Update: `docs/README.md`
- Update: completion evidence links and exact commits.

**Decision rules:**
- `M1 Go`: all repository gates pass and at least 20 valid authentic human sessions from the required cohort satisfy the release thresholds.
- `M1 No-Go`: a repository or supplied human-evidence gate fails with an actionable product defect.
- `M1 Candidate — External Validation Pending`: all repository work is complete but the authentic 20-session cohort is absent or incomplete.

- [ ] Record exact build, commit, content version, tests, seed digests, evidence counts, metrics, known limitations, and rollback points.
- [ ] Ensure the report does not claim external evidence that was not supplied.
- [ ] Run `./tools/validate_project.sh` from the integrated worktree.
- [ ] Validate a clean local clone/checkpoint when the worktree is clean.
- [ ] Commit the evidence and status update.

### Task 7: Promote one post-M1 option to Current

**Files:**
- Create: `docs/adr/2026-09-28-first-post-m1-promotion.md` after M1 evidence is available.
- Modify the chosen option's availability/content flags and tests only after the ADR decision.

**Scoring inputs:**
- Build diversity and route concentration.
- Ranged-pressure failure rate.
- Time Stop versus Rewind comprehension and usage.
- Input-load and completion-time pressure.
- Explicit player demand from authentic playtests.

- [ ] Score Bow, Time Rift, and Time Accelerate from the recorded cohort.
- [ ] Select exactly one option and explain why the other two remain future scope.
- [ ] Promote the selected option through data availability and regression tests.
- [ ] Re-run the integrated validation entrypoint.

If the human cohort is still pending, this task remains evidence-blocked; no option is falsely promoted as a data-driven M1 outcome.

## Final integrated verification

```bash
git diff --check
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.playtest.test_playtest_data
./tools/validate_project.sh
git status --short
```

The current delivery is complete when Tasks 1–6 are implemented and verified, the M1 state is honestly recorded, and Task 7 is completed only if the required M1 evidence exists. Future Next/Launch/Expansion content remains documented and intentionally outside this delivery.
