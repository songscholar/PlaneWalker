# Plane Walker P11B Sword Migration Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11B Sword coordinator migration and M1 parity certification
- Applies To: SwordWeaponRuntime, WeaponActionCoordinator arbitration, Player integration, Profile-owned timing and payloads, Active-frame cues, ItemEffect and Pixel Proxy boundaries, rewind cancellation, and M1 regressions
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`, `docs/current/2026-09-29-p11a-shared-weapon-authority-evidence.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified Implementation HEAD: `1ff2600`
- Certified Repository State: `1ff2600` plus this documentation-certification commit
- Rollback Point: `107a1e7`

## Completion decision

P11B is locally complete. Sword actions now commit, advance, cancel, buffer, reset, snapshot, and present through `WeaponActionCoordinator`. `PlayerController` retains only the cross-domain arbitration boundary and compatibility projection; it no longer owns a second Sword phase clock, attack definition, heavy buffer, or combo phase transaction.

The certified M1 action contract remains unchanged: three light attacks, one heavy attack, the exact 6/5/11, 8/5/12, 10/6/17, and 21/8/27 frame tables, half-open recovery cancel frames, the 48-frame combo reset, attack-speed rounding, damage multipliers, knockback, tags, reward hooks, and Active-frame release timing all pass parity tests.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic human playtests remain `0 / 20`. This evidence does not claim that Launch Sword, Bow migration, Gun, Staff, Gauntlets, five characters, five floors, online services, platform packaging, or publication are complete.

## Certified authority chain

```text
RunLoadoutPolicy
  -> RunRuntimeFacade.active_loadout()
  -> RunRuntimeHost
  -> PlayerController.configure_loadout()
  -> WeaponRuntimeProfile + WeaponModifierState
  -> SwordWeaponRuntime
  -> WeaponActionCoordinator
  -> Player compatibility projection + immutable presentation snapshot
```

The Host path requires the policy-accepted Profile and rejects a missing Profile before Player configuration. Direct Player-only NEXT time-loadout fixtures retain a temporary M1 compatibility Profile, but publish `compatibility_profile_fallback=true`; the production Host cannot enter that path. Explicit milestone/Profile mismatches fail atomically.

## Combat and feedback invariants

- Same-frame action edges resolve as `Dash > Time Cast > Weapon`; the order is tested from READY and at the recovery cancel boundary.
- Buffered weapon intents are consumed only after Dash and Time buffers have had priority.
- Failed replacement rollback resets to READY, advances generation, clears the token and buffer, and publishes no additional commit.
- ACTIVE payload activation failure cancels safely and cannot advance into later phases.
- Sword timing is planned from the frozen M1 Profile contract, including legacy-compatible attack-speed rounding; Runtime no longer reads adapter attack timing.
- Damage multiplier, knockback, and tags are injected from the frozen action plan when the Hitbox opens. Adapter-state tampering cannot change the committed payload.
- Profile cue definitions are frozen across `animation_id`, `vfx_id`, `audio_id`, and `camera_id`.
- Runtime phase events flow through Coordinator and Player exactly once. Combat feedback reads Profile `audio_id` and `camera_id`; the legacy Sword feedback path is suppressed to prevent duplicate playback.
- Pixel Proxy reads `weapon_presentation_snapshot()` rather than the `SwordWeapon` child transform.
- Item effects cross the Player weapon-effect boundary and do not reach Sword or Bow nodes directly.

## Validation evidence

Authoritative command:

```bash
VALIDATION_LOG_DIR=/tmp/planewalker-p11b-final-2 \
TEST_LOG_DIR=/tmp/planewalker-p11b-final-2/scene-tests \
./tools/validate_project.sh
```

Result:

- Shell/CI contract: PASS, `73` discovered scene tests.
- Documentation governance: `30 / 30` PASS, zero violations and zero baseline debt.
- Localization contracts: `7 / 7` PASS.
- Playtest data contracts: `13 / 13` PASS.
- M1 release-gate contracts: `27 / 27` PASS.
- GDScript coverage contracts: `5 / 5` PASS; line coverage remains `not collected (godot_line_coverage_unsupported)`.
- Export contracts: `37 / 37` PASS in contract mode; export templates and packaged startup were not checked.
- Godot bootstrap and clean second import: PASS with only approved sandbox environment diagnostics.
- Godot scenes: `73 / 73` PASS.
- Registered warnings: one known `reward_system_smoke` ObjectDB warning.
- Validation logs: `/tmp/planewalker-p11b-final-2`.

## Remaining boundaries

- P11C must first add a shared same-token `press -> hold -> release` transaction before Bow charge can migrate without creating a second action clock.
- P11C must make cooldown frames Profile-authoritative, preserve P10 candidate boundaries, and prevent multi-target energy restoration from applying more than once per action token.
- P11D-P11F must implement Gun, Staff, and Gauntlets; P11G-P11H must complete generic HUD/feedback/replay integration and the 30-loadout matrix.
- GDScript line coverage, authentic human playtests, three-platform packaged startup, signing, publication, and commercial credentials remain unverified external boundaries.
