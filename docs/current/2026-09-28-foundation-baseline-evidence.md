# Plane Walker Foundation Baseline Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Execution evidence
- Applies To: P0 localization/data baseline and P1 reproducible validation foundation
- Implementation Status: Complete
- Owner: Project integration lead
- Depends On: `AGENTS.md`, full-product completion spec
- Verified Commits: `9faa1e2`, `bac5e74`, `d92b1ed`
- Last Verified: 2026-10-05
- Rollback Points: each verified commit is independently reversible

## Outcome

The previously uncommitted localization, content-pool, legacy UI, main-flow, smoke-test, and Godot 4.6 changes were inspected, retained, validated, and committed without discarding existing work.

The repository now has one tracked localization source, one project validation entrypoint, and a clean-clone bootstrap path that does not depend on previously generated `.translation` files or local `.godot` cache state.

## Checkpoints

| Commit | Result |
|---|---|
| `9faa1e2` | Tracks `translations.csv`, localizes runtime/content strings, adds static and derived localization contracts, ignores generated translation binaries, and makes smoke-test persistence use an isolated temporary file |
| `bac5e74` | Adds the serial Godot scene runner, project validation entrypoint, CI contract tests, and read-only GitHub validation workflow |
| `d92b1ed` | Adds bootstrap import plus strict clean second import, exact generated-translation classification, and precise environment-error handling |

Documentation and continuous-product scope are recorded separately in `f592b0d`; Wave 4B execution planning is recorded in `248ac0f`.

## Localization contract evidence

Command:

```bash
python3 -m unittest tests.contract.localization.test_validate_localization
python3 tools/validate_localization.py
```

Result:

- 6 contract tests passed.
- Catalog keys are unique.
- English and Simplified Chinese values are non-empty.
- Percent/brace placeholder type and order are compatible.
- Static `tr("KEY")` references resolve.
- Derived archetype, risk, room-type, and terminal-result domains resolve.
- JSON content localization references resolve.
- `translations.csv` is tracked; `.translation` and `.import` derivatives are ignored.

## Main-worktree validation

Command:

```bash
./tools/validate_project.sh
```

Result:

- Shell/CI contract passed.
- Bootstrap import passed.
- Strict clean second import passed.
- 28 discovered Godot scene tests passed.
- 0 failed scenes.
- 1 classified legacy warning remains: `tests/reward_system_smoke.tscn` reports an ObjectDB leak at exit.
- Code coverage was not collected and was not inferred from scene counts.

Evidence log directory:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.06h9gk
```

## Clean-clone certification

A new local clone was created from committed `dev` state without generated translations or project cache, then validated using the repository entrypoint.

Command:

```bash
git clone --no-local . /tmp/planewalker-clean.h3qx2o
cd /tmp/planewalker-clean.h3qx2o
./tools/validate_project.sh
```

Result:

- Bootstrap correctly classified the initially absent English and Chinese generated translation resources and regenerated both from the tracked CSV.
- The second import contained no project script or resource failure.
- Localization contracts passed.
- 28/28 Godot scene tests passed.
- Only the same classified legacy reward-smoke ObjectDB warning remained.

Evidence log directory:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.d3i2QU
```

## Historical limitation

The September baseline retained a reward-smoke ObjectDB warning with an explicit runner exemption. This describes the captured historical runs above. The current runner has no scene exemption: every ObjectDB or RID leak fails validation.

## Current Reward Regression Gate

On 2026-10-05 the actual reward-smoke investigation `planewalker-tests.3MsrvA` reproduced obsolete fixture assertions after production Hub/Profile activation, but no ObjectDB or RID leak. A runtime leak correction is therefore not claimed. The focused fixture update uses the existing explicit M1 compatibility launch path for pause/death UI, verifies a nonprofile death cannot mutate the activated Profile, and places legacy save/reset checks in a separate test directory. Production Profile protection remains unchanged.

The meaningful CI-contract RED requires an injected exit-zero ObjectDB warning in `reward_system_smoke` to fail and reproduced the exemption exactly: `FAIL: the reward smoke scene must reject ObjectDB leaks without a waiver`. The runner now treats that scene identically to all other scenes and removes the obsolete known-warning counter. Actual reward smoke GREEN `planewalker-tests.Q7UeOg`, 1/1, retains reward, curse, weapon, time, feedback, death, pause, settings, progression, choice UI and legacy persistence assertions. Both stdout and engine logs were scanned and contain no errors, warnings or leaks. Godot line coverage remains unsupported.

The stable `bash tools/test_ci_contract.sh` rerun passed against 332 discovered scenes. Its fake-engine contract verifies exit-zero runtime and leak refusal, timeout, bootstrap/clean import ordering and the native dependency invocation boundary; it is not a claim that all 332 native scenes were executed by that contract fixture.

## Gate decision

P0 localization/data baseline and P1 validation foundation are complete. Wave 4A continues with playtest session recording and analysis tooling. Wave 4B implementation is authorized and active; M1 and the full-product program remain downstream quality gates rather than stop points.
