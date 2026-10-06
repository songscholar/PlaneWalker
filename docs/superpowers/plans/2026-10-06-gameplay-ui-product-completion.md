# Gameplay Then UI Product Completion

- Status: Active
- Document Role: Current executable completion plan
- Authority Level: Below approved full-product completion specification
- Applies To: Remaining local gameplay, presentation, verification and packaging work
- Owner: Plane Walker integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-06
- Exit Gate: All repository product gates pass; authentic human playtesting is the remaining experience gate, with account-bound publication and signing listed separately

## Goal And Order

Complete gameplay verification before changing player-facing UI. UI design and
resource research may proceed independently during gameplay tests. Preserve the
existing domain authorities, save compatibility, deterministic seeds and exact
native clocks. Never claim synthetic survival fixtures as unassisted or human
victory. No remote push or public release is part of this work.

## 1. Native Gameplay And Performance

- [x] Inspect active processes, source state, current evidence and UI gaps.
- [x] Complete source-bound hostile catalog/action configuration caches with
  typed mutation, identity, eviction and concurrency regressions.
- [x] Retain ordinary-input actual Main five-floor victory, all five authenticated
  Boss receipts, ending/credits and fresh physical settlement reload. Existing
  development process and changing-source evidence remain diagnostic. Frozen
  `ea35dc7` passes this focused gate; later runtime changes require revalidation.
- [ ] Freeze a committed source inside the workspace and run exactly 750 native
  loadout/Boss cases with all HP phases, paid time receipts, physical checkpoint,
  exact cold continuation and final cleanup.
- [ ] Certify sustained actual combat with concurrent replay recording, late Boss
  phases, rendering, observed saturation and bounded memory. Unique native
  observations must remain physically readable after completion.

Existing executable gates:

```sh
./tools/run_tests.sh --filter p15_five_floor_run --timeout 7200
python3 tools/run_p15_hostile_matrix.py \
  --output build/p15-native-full.json \
  --logs build/test-evidence/p15-native-full \
  --jobs 5 --timeout 28800
python3 -m unittest tests.contract.performance.test_native_performance_probe
```

The matrix command must execute in the untouched retained source, not the shared
working tree. A partial matrix or a source hash change cannot pass its gate.

## 2. Clean Gameplay Certification

- [ ] Import a fresh retained checkout twice and scan both engine/stdout logs.
- [ ] Pass all Python contracts, content/localization/governance validation,
  native scene tests, deterministic simulations and save/replay migrations.
- [ ] Measure every runtime source through the real statement-line provider;
  retain source manifests, executed line sets and honest uncovered files.
- [ ] Repair demonstrated failures with focused RED/GREEN regressions and retain
  small explicit local commits; rerun only affected checks until a new combined
  certification is warranted.

The existing coverage environment is project-scoped:

```sh
GDSCRIPT_COVERAGE_PYTHON="$PWD/build/toolchain/gdscript-coverage-venv/bin/python" \
  ./tools/validate_project.sh
```

An isolated source uses the absolute provisioned interpreter from the primary
workspace. Instrumented timings do not certify production performance.

## 3. Full UI And Presentation

- [x] Retain a complete UI specification and implementation plan based on actual
  rendered screens and the approved modern pixel ruins direction.
- [ ] After gameplay milestone passage, implement the shared theme, licensed
  typography, original bitmap icons, states and reduced-motion behavior.
- [ ] Finish graphical combat HUD and feedback, dedicated loadout/build/forge/
  collection views, and all dungeon, Hub, narrative and mode screens.
- [ ] Finish replay, ranking, content management, offline platform, onboarding,
  settings, remapping and accessibility presentation.
- [ ] Verify actual keyboard/mouse and controller flows in Chinese and English,
  normal/enlarged text, 640x360, 1280x720, 1920x1080 and ultrawide framing.
- [ ] Inspect representative screenshots for hierarchy, information clarity,
  assets, clipping, contrast, focus and coherent game-specific composition.

Functional success, nonblank pixels and text bounds are necessary but insufficient
for visual completion. Preserve before/after captures and assess the final UI as
a cohesive playable product.

## 4. Final Local Product Gate

- [ ] Repeat combined clean certification after the final presentation commits.
- [ ] Export and retain authenticated Windows, Linux and macOS development
  packages from that exact source; verify available real package runtimes.
- [ ] Complete local/offline optional-service flows and record account-dependent
  external steps separately. Investigate project-scoped runtime fallbacks for
  unavailable platform execution rather than declaring them passed.
- [ ] Prepare the playable candidate, authentic 20-session protocol, import
  templates, observations and honest release report without invented humans.
- [ ] Publish one consolidated non-blocking retention review with commits,
  evidence, artifacts, known external boundaries and rollback points.

## Initial Retention State

Initial HEAD is `c1a24d4`. The two dirty native cache modules and their tests/plans
are inspected existing in-scope work. Preserve their intended behavior while
finishing and certifying them. The documentation index has two intentional cache
plan links. No previous working-tree changes are discarded.

The ongoing five-floor development process is source-changing diagnostic
evidence. The 22,500 seeded domain cases already have independent certification;
the 750-case native matrix and final full-game result remain pending. Human
playtests remain 0/20 until authentic records are supplied.
