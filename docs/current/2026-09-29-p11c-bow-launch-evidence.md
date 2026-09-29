# Plane Walker P11C Launch Bow L2 Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11C Launch Bow L2 implementation evidence below final P11 certification
- Applies To: `bow_launch_v1`, semantic Bow actions, atomic cooldown and Time Energy transactions, deterministic projectiles and zones, four time interactions, Chrono Warden conversion, cleanup, and Candidate isolation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`, `docs/current/2026-09-29-p11c-bow-candidate-evidence.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Worktree Base HEAD: `81dfe63`
- Candidate Certification HEAD: `0cf27da`
- Launch Certification Commit: `372455d`
- Rollback Point: `81dfe63`

## Completion decision

Launch Bow L2 is `Verified Locally` at commit `372455d`. The data contract, runtime plan layer, coordinator transactions, Player integration, payload execution, time interactions, Chrono Warden conversion, lifecycle cleanup, focused gates, complete scene suite, clean import/bootstrap path, documentation governance, localization, playtest-data, M1, coverage, and export contracts all pass locally. Two independent final reviews report no remaining code or evidence blocker.

The existing Candidate contract is unchanged. `bow_candidate_v1` remains `NEXT` with the certified `9 / 54 / 21` boundaries: 9-frame minimum charge, 54-frame maximum charge, and 21-frame cooldown/recovery. Launch work does not promote Bow to Current, does not change Quick Start or the M1 Sword profile, and does not weaken the Candidate certification in `docs/current/2026-09-29-p11c-bow-candidate-evidence.md`.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic external human playtests remain `0 / 20`. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Launch data contract

`bow_launch_v1` now defines five semantic actions and rejects authoritative numeric drift even when a mutated profile remains schema-valid. The normalized operational projection is frozen by SHA-256 `be695e379ae6ac4c670eacc37436141f935c1333cf1b927db525714c78815bd5`; it covers profile/runtime identity, actions, resources, capabilities, payloads, cues, all four time interactions, and Chrono Warden conversion. Eleven schema-valid drift classes pass rejection coverage.

| Action | Frozen contract |
|---|---|
| Precision Draw | Four tiers at `0–14`, `15–29`, `30–47`, and `48+`; full charge at 48 effective frames; automatic release at 228 raw frames; charge movement `0.40`; full-charge hold movement `0.20` |
| Scatter Shot | `10 / 3 / 18` phase frames, five independent `0.6×` arrows across `±30°`, 120-frame cooldown |
| Focus Step | 96-pixel movement opposite aim, swept collision, no invulnerability |
| Temporal Arrow | `12 / 2 / 16`, 30 Time Energy, 300-frame cooldown, `5.0×` time damage, unlimited pierce, 300-frame trail, 30-frame ticks |
| Starfall Arrow Rain | 60-frame HOLD, `20 / 90 / 25`, 70 Time Energy, 900-frame cooldown, ten waves every 9 frames, three arrows per wave |

The Base Pack manifest records `content/weapon_runtime_profiles.json` with SHA-256 `371c0f88b050fd14aa145f321f6531a9ca963501fd8dd376bbc5f37437f6db30`.

## Runtime authority and atomic transactions

```text
semantic weapon intent
  -> PlayerController aim, target, and immutable time context
  -> WeaponActionCoordinator HOLD / WINDUP / ACTIVE / RECOVERY authority
  -> BowWeaponRuntime validated plan and seeded action packet
  -> BowWeapon payload adapter
  -> PlayerArrow / Starfall zone execution
  -> typed weapon facts, cues, hit conversion, and cleanup
```

- `WeaponActionCoordinator` owns the only action clock, Profile cooldowns, Time Energy reservation/commit, HOLD release, automatic release, cancellation, and buffered action boundary.
- Rejected or failed staging preserves energy, cooldown, token ownership, payload state, fact publication, and Rewind claim availability.
- Primary and Starfall HOLD reserve no payload before a valid release. Restorable HOLD snapshots preserve the original token; unsafe snapshots with live staged payloads fail closed.
- Accelerate charge timing is frozen at press. Stop, Rewind, and Rift availability is refreshed at release so a HOLD cannot use stale time state.
- Launch payload definitions freeze resolved modifier values. Later mutable reward or modifier changes do not alter the committed projectile, trail, or zone.
- Seed channels include the run seed, Launch profile, action ID, payload ID, action token, and outcome index. Repeating the same input reproduces the same Scatter and Starfall descriptors.

## Payload execution

- Precision Draw executes all four charge tiers, including full-charge split physical/time damage and unlimited-pierce behavior.
- Scatter Shot materializes five independently seeded arrows around the original aim direction. Rewind phantoms also center on the original aim instead of inheriting the first `-30°` pellet.
- Focus Step sweeps the reverse-aim path and stops at collision without adding invulnerability.
- Temporal Arrow uses source-aware first-hit control, enemy-identity deduplication, a finite trail lifetime, bounded tick cadence, and cleanup that cannot leave a final slow or damage tick after exhaustion.
- Starfall targets `player.global_position + aim * 512px`, not world origin. Its 30 arrows are released by coordinator ACTIVE frames. The cast applies its declared invulnerability, zone slow, and 30-frame time-erosion cadence, then clears owned transient state on completion or cancellation.
- Rift detonation resolves the live Rift radius, triggers once per eligible enemy/action path, and cannot retrigger indefinitely through unlimited pierce.
- Transient cancellation, Rewind restore, death/reset, and loadout reconfiguration remove owned `player_arrows`, trails, zones, and associated slow/status sources without deleting unrelated nodes.

