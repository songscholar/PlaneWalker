# Plane Walker P11 Five Complete Weapons Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Consolidated P11A–P11H local certification evidence below the approved five-weapon design
- Applies To: Five coordinator-owned weapon runtimes, capability-based modifiers, generic weapon HUD, Launch Loadout UI, deterministic replay, external-fact validation, accessibility, the 30-loadout matrix, synthetic simulation reporting, and repository certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-30
- Evidence Status: Verified Locally
- Implementation Certification Commit: `01c3712`
- Certified Repository State: `01c3712` plus this documentation-certification commit

## Completion decision

P11A–P11H are locally complete. Sword, Bow, Gun, Staff, and Gauntlets run through one coordinator-owned action authority; expose weapon-specific resources and rhythm through one validated `weapon_state` UI union; publish typed facts and feedback; interact with Stop, Rewind, Rift, and Accelerate; convert unsupported Chrono Warden control into deterministic Boss-safe outcomes; and preserve snapshot, reset, replay, and stale-generation boundaries. The Launch selection flow supports keyboard, mouse, and controller operation. Hold/toggle equivalence is certified for the applicable ranged-charge accessibility path rather than claimed as a distinct mode for every weapon.

The player-facing path is included. The Start menu exposes a formal Launch Loadout panel that can select all five weapons and all six legal time-ability pairs, validates the requested run before closing, restores usable focus on rejection, and enters the production runtime on success. The Launch panel is covered at 640×360, 1280×720, 1920×1080, and 3440×1440. The generic combat HUD is covered at 640×360, 1280×720, 1920×1080, and 2560×1080. Real keyboard and controller events are exercised by integration tests.

This decision does not promote any Launch weapon to M1 or Current. Formal product status remains `M1 Candidate — External Validation Pending`, authentic external human playtests remain `0 / 20`, and the post-M1 evidence-driven promotion decision remains unstarted.

## Cross-weapon UI, modifiers, and feedback

- `RunViewState` validates one exact five-weapon union and rejects unknown weapons, phases, meters, status combinations, secondary states, non-finite values, invalid bounds, and legacy weapon-state placement.
- `RunViewStateProjector` projects Sword rhythm, Bow charge, Gun ammo/reload/Time Load, Staff Mana/element sequence, and Gauntlets Combo/counter state without a Sword fallback.
- `ItemEffect` resolves declarative effect definitions into validated weapon capabilities. Unsupported capability mappings fail closed before runtime mutation.
- `CombatFeedback`, `PixelProxyActor`, and the synthesized audio path route weapon-specific animation, VFX, audio, hit-pause, camera, and accessibility budgets from committed cues. `sword_swing` remains a Sword-specific cue only; other weapons do not fall back to it.
- The Launch panel owns localized labels, modal input blocking, rejection feedback, focus restoration, controller traversal, and safe-area layout. Main supplies the run seed and accessibility snapshot before the authoritative runtime host accepts the run.

Primary player-facing files include:

```text
scenes/ui/launch_loadout_panel.tscn
scripts/ui/launch_loadout_panel.gd
scenes/main.tscn
scripts/main.gd
scripts/application/run_view_state_projector.gd
scripts/ui/contracts/run_view_state.gd
scripts/ui/views/combat_hud_view.gd
scripts/presentation/pixel_proxy_actor.gd
autoload/combat_feedback.gd
```

## Deterministic replay and external facts

`ReplayRecorder` and `ReplayPlayer` preserve profile identity, profile version, generation, action token, frame, event-prefix count, and state digest. Restore is transactional across the weapon coordinator, Player-owned state, TimeManager state, external resource accounts, owned payloads, and the captured event prefix.

Replay covers all five weapons, committed semantic intents, resource/rhythm state, payload ownership, and externally observed combat facts. Recording and playback validate these fact families before mutation:

```text
combat_damage
weapon_hit_claim
weapon_payload_result
weapon_resource_reward
time_interaction_claim
time_stop_extension
```

Malformed, no-op, stale-generation, wrong-token, wrong-frame, mismatched-prefix, forged-state, and invalid transition facts fail atomically. Rejection does not consume capture sequence, refresh the authenticated baseline, mutate the live snapshot, append an event, or partially apply a TimeManager transition. The high-HP damage comparison uses a fixed absolute tolerance so small real damage values are not erased by relative-error scaling.

