# Plane Walker P11F Launch Gauntlets Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11F Launch Gauntlets implementation evidence below final P11 certification
- Applies To: `gauntlets_launch_v1`, five-hit chain, cross-chain Combo, heavy/counter/skill/ultimate actions, four time interactions, Boss poise conversion, real hit/zone execution, Player integration, HUD, Pixel Proxy, combat feedback, snapshots, reset, and stale-callback rejection
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`
- Last Verified: 2026-09-30
- Evidence Status: Verified Locally
- Worktree Base HEAD: `b33f080`
- Implementation Certification Commit: `2cfd31c`
- Rollback Point: `b33f080`

## Completion decision

P11F Launch Gauntlets is `Verified Locally` at implementation commit `2cfd31c`. The authoritative Profile, five-hit chain, independently confirmed Combo counter, exact tier boundaries, charged heavy, Dash counter, Space-Time Shatter, Primordial Collapse, four time interactions, Chrono Warden poise conversion, real hitboxes and zones, source-owned Combo Aura, Player assembly, controller aim, HUD, Pixel Proxy, audio/VFX/camera feedback, snapshot/reset behavior, and bounded stale-callback protection pass the final focused and repository gates.

The final Gauntlets suite passed `6 / 6` with zero leak warnings. The final repository validation passed `103 / 103` Godot scene tests with only the registered `reward_system_smoke` ObjectDB warning. Documentation, localization, playtest-data, M1, coverage-contract, export-contract, bootstrap-import, and clean-import sub-gates all passed. Final implementation and integration reviews reported no P0 or P1 blocker.

Gauntlets remains limited to `LAUNCH` and `EXPANSION`. This implementation does not add a complete five-weapon player-facing loadout menu, promote Gauntlets to Current, or change the frozen M1 candidate.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic external human playtests remain `0 / 20`. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Authoritative data contract

`gauntlets_launch_v1` is the single Launch Gauntlets runtime Profile. The frozen Profile SHA-256 is:

```text
63b6a21a7ea03cd1d63ba93307eac84320a1bf9b3b430d9943cfea0f2b32cdd9
```

The Profile contract rejects drift across identity, availability, actions, capabilities, timing, resource costs, payloads, cues, time interactions, Boss conversion, tags, compatibility, effects, references, and localization keys.

| Action | Frozen behavior |
|---|---|
| Punch chain | Five committed actions with an independently confirmed cross-chain Combo counter |
| Charged heavy | Release from frame 30; heavy impact and owned shockwave |
| Dodge counter | Real Dash-completion window on frames 0–8; closed on frame 9 and immediately after commit |
| Space-Time Shatter | Mixed Physical/Time impact, owned slow zone, immutable high-Combo Rift modifiers |
| Primordial Collapse | 60-frame hold, fist and cone execution, shared target damage claim, source-owned cast invulnerability |

Combo timeout is 120 frames before modifiers. Tier edges are certified at 4/5, 9/10, 14/15, 19/20, and 29/30. Real player damage resets Combo; Dash preserves it. Attack-speed tiers affect only future plans, while damage, critical, Time damage, resource return, Rift ownership, and time-interaction results are frozen at plan/commit boundaries.

## Runtime authority and atomicity

```text
semantic weapon intent
  -> PlayerController aim and Dash completion context
  -> WeaponActionCoordinator single action clock
  -> GauntletsWeaponRuntime validated plan and action ledger
  -> GauntletsWeapon adapter
  -> hitbox / shockwave / zone / Combo Aura execution
  -> typed facts, feedback, snapshots, and cleanup
