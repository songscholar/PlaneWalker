# Plane Walker P11 Staff Runtime Implementation Plan

- Status: Superseded
- Document Role: Historical implementation plan
- Authority Level: Superseded by the unified P11 five-weapon plan
- Applies To: Historical Staff-only planning assumptions created before shared weapon runtime authority was frozen
- Owner: Project integration lead
- Depends On: `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`
- Last Verified: 2026-09-29
- Implementation Status: Not executed as an independent plan; absorbed into the unified P11 five-weapon implementation before runtime integration
- Completion Evidence: Historical planning commit `301a6ba`; no certified Staff runtime or GREEN gate was produced by this plan

> **Supersession notice:** This plan is retained for audit history only. Its direct `StaffWeapon` + `PlayerController` integration path is not executable authority. Reusable Staff requirements are absorbed into the unified P11 plan and must use `WeaponIntentRouter`, `WeaponActionCoordinator`, `WeaponRuntimeProfile`, and `WeaponModifierState`.

> **For agentic workers:** REQUIRED SUB-SKILL: execute each task with test-first changes, targeted verification, and a focused commit.

**Goal:** Deliver a fully playable Staff weapon vertical slice with deterministic elemental spells, ordered combos, time-system interactions, Boss-safe control effects, HUD state, feedback, and regression coverage.

**Architecture:** `StaffWeapon` owns Mana, element selection, charging, cast reservation, and combo sequencing. Projectiles and zones are presentation-facing effect carriers; a reusable source-aware elemental-status runtime owns burn, slow, freeze, shock, and blind lifecycles. `PlayerController` remains the sole action-clock owner and exposes a weapon-neutral UI snapshot.

**Tech Stack:** Godot 4 GDScript, scene-based test harness, JSON content packs, deterministic run seeds, existing EventBus/TimeManager/ViewState contracts.

## Global Constraints

- Preserve Sword and Bow behavior and all existing loadout gates.
- Use `Stats.attack` as the single attack-power authority.
- Record spell sequence on confirmed hit, never on button press.
- Reserve base and combo Mana atomically before a committed charged cast.
- Use run-seeded randomness for every random spell outcome.
- Use source IDs for overlapping status, zone, stop, and rift effects.
- Boss control effects must degrade deterministically instead of becoming immune.
- A task is complete only when code, data, tests, documentation, and build-path coverage are present.

---

### Task 1: Authoritative Staff spell catalog

**Files:**
- Create: `data/content_packs/base/content/staff_spells.json`
- Modify: `data/content_packs/base/pack.json`
- Create: `tests/contract/content_schema/staff_spell_catalog_contract_test.gd`
- Create: `tests/contract/content_schema/staff_spell_catalog_contract_test.tscn`

**Produces:** A validated catalog for basic, fire, ice, lightning, collapse, ultimate, and six ordered combos.

- [ ] Write the contract test for IDs, element order, frame counts, Mana costs, multipliers, ranges, durations, tick counts, combo windows, and ordered pairs.
- [ ] Run `./tools/run_tests.sh --filter staff_spell_catalog_contract` and confirm the missing catalog fails.
- [ ] Add the catalog and manifest integrity metadata.
- [ ] Re-run the contract test and content-pack contract tests.
- [ ] Commit the catalog and contract together.

### Task 2: Staff resource and charge state machine

**Files:**
- Create: `scripts/combat/staff_weapon.gd`
- Create: `tests/combat/staff_weapon_test.gd`
- Create: `tests/combat/staff_weapon_test.tscn`

**Produces:** `StaffWeapon` APIs for Mana tick/recovery, element cycling, hold/toggle charge, atomic cast reservation, cooldowns, damage-based Mana gain, hit-confirmed combo windows, and safe reset.

- [ ] Write failing tests for 100 Mana cap, 3/second regeneration, 30-frame charge, fire/ice/lightning costs, instant element switching, insufficient-funds rejection, atomic combo reservation/refund, five-second hit window, timeout, same-element rejection, and reset.
- [ ] Run the focused scene and confirm it fails before implementation.
- [ ] Implement only the state-machine surface required by the tests.
- [ ] Re-run the focused scene and inspect the Godot log for parser/runtime/leak errors.
- [ ] Commit the resource runtime and tests.

### Task 3: Source-aware elemental statuses