## Time interactions and Chrono Warden conversion

| Interaction | Implemented behavior |
|---|---|
| Stop | Full-charge hit adds a `2.0×` time explosion and requests at most 60 extension frames once per action token |
| Rewind | One generation-safe two-second claim creates three `0.5×` time-damage phantom arrows at `-15° / 0° / +15°`; the claim is consumed only after successful staging |
| Accelerate | Future charge timing is `×2`; quick-shot recovery is reduced by 6 frames; press-time timing remains stable during HOLD |
| Rift | Full-charge arrows gain unlimited penetration and a `1.5×` time-damage detonation using the live Rift boundary |

Chrono Warden rejects Bow control conversion during `WINDUP` or an active committed attack. During `RECOVERY` or `EXPOSED`, eligible hits convert into bounded recovery extension, exposure extension, and poise damage. Conversion is target-deduplicated. Weapon-sourced exposure and poise persist across action completion and decay or expire through their own timers instead of being cleared unconditionally.

## Validation evidence retained so far

### Focused implementation checkpoints

The retained runtime-plan checkpoint proves `bow_weapon_runtime` only:

```text
bow_weapon_runtime
```

Result: PASS with no leak warning in the reported Godot run.

Runtime checkpoint log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.L1JV5M
```

The post-review execution wave separately passed these focused scenes:

```text
bow_launch_execution
bow_weapon_runtime
bow_boss_conversion
bow_time_interaction_context
player_launch_bow_integration
health_component
```

The execution scene covers Rewind preflight for Temporal Arrow and Starfall, aim-centered Scatter phantoms, frozen resolved damage, live-radius once-per-action Rift detonation, enemy-identity deduplication, source-aware 90-frame first-hit freeze, exhausted-trail cleanup, Starfall invulnerability/slow/30-frame erosion cadence, natural and cancelled cleanup, and Dash overlap. The verbose Player integration run reported no ObjectDB or SceneTreeTimer warning.

Execution-focused result: `6 / 6` scenes passed in one serial command. The log contains only the macOS headless CA-certificate environment diagnostic, with no script error, ObjectDB leak, or SceneTreeTimer warning.

```text
/tmp/planewalker-launch-bow-execution-focused.log
```

Earlier integration checkpoints also passed in separate runs:

```text
player_semantic_weapon_input
player_weapon_coordinator_integration
player_loadout_runtime
rewind_action_cancellation
seed_service
content_schema
```

These results prove the named checkpoint revisions only. They are not substituted for the final post-review rerun.

### Documentation governance

The Launch evidence entry and Current index pass the repository documentation contract:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
```

Result: `30 / 30` documentation tests passed; governance reported `violations=0`, `baselined=0`, `new=0`, and `stale=0`.

### Pre-review unified repository checkpoint

The unified scene suite passed `82 / 82` before the final execution-review repairs. The only reported warning was the registered `reward_system_smoke` ObjectDB warning.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.0HLA0A
```

This run is retained as regression evidence, not final Launch certification.

### Final local certification

The post-review focused gate passed every literal filter listed by the P11 plan:

```text
bow: 6 / 6
ranged_charge_accessibility: 1 / 1
combat_feedback_runtime: 1 / 1
candidate_loadout_panel: 1 / 1
weapon_action_coordinator: 1 / 1
rewind_action_cancellation: 1 / 1
player_loadout_runtime: 1 / 1
health_component: 1 / 1
```

All focused runs reported zero failed scenes and zero leak warnings. The Bow log is:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.danrEl
```

The final complete scene suite passed `82 / 82`, with only the registered `reward_system_smoke` ObjectDB warning:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.kWPYlm
```

The final `./tools/validate_project.sh` run passed the shell/CI contract, documentation governance, localization, playtest-data, M1 release-gate, GDScript coverage contracts, export contracts, bootstrap import, clean second import, and the same `82 / 82` scene suite:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.iQlYtc
```

Final `git diff --check` passed. Formal replay serialization remains Task 9 scope; P11C certifies deterministic snapshot safety and does not claim replay completion.

## Certification and release boundaries

- `bow_candidate_v1` remains `NEXT`; Candidate `9 / 54 / 21` is unchanged.
- Launch Bow is not promoted to Current by this implementation record.
- M1 remains `M1 Candidate — External Validation Pending`; authentic external human playtests remain `0 / 20`.
- GDScript line coverage is unsupported by the current toolchain and is not inferred from scene counts.
- Validation is local only. Windows, Linux, and macOS packaged startup are not certified by this record.
- Export templates, artifact signing, store credentials, remote push, public release, publication, and commercial approvals remain outside this local certification.
- No remote commit, tag, build, announcement, or store artifact is authorized or claimed here.