```

- Player-level action token floors remain strictly monotonic through all loadout replacements, including a temporary loadout with no Coordinator.
- Candidate Gauntlets assembly uses detached configuration and binds the shared adapter only after Profile, modifiers, resources, and Coordinator construction succeed.
- Failed late assembly preserves the prior loadout, Runtime, Coordinator, prepared payloads, and presentation state.
- WINDUP snapshot restore requires the committed definition and the sole active ledger to equal canonical values derived from the active plan and token.
- Adapter begin failure rolls back the previous definition. If both target begin and rollback fail, Runtime and Adapter synchronously enter a READY safe reset.
- READY restore cannot resurrect completed action ledgers or accept delayed callbacks. Non-snapshot tombstones preserve stale-token rejection.
- High Combo and `aura_source_generation` are bidirectionally consistent. Aura clear/rebuild is part of the restore transaction.
- Reset, death, Rewind-safe cancellation, loadout replacement, and action cancellation retire owned hitboxes, zones, Aura sources, invulnerability, callbacks, and feedback claims.

## Combat execution and time interactions

| Interaction | Implemented behavior |
|---|---|
| Stop | Eligible hits extend the owned Stop source up to the Profile cap; stale generations fail closed |
| Rewind | One generation-safe counter opportunity uses the real 120-frame time context and cannot be reclaimed after commit |
| Accelerate | Every third eligible primary hit may create one non-recursive echo; echo hits cannot grant Combo, energy, Stop extension, or another echo |
| Rift | Only the authorized intersecting Rift generation grants the reduced resource cost and `1.5×` zone radius/duration; foreign or mismatched generations cannot grant benefits |

Rift geometry and generation are immutable in the action plan. Clearing live Combo or replacing world Rift state after planning cannot alter the committed zone. Reset payload callbacks cannot recreate a retired Rift zone or emit new feedback.

Chrono Warden never enters unsupported airborne state. Eligible launch effects become deterministic displacement and poise contribution in allowed Boss states, preserve committed active attacks, and are deduplicated by source generation and target identity.

## Player-visible UI and feedback closure

P11F is not a backend-only implementation. The certified player-visible path includes:

- semantic keyboard, mouse, and controller input routed through the shared Coordinator;
- aim priority of right stick, then mouse, then the latest non-zero movement direction;
- identical visible weapon rotation and committed aim context across Sword, Bow, Gun, Staff, and Gauntlets;
- real Gauntlets HUD rendering with localized weapon name, exact Combo value, `15 / 30` meter behavior, Combo-active status, timeout, and Counter Ready state;
- a dedicated Pixel Proxy visual kind instead of Sword fallback;
- alternating left/right fists, punch wind, uppercut/charged/skill/ultimate shapes, Counter speed lines, and a visible two-ring 128-pixel Combo Aura matching the two-tile gameplay boundary;
- distinct synthesized cues for jab, hook, uppercut, charged heavy, counter, skill, and ultimate;
- Profile-driven `animation_id` and `vfx_id` routing, impact-tier hit pause, camera feedback, token deduplication, and typed hit-confirmed facts;
- automated projector, HUD scene, feedback, semantic input, real Area2D hit, real zone, and Aura tests.

This evidence does not claim that every Launch/Expansion feature already has a formal UI. Gun, Staff, and Gauntlets still need a unified player-facing five-weapon selection flow. Replay, Hub, meta progression, maps, shops, events, narrative, rankings, Mod management, cosmetics, challenges, and DLC status UI remain later gates. Their definition of done must include a formal player entry point, state/error feedback, keyboard/controller access, and UI/visual tests.

## Validation evidence

### Focused gates

- Gauntlets suite: `6 / 6` PASS, zero leak warnings at `planewalker-tests.gKEXxs`.
- Combat Feedback: PASS at `planewalker-tests.xIsJOi`.
- Combat HUD V2: PASS at `planewalker-tests.yWrRxi`.
- RunViewState projector: PASS at `planewalker-tests.1nO5Ti`.
- Semantic weapon input: PASS at `planewalker-tests.aOFtno`.
- Player action runtime: PASS at `planewalker-tests.MC8myf`.

These gates cover Profile drift, chain/Combo separation, tier boundaries, time interactions, Boss conversion, real hit and zone execution, Aura visibility and ownership, snapshot rollback, stale callbacks, token monotonicity, Dash counter timing, controller aim, HUD rendering, Pixel Proxy visuals, cue routing, reset, death, and loadout replacement.

### Complete repository gate

The final `./tools/validate_project.sh` run passed:

- shell and CI contract with 103 discovered scenes;
- documentation governance `30 / 30`, `violations=0`;
- localization `8 / 8`;
- playtest data `13 / 13`;
- M1 release gate `27 / 27`;
- GDScript coverage contracts `5 / 5`;
- export contracts `37 / 37` in contract mode;
- bootstrap import and clean second import;
- final Godot scene suite `103 / 103` with only the registered `reward_system_smoke` ObjectDB warning.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.vp6gcQ
```

The import path emitted only approved macOS CA-store/settings diagnostics. Final log review found no unexpected script error, parse error, RID leak, orphan node, or unregistered warning. `git diff --check` and staged-diff checks passed before implementation commit `2cfd31c`.

## Certification boundaries

- Gauntlets remains `LAUNCH` / `EXPANSION`; M1 and NEXT availability are unchanged.
- M1 remains `M1 Candidate — External Validation Pending`; authentic external human playtests remain `0 / 20`.
- Programmatic Pixel Proxy art is mechanically certified but still requires real-player screenshot and subjective visual tuning.
- Full localization/input/resolution visual acceptance, exact Combo tier naming, feedback-frequency budgets, replay, and legacy removal remain P11G scope.
- Contract-mode export checks do not certify installed templates, packaged startup, signing, store credentials, publication, or remote push.

## Next handoff

P11G is the next implementation gate. It must finish capability-based item effects, remove legacy `player_attacked` and Sword presentation fallbacks, add deterministic five-weapon replay, enforce high-frequency accessibility budgets, complete cross-weapon UI contracts, and create the unified player-facing Launch loadout entry rather than treating runtime availability as sufficient UI completion.