**Files:**
- Create: `scripts/combat/elemental_status_runtime.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Create: `tests/combat/elemental_status_runtime_test.gd`
- Create: `tests/combat/elemental_status_runtime_test.tscn`

**Produces:** Source-scoped burn, movement/attack slow, freeze, shock, and deterministic blind with Boss resistance transforms.

- [ ] Write failing overlap, refresh, expiry, cleanup, death, freeze conversion, slow-cap, and blind-determinism tests.
- [ ] Run the focused scene and capture the expected failures.
- [ ] Implement the status runtime and narrow enemy/Boss hooks.
- [ ] Re-run status, enemy timing, time-stop resistance, and Boss action-state tests.
- [ ] Commit the status layer.

### Task 4: Projectiles, zones, combos, and seeded ultimate

**Files:**
- Create: `scripts/combat/staff_projectile.gd`
- Create: `scripts/combat/staff_spell_zone.gd`
- Create: `scenes/combat/staff_projectile.tscn`
- Create: `scenes/combat/staff_spell_zone.tscn`
- Create: `tests/combat/staff_spell_runtime_test.gd`
- Create: `tests/combat/staff_spell_runtime_test.tscn`

**Produces:** Single-hit projectiles, lightning chain deduplication, fixed-tick zones, all six ordered combos, collapse, and a 20-tick seeded ultimate.

- [ ] Write failing tests for hit-once, chain target uniqueness, exact zone tick counts, all ordered combo directions, rift amplification, collapse control, and identical-seed ultimate outcomes.
- [ ] Run the focused scene and confirm each subsystem fails for the intended missing behavior.
- [ ] Implement projectile/zone carriers and deterministic target ordering.
- [ ] Re-run the focused scene plus projectile, seed, and replay regressions.
- [ ] Commit runtime carriers and spell integration.

### Task 5: Player action-owner integration

**Files:**
- Modify: `scripts/player/player_action_state.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scenes/player/player.tscn`
- Modify: `tests/player/player_action_state_test.gd`
- Modify: `tests/player/player_action_runtime_test.gd`

**Produces:** Tap basic cast, hold charged cast, toggle accessibility mode, instant element switch, short/long Staff special input, action interruption, rewind safety, and loadout gating through the single player action clock.

- [ ] Add failing action-owner tests for Staff input, movement multipliers, dash/time buffering, hitstun/death cancellation, rewind cleanup, and new-run reset.
- [ ] Run the focused player tests and confirm Staff cases fail while Sword/Bow remain green.
- [ ] Add weapon-neutral charge/channel action transitions and integrate the Staff node.
- [ ] Re-run all player, rewind, loadout, and input tests.
- [ ] Commit player integration.

### Task 6: Time ability and Boss contracts

**Files:**
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/time_rift.gd`
- Create: `tests/integration/combat/staff_boss_interaction_test.gd`
- Create: `tests/integration/combat/staff_boss_interaction_test.tscn`

**Produces:** Stop extension, two-second rewind free cast/+30% damage, accelerated 15-frame/-30% Mana casts, rift range/time bonus, and Chrono Warden resistance behavior.

- [ ] Write failing tests for the four time interactions and Boss control conversions.
- [ ] Run the focused integration scene and confirm intended failures.
- [ ] Add explicit, source-aware TimeManager/Rift hooks and consume-once rewind windows.
- [ ] Re-run time, Boss, rewind, replay, and Staff integration suites.
- [ ] Commit time/Boss integration.

### Task 7: HUD, feedback, Pixel Proxy, audio, and localization

**Files:**
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/presentation/combat_audio_synth.gd`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/localization/translations.csv`

**Produces:** Mana, element, charge, combo-window, and cooldown UI plus Staff-specific cast, hit, status, animation, sound, and bilingual presentation.

- [ ] Add failing snapshot, schema, event exactly-once, localization, and 640x360 HUD tests.
- [ ] Run the focused contract/UI/feedback tests and capture failures.
- [ ] Upgrade the ViewState schema and render Staff state without changing non-Staff layout behavior.
- [ ] Replace weapon-hardcoded feedback lookups with event context and add Staff presentation mappings.
- [ ] Re-run HUD at 640x360, 1280x720, and 1920x1080 plus localization/feedback regressions.
- [ ] Commit presentation integration.

### Task 8: Full Staff certification

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Create: `docs/quality/p11-staff-certification.md`
- Modify: loadout smoke/validation tests as required by the authoritative test matrix.

**Produces:** Staff × six time-loadout smoke evidence, import evidence, full-suite evidence, build evidence, limitations, rollback commits, and scope-status documentation.

- [ ] Run Staff × six equipped time pairs with deterministic seeds and record results.
- [ ] Run clean import and scan logs for parser/runtime/resource/leak failures.
- [ ] Run `./tools/run_tests.sh` and record the exact pass/fail total and coverage result.
- [ ] Run local export/build validation and a launch smoke of the produced artifact.
- [ ] Document evidence, remaining external-only limitations, and the exact rollback commit range.
- [ ] Commit the certification report and documentation status update.