Focused replay evidence:

- Replay directory: `5 / 5` PASS, zero leaks, `planewalker-tests.nJef75`.
- External Fact Replay: PASS, zero leaks, `planewalker-tests.xXPIoJ`.
- Gauntlets External Fact Variants: PASS, zero leaks, `planewalker-tests.N8ZOvg`.
- Gauntlets Runtime: PASS.

Relevant coverage lives under `tests/replay/`, including runtime replay, observable restore atomicity, shared external facts, Staff variants, and Gauntlets variants.

## Thirty-loadout runtime matrix

The runtime smoke matrix covers the exact Cartesian product:

```text
5 weapons × 6 unordered legal time pairs = 30 loadouts
```

Each case starts a real Player run with a stable seed, activates representative weapon and equipped time actions, validates the generic HUD and presentation snapshot, records runtime/replay state, resets the run, checks the clean terminal state, and repeats. The repeated execution must produce identical pre-reset and post-reset SHA-256 digests. The matrix also verifies that owned projectiles, zones, resource accounts, time scenes, external fact deltas, and transient callbacks do not leak across reset.

The authoritative scene is:

```text
tests/smoke/weapon_time_loadout_matrix_smoke_test.tscn
```

## Synthetic simulation evidence

`tools/run_weapon_simulation_matrix.py` generates a strict report for the same 30 loadouts and the exact canonical seed set `20260901` through `20260930`. Each loadout has 30 samples, for 900 total synthetic deterministic samples.

The report records:

- DPS;
- risk uptime;
- starvation rate;
- burst damage;
- area coverage;
- status uptime;
- Gun perfect-reload value;
- Staff combination frequency;
- Gauntlets Combo retention.

The contract rejects noncanonical seed counts, missing or unknown fields, non-finite metrics, recomputation drift, digest tampering, and any attempt to label the report as human evidence. Simulation report contracts pass `8 / 8`.

Two independent outputs are byte-identical:

```text
/tmp/planewalker-p11-sim-a.json
/tmp/planewalker-p11-sim-b.json
```

Internal report `content_digest`:

```text
5888bdc254eed6a374ed02dfd7fb7f72e606b29fb98cf8d8159d3479035e87c8
```

SHA-256 of each complete output file:

```text
6e34e2ba697f966766e39f8f004854d661d0c232bf5d10228f90de85f43463aa
```

These values are synthetic deterministic engineering evidence only. They do not represent feel, comprehension, accessibility acceptance, retention, or balance observations from a human player.

## Complete repository gate

The final local `./tools/validate_project.sh` run passed:

- documentation governance: `30 / 30`;
- localization: `8 / 8`;
- playtest contracts: `13 / 13`;
- M1 release contracts: `27 / 27`;
- GDScript coverage contracts: `5 / 5`;
- export contracts: `37 / 37` in contract mode;
- Godot scene suite: `113 / 113`;
- project validation: `PASS`.

Retained validation log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.TFKXr1
```

The only registered suite warning is the known `tests/reward_system_smoke.tscn` ObjectDB leak. Final scans found no unexpected parser error, runtime error, RID leak, orphan-node warning, or unregistered ObjectDB warning. `git diff --check` passes.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- No synthetic simulation, deterministic matrix, automated browser/UI test, or agent review is represented as human experience evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.
- Export contracts verify repository policy and fail-closed execution behavior only. Installed Windows/Linux/macOS templates, distributable package creation, packaged startup, signing, platform credentials, remote push, store configuration, and public publication remain unverified external boundaries.
- P11G/P11H implementation is certified at `01c3712`. This record does not invent the hash of its own later documentation-certification commit.

## Next local program

The consolidated P11 gate closes the five-weapon runtime program. The next repository-local Full Product work is no longer P11G/P11H; it advances the remaining staged content and product systems, including five floors and five Bosses, eight archetypes, the complete content pool, Hub and meta progression, full narrative and endings, player-facing replay productization, rankings, Mod management, and DLC/content-pack experiences. Each future stage must retain the same rule: repository automation may prove implementation and determinism, but cannot replace required human, platform, credential, commercial, or publication evidence.
