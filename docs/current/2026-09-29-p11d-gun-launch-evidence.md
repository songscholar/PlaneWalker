# Plane Walker P11D Launch Gun Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11D Launch Gun implementation evidence below final P11 certification
- Applies To: `gun_launch_v1`, ammunition and reload transactions, Gun projectiles, four time interactions, Chrono Warden conversion, Gun HUD, feedback, typed facts, snapshots, reset, and Candidate isolation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Worktree Base HEAD: `b482d53`
- Implementation Certification Commit: `e92e7f4`
- Rollback Point: `b482d53`

## Completion decision

P11D Launch Gun is `Verified Locally` at commit `e92e7f4`. The authoritative Profile, six-round ammunition loop, normal/aimed/shotgun fire, reload/perfect reload, Time Load, Void Penetration, deterministic projectile construction, four time interactions, Chrono Warden conversion, typed facts, HUD, feedback, snapshot/reset lifecycle, focused regressions, complete scene suite, clean import path, and repository validation pass locally.

Gun remains limited to `LAUNCH` and `EXPANSION`. It is not available in the M1 Sword run or the P10 Candidate Lab. This certification does not promote Gun to Current and does not retune the frozen M1 candidate.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic external human playtests remain `0 / 20`. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Authoritative data contract

`gun_launch_v1` is the single runtime Profile. It rejects parser-valid drift across action, payload, cue, resource, time-interaction, Boss-interaction, identity, availability, localization, tag, compatibility, effect, and reference fields. The current Base Pack weapon Profile catalog is frozen by SHA-256:

```text
bea51fb9a6580efecf1cad176b24d6c1ef84749e3b11b3331b25107d9feb32b9
```

The Base Pack manifest records the same digest. Its localization catalog is frozen by SHA-256:

```text
213de13f89d02fed287dd0a1caca20465eab819c896355fb5bfb74abd7a71c3b
```

| Action | Frozen contract |
|---|---|
| Normal Fire | Primary release through frame 17; `3 / 1 / 8`; one ammo; `1.0×` damage; 15-tile range |
| Aimed Fire | Primary release from frame 18; `8 / 1 / 12`; one ammo; `2.5×` damage; one pierce; 20-tile range |
| Shotgun Fire | `8 / 2 / 20`; two ammo; eight independently seeded `0.7×` pellets across 45 degrees; per-pellet target deduplication |
| Reload | 48 total frames; dash-cancellable from frame 8 through 39; final lock from frame 40; Perfect window `28–36`; normal fill 6; Perfect fill 7 and four recovery frames |
| Time Load | `8 / 1 / 4`; 25 Time Energy; 360-frame cooldown; 300-frame buff; active refill 6; future ammo-free actions and accelerated action timing |
| Void Penetration | 60-frame HOLD; `18 / 3 / 25`; 65 Time Energy; 720-frame cooldown; `15.0×` split Void/Time damage, unlimited pierce, vulnerability, explosions, and a deterministic trail |

## Runtime authority and atomic transactions

```text
semantic weapon intent
  -> PlayerController aim and immutable time context
  -> WeaponActionCoordinator HOLD / WINDUP / ACTIVE / RECOVERY authority
  -> GunWeaponRuntime validated plan and resource transaction
  -> GunWeapon projectile adapter
  -> GunProjectile hit, trail, explosion, and target-deduplication execution
  -> typed weapon facts, cues, rewards, snapshots, and cleanup
```

- `WeaponActionCoordinator` owns action timing, HOLD release, cooldowns, Time Energy reservation/commit, buffered input, cancellation, and resource rollback.
- Ammunition is committed atomically with projectile construction. A construction failure restores ammo, Time Energy, cooldown, action ownership, and Rewind claim availability.
- Empty primary starts Reload. Shotgun rejects at one round instead of consuming a partial transaction.
- Perfect Reload fills to seven, grants one free Time Load, preserves an already active cooldown, and enters its declared four recovery frames.
- All eight Shotgun pellets share the committed action token while keeping per-pellet hit identity. Resource rewards and typed facts deduplicate at the action boundary where required.
- Snapshot, restore, reset, death, rewind cancellation, and loadout reconfiguration preserve or clear action ownership, ammo, cooldowns, buffs, claims, and live projectiles according to their lifecycle contract.

## Projectile, time, and Boss behavior

| Interaction | Implemented behavior |
|---|---|
| Stop | Aimed Fire creates a two-tile TIME burst and requests one 30-frame Stop extension per action token; stale or retired projectiles cannot extend Stop |
| Rewind | A generation-safe 120-frame claim makes the next eligible shot ammo-free and `1.5×`; all projectiles are preconstructed before the generation is claimed, and failed staging rolls back completely |
| Accelerate | Future recovery is reduced by four frames; ammo cost is multiplied by `0.5` and rounded up, so non-free actions never underpay |
| Rift | Eligible projectiles create a 90-frame, one-tile trail with 30-frame ticks only when their actual path intersects the live Rift boundary |

- Void Penetration applies source-aware vulnerability and cannot use another source to refresh or remove its ownership.
- Time Load modifies future committed plans without mutating an in-flight action. Its active and Perfect-granted forms remain distinguishable in state and HUD projection.
- Stop explosions, Rift trails, Void explosions, and trail ticks deduplicate targets and reject stale callbacks after reset or retirement.
- The adapter forwards only live projectile signals whose token, source, and owner still match. Released-projectile action claims are retained long enough to reject duplicate callbacks safely.
- Chrono Warden preserves an active committed attack. Eligible RECOVERY or EXPOSED hits convert control into bounded poise contribution with target deduplication.

