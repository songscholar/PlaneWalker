# Plane Walker P11C Bow Candidate Migration Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11C Bow Candidate coordinator migration and parity certification
- Applies To: Bow Candidate hold/release transactions, Profile-owned charge boundaries, modifier capabilities, projectile release, feedback, cancellation, rewind safety, and legacy action-clock retirement
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`, `docs/current/2026-09-29-p11b-sword-migration-evidence.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified Implementation HEAD: `0cf27da`
- Certified Repository State: `0cf27da` plus this documentation-certification commit
- Rollback Point: `4a2dc47`

## Completion decision

The P11C Bow Candidate migration is locally complete. The Candidate Bow now uses the shared `WeaponActionCoordinator` for the entire same-token `press -> HOLD -> release` transaction. `BowWeapon` is a payload adapter only: it owns no `_process()` action clock, charge duration, cooldown timer, legacy charge API, or direct combat-fact publication.

The certified Candidate contract remains unchanged: 9-frame minimum charge, 54-frame maximum charge and automatic release, 21-frame Profile cooldown, 0.75-to-1.75 damage interpolation, 440-to-680 projectile speed, 0.98 full-charge threshold, one full-charge pierce, and six Time Energy restored at most once per action token. Hold and toggle accessibility paths remain semantically equivalent. Dash, time actions, transient reset, death, loadout reconfiguration, and Rewind invalidate abandoned HOLD generations.

Bow item rewards now target frozen modifier capabilities instead of mutable adapter fields. Charge rate, full-charge damage, and pierce bonuses accumulate through bounded atomic operations and fail closed when Bow is not equipped. Candidate release cues, synthesized audio, Pixel Proxy draw/string/arrow presentation, reduced-motion behavior, and cue deduplication are Profile-driven.

This certification does not complete Launch Bow. Four-tier charge, 228-frame maximum hold, Scatter Shot, Focus Step, Temporal Arrow, Starfall, atomic Time Energy and cooldown transactions, four time-ability interactions, Chrono Warden conversion, generic weapon HUD, replay, and deterministic spread remain active P11C work.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic human playtests remain `0 / 20`. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Certified authority chain

```text
semantic ranged input
  -> PlayerController compatibility routing
  -> WeaponActionCoordinator
  -> BowWeaponRuntime + frozen WeaponModifierState snapshot
  -> BowWeapon payload adapter
  -> PlayerArrow
  -> typed coordinator facts and Profile cues
  -> CombatFeedback + Pixel Proxy
```

## Candidate invariants

- Bow press enters coordinator-owned `HOLD`; release finalizes the same token and generation.
- Releasing before frame 9 rejects atomically and spawns no projectile, fact, cue, reward, or cooldown side effect.
- Reaching frame 54 automatically finalizes once into `WINDUP`; the following frame enters `ACTIVE` and releases the projectile.
- The press-time aim, adapter stats, and modifier snapshot are immutable for the committed action.
- Full-charge energy restoration is deduplicated per action token even when a projectile can contact multiple targets.
- `weapon.charge_rate`, `weapon.full_charge_damage`, and `weapon.pierce` are bounded capabilities; invalid, non-finite, unsupported, or wrong-weapon mutations preserve the prior snapshot.
- `BowWeapon` exposes only the Profile payload lifecycle and cannot publish `player_attacked` directly.
- Bow-specific feedback suppresses the compatibility attack signal, deduplicates Profile cues, and respects reduced-motion and shake settings.

## Focused validation evidence

The integration owner and an independent review agent both ran the focused gate:

```text
weapon_modifier_state_test
item_effect_test
bow_weapon_runtime_test
weapon_runtime_profile_contract_test
content_registry_test
content_pack_resolver_test
combat_event_publication_test
player_action_runtime_test
player_loadout_runtime_test
rewind_action_cancellation_test
reward_system_smoke
```

Result: all eleven suites passed. The first ten reported zero leak warnings. `reward_system_smoke` reported the one project-registered known ObjectDB warning.

## Full repository validation

Authoritative command:

```bash
VALIDATION_LOG_DIR=/tmp/planewalker-p11c-candidate \
TEST_LOG_DIR=/tmp/planewalker-p11c-candidate/scene-tests \
./tools/validate_project.sh
```

Result:

- Shell/CI contract: PASS, `75` discovered scene tests.
- Documentation governance: `30 / 30` PASS, zero violations and zero baseline debt.
- Localization contracts: `7 / 7` PASS.
- Playtest data contracts: `13 / 13` PASS.
- M1 release-gate contracts: `27 / 27` PASS.
- GDScript coverage contracts: `5 / 5` PASS; line coverage remains unsupported and uncollected.
- Export contracts: `37 / 37` PASS in contract mode; real templates, packaged startup, signing, and publication were not checked.
- Godot bootstrap and clean second import: PASS with only approved sandbox environment diagnostics.
- Godot scenes: `75 / 75` PASS.
- Registered warnings: one known `reward_system_smoke` ObjectDB warning.
- Validation logs: `/tmp/planewalker-p11c-candidate`.

## Certified commits

- `508b443` — Bow Candidate runtime and frozen Profile parity.
- `b4df231` — Player routes Candidate Bow through the coordinator.
- `4670ae5` — Undercharge and time-cancellation coverage.
- `4a2dc47` — Bow-specific feedback and Pixel Proxy presentation.
- `ac2d292` — Bow rewards migrate to bounded modifier capabilities.
- `0cf27da` — Legacy Bow action clock and APIs retire.

## Remaining boundaries

- Coordinator must own Profile cooldown and Time Energy transactions before Launch Bow skills can be accepted.
- Player must route all five semantic weapon actions to the active runtime.
- Launch Bow must replace placeholder action data with the approved four-tier charge, Scatter Shot, Focus Step, Temporal Arrow, and Starfall contract.
- Deterministic spread, time interactions, Boss conversion, weapon HUD union, replay, and Launch presentation remain pending.
- Authentic human playtests, real GDScript line coverage, three-platform packaged startup, signing, publication, and commercial credentials remain external boundaries.