## HUD, feedback, and typed facts

- `RunViewState` schema 3 exposes a strict `weapon_state` union for Sword, Bow, and Gun. Gun projects ammo, reload progress, Perfect Reload, active Time Load, and free Time Load without exposing internal action IDs.
- The compact HUD remains safe at 640×360, 1280×720, 1920×1080, and 2560×1080 and preserves the two time-ability slots.
- Pixel Proxy adds the Gun silhouette, muzzle flash, reload marker, Perfect ring, Time Load tint, and resource-action stance. Gun attacks do not render the Sword slash.
- Audio exposes distinct `gun_fire`, `gun_aimed_fire`, `gun_shotgun`, `gun_reload`, `gun_time_load`, and `gun_ultimate` cues.
- Player integration publishes `weapon_hit_confirmed` and `weapon_resource_changed` once per eligible action boundary, supports Gun Time Energy rewards, rejects unknown rewards fail-closed, and bounds token/fact ledgers to 256 entries.

## Validation evidence

### Focused Gun gate

```bash
./tools/run_tests.sh --filter gun
```

Result: `5 / 5` scenes passed, zero failed, zero leak warnings.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.QT5bV5
```

The focused suite covers the Profile contract, runtime boundary table, projectile lifecycle, adapter integration, Player integration, Stop stale protection, real Rewind context normalization, generation claim/rollback, Rift path intersection, Accelerate rounding, and snapshot/reset ledgers. Its final log scan contains no script error, parse error, ObjectDB/RID leak, or orphan warning.

### Adjacent weapon and action regressions

Eighteen focused Sword, Bow, coordinator, PlayerAction, resource, modifier, rewind, time-context, event-publication, and loadout scenes passed after Gun reached a stable state. Every final run reported zero failed scenes and zero leak warnings. The retained logs are:

```text
planewalker-tests.7xgIzf  planewalker-tests.sVFY2L  planewalker-tests.iW6Bld
planewalker-tests.KMoHOz  planewalker-tests.hkek42  planewalker-tests.uk5tzu
planewalker-tests.i0Ql4c  planewalker-tests.BOvjm1  planewalker-tests.TIHbLL
planewalker-tests.4WOCWM  planewalker-tests.d3oJwV  planewalker-tests.DpTWvU
planewalker-tests.aIN8lC  planewalker-tests.5eRYb0  planewalker-tests.We4h1i
planewalker-tests.akanwL  planewalker-tests.Bvn4ze  planewalker-tests.D3jj7i
```

### HUD, feedback, localization, and host gates

- `run_runtime_host`: `1 / 1` PASS at `planewalker-tests.ViCvnT`.
- `run_view_state`: `2 / 2` PASS at `planewalker-tests.eHFrdM`.
- `combat_hud_v2_scene`: `1 / 1` PASS at `planewalker-tests.fg9Tg0`.
- `run_view_state_projector`: `1 / 1` PASS at `planewalker-tests.Zw738V`.
- `combat_feedback_runtime`: `1 / 1` PASS at `planewalker-tests.rB7mV2`.
- `content_pack_contract`: `1 / 1` PASS at `planewalker-tests.QZXI10`.
- Localization unit contract: `8 / 8` PASS; catalog validator: PASS.

The macOS headless runs may emit the approved system CA-store environment diagnostic. It is not a project script error.

### Complete repository gates

The final standalone scene suite passed `88 / 88`:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.Drv3x9
```

The only registered leak warning is the pre-existing `reward_system_smoke` ObjectDB warning. The input-profile corruption and migration tests intentionally parse malformed JSON and then pass their recovery assertions; those expected engine diagnostics are not P11D runtime failures.

The final `./tools/validate_project.sh` run passed:

- shell and CI contract with 88 discovered scenes;
- documentation governance `30 / 30`, zero violations;
- localization `8 / 8`;
- playtest data `13 / 13`;
- M1 release gate `27 / 27`;
- GDScript coverage contracts `5 / 5`;
- export contracts `37 / 37` in contract mode;
- bootstrap import and clean second import;
- final Godot scene suite `88 / 88` with the one registered warning.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.8FraGn
```

Final `git diff --check` and staged diff checks passed before the implementation commit.

## Certification and release boundaries

- Gun remains `LAUNCH` / `EXPANSION`; M1 and NEXT availability are unchanged.
- M1 remains `M1 Candidate — External Validation Pending`; authentic external human playtests remain `0 / 20`.
- This record certifies deterministic local behavior, not subjective combat feel, balance quality, real controller comfort, or external player acceptance.
- GDScript line coverage is unsupported by the current toolchain and is not inferred from scene counts.
- Export contracts pass, but platform templates, packaged startup on Windows/Linux/macOS, signing identities, store credentials, publication, and remote push are not certified here.
- Formal replay serialization and the 30 weapon/time-loadout matrix remain P11G–P11H scope.

## Next handoff

P11E Staff is the next implementation gate. It must reuse the coordinator, strict Profile authority, generic `weapon_state`, source-aware status ownership, deterministic projectile/zone construction, and the same snapshot/reset/replay-ready lifecycle proven by P11D.
