# Plane Walker P11E Launch Staff Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11E Launch Staff implementation evidence below final P11 certification
- Applies To: `staff_launch_v1`, Mana and element sequencing, ordered combinations, elemental status ownership, Staff projectiles and zones, four time interactions, Chrono Warden conversion, Staff HUD and feedback, typed facts, snapshots, reset, and Candidate isolation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Worktree Base HEAD: `b5414a7`
- Implementation Certification Commit: `f1f022d`
- Rollback Point: `b5414a7`

## Completion decision

P11E Launch Staff is `Verified Locally` at implementation commit `f1f022d`. The authoritative Profile, deterministic Mana loop, free and charged primary boundary, three elements, six ordered combinations, real projectile and zone execution, source-owned elemental statuses, Planar Collapse, seeded Primordial Wrath, four time interactions, Chrono Warden conversion, Player integration, HUD, feedback, typed facts, snapshot/reset behavior, and bounded runtime ledgers pass the final Staff gate and complete repository validation.

The final focused Staff suite passed `7 / 7` with zero leak warnings. The final repository validation passed `97 / 97` Godot scene tests with only the registered `reward_system_smoke` ObjectDB warning, and its documentation, localization, playtest-data, M1, coverage-contract, export-contract, bootstrap-import, and clean-import sub-gates all passed. Final static and independent reviews reported no P0, P1, or P2 blocker.

Staff remains limited to `LAUNCH` and `EXPANSION`. It is unavailable in the M1 Sword run and the P10 Candidate Lab, and this implementation does not promote Staff to Current or change the frozen M1 candidate.

Formal product status remains `M1 Candidate — External Validation Pending`. Authentic external human playtests remain `0 / 20`. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Authoritative data contract

`staff_launch_v1` is the single Staff runtime Profile. The current Base Pack weapon Profile catalog and manifest entry are frozen by SHA-256:

```text
67f41d92276e2da360e5c43ee8257e435162ac3729c5cd369f8e30cb9a57e4ce
```

The Profile rejects parser-valid drift across identity, availability, actions, resources, capabilities, payloads, cues, element definitions, combinations, time interactions, Boss conversion, tags, compatibility, effects, references, and localization keys.

| Action | Frozen contract |
|---|---|
| Arcane Bolt | Primary release through frame 29; `4 / 1 / 10`; free; `0.8×` projectile |
| Charged Element | Primary release from frame 30; `8 / 2 / 16`; Fire costs 20 Mana, Ice 25, Lightning 18 |
| Element Cycle | `1 / 1 / 2`; cycles Fire → Ice → Lightning → Fire without spending Mana |
| Planar Collapse | `12 / 6 / 20`; 30 Mana and 20 Time Energy; centered six tiles ahead; `3.2×`, four-tile radius, 180-frame field |
| Primordial Wrath | 60-frame HOLD; `20 / 20 / 30`; 60 Mana and 55 Time Energy; one seeded zone with 20 ticks every six frames |

The Mana resource starts at 100, is capped at 100 before modifiers, and regenerates at three per second on coordinator frames. Eligible charged-spell damage restores two percent Mana, capped at five Mana per outcome and deduplicated by outcome identity.

## Runtime authority and atomic transactions

```text
semantic weapon intent
  -> PlayerController aim and immutable time context
  -> WeaponActionCoordinator HOLD / WINDUP / ACTIVE / RECOVERY authority
  -> StaffWeaponRuntime validated plan and resource transaction
  -> StaffWeapon projectile / zone adapter
  -> StaffProjectile / StaffSpellZone real combat execution
  -> elemental status ownership, typed facts, rewards, snapshots, and cleanup
```

- `WeaponActionCoordinator` remains the only action clock and owns HOLD release, action phases, cooldowns, Time Energy transactions, buffered input, cancellation, and coordinator snapshots.
- `StaffWeaponRuntime` owns deterministic Mana regeneration, element selection, combination windows, combination surcharge reservation, Rewind claims, outcome-bound Mana return, and presentation state.
- The 300-frame combination window is frozen at second-cast commit. Projectile travel cannot reset or extend a nearly expired window; expiry removes the cast-ledger combination and refunds its reserved surcharge exactly once.
- Construction or release failure restores Mana, Time Energy, cooldown ownership, pending combination surcharge, and generation-safe Rewind availability without publishing a successful action.
- Raw projectile and zone outcomes are normalized into the runtime contract with a positive generation, stable `outcome_id`, element, target identity, terminal flag, hit flag, and resolved damage.
- Safe WINDUP snapshots may restore. Snapshots containing ACTIVE or RECOVERY payload ownership fail closed instead of pretending that live projectiles, zones, or invulnerability can be reconstructed.
- Cast, outcome, fact, payload, and source bookkeeping is bounded to 256 retained entries where applicable. Reset, death, Rewind cancellation, loadout replacement, and action cancellation retire owned projectiles, zones, statuses, claims, and invulnerability sources.

## Real spell and elemental-status execution

| Spell or effect | Implemented behavior |
|---|---|
| Fire | `4.0×` direct/explosion damage in a 2.5-tile radius, owned 240-frame Burn, 30-frame Burn ticks, and `0.1×` tick damage |
| Ice | `2.5×` impact, three-tile zone for 300 frames, 30-frame `0.08×` ticks, movement and attack slow, 60-frame Freeze, and departure cleanup |
| Lightning | `3.0×` primary damage, up to three additional targets within four tiles, distance-then-stable-ID chain order, `0.7×` chain damage, and owned Shock |
| Steam Burst | Fire → Ice; split Fire/Ice explosion, three-and-a-half-tile radius, and deterministic Blind |
| Blazing Storm | Fire → Lightning; 360-frame damage zone with Burn and repeated Fire/Lightning ticks |
| Crystal Thunder | Ice → Lightning; delayed dual-element explosion followed by an ice surface |
| Reverse Steam | Ice → Fire; immediate Freeze field followed by the delayed split explosion and Blind |
| Thunder Flare | Lightning → Fire; delayed Fire explosions at confirmed chain-target origins |
| Thunder Crystal | Lightning → Ice; delayed Ice crystals and Freeze at confirmed chain-target origins |
| Planar Collapse | Resolves at the six-tile aim offset, damages and controls real targets, applies owned Void Erosion, and uses Boss-safe slow/conversion behavior |
| Primordial Wrath | One deterministic zone executes exactly 20 seeded element ticks, applies cast invulnerability, and requests two Time Energy per completed tick with action-token deduplication |

Elemental status entries are keyed by `(effect_id, source_id, generation)`. Refreshing or clearing one source cannot remove another source's Burn, Slow, Freeze, Shock, Blind, or Void Erosion. Enemy death, room/reset cleanup, Boss phase transition, and matching Staff payload retirement remove only the owned generations. Blind uses stable action-and-target seed material and does not depend on unstable node instance ordering.

## Time interactions and Chrono Warden conversion

| Interaction | Implemented behavior |
|---|---|
| Stop | Planar Collapse area and duration are multiplied by `1.5`, bounded by the Profile cap and guarded by the live source generation |
| Rewind | One generation-safe 120-frame claim makes the next eligible charged cast Mana-free and `1.3×`; Fire therefore resolves at `5.2×`; failed staging does not consume the claim |
| Accelerate | Future charged casts use a 15-frame threshold and `0.7×` Mana cost; in-flight timing remains immutable |
| Rift | A valid intersecting ordered combination expands its relevant radii by `1.3×` and adds `0.5×` Time damage; stale callbacks refund the reserved surcharge once |

Chrono Warden rejects Staff Freeze and Blind conversion during `WINDUP` or a committed active attack, even when exposure is visible. Eligible `RECOVERY` or `EXPOSED` hits convert Freeze into 12 frames of action delay and Blind into eight frames, with source-generation ownership, target deduplication, bounded exposure/poise effects, and phase-transition cleanup. A committed Slam is preserved and cannot settle twice.

## HUD, feedback, and Player integration

- `RunViewState` projects Staff Mana, selected `element`, `combo_element`, and `combo_remaining_frames` through the strict weapon-state union while retaining compatibility aliases for older fixtures.
- The compact HUD renders Staff resource and combination state without exposing action tokens or mutable runtime internals.
- Pixel Proxy reads the nested authoritative runtime fields and renders the actual selected element instead of defaulting every Staff action to Fire.
- Staff feedback exposes distinct basic, element-cast, cycle, skill, ultimate, impact, and resource cues through the shared feedback/audio path.
- Player assembly accepts Staff only for `LAUNCH` and `EXPANSION`, preserves 29/30 primary and 59/60 ultimate boundaries, rotates aim correctly, deduplicates Mana and Time Energy facts, and clears Staff ownership on reset, death, Rewind, and loadout changes.

## Validation evidence

### Staff runtime and Player checkpoints

- `staff_weapon_runtime`: `1 / 1` PASS at `planewalker-tests.FVqwyv`; zero leak warnings.
- `player_launch_staff_integration`: `1 / 1` PASS at `planewalker-tests.jG0Kr3`; zero leak warnings.
- `staff_time_boss_integration`: PASS at `planewalker-tests.4djmin`; the retained run reports no leak warning.

These checkpoints cover Profile drift rejection, 29/30 and 59/60 boundaries, Mana regeneration/return, all six ordered combination transactions, near-expiry projectile behavior, generation-safe time interactions, Boss state conversion, authoritative Staff assembly, real reward routing, and lifecycle cleanup.

### HUD, feedback, content, and localization checkpoints

- `run_view_state`: `2 / 2` PASS at `planewalker-tests.JCqqP7`.
- `run_view_state_projector`: `1 / 1` PASS at `planewalker-tests.TqOFhx`.
- `combat_hud_v2_scene`: `1 / 1` PASS at `planewalker-tests.5LODiG`.
- `combat_feedback_runtime`: `1 / 1` PASS at `planewalker-tests.BSrGeg`.
- `content_registry`: PASS at `planewalker-tests.BQwfA0`.
- `content_pack_contract`: PASS at `planewalker-tests.OR1OlO`.
- Localization unit contract: `8 / 8` PASS.

The retained runs report no script error, parse error, ObjectDB/RID leak, or orphan warning. The macOS headless CA-store diagnostic remains an approved environment diagnostic when emitted.

### Final focused Staff gate

```bash
./tools/run_tests.sh --filter staff
```

Result: `7 / 7` Staff scenes passed, zero failed, and zero leak warnings.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.6ks5Ap
```

The final gate covers the Staff Profile contract, runtime transactions, real Fire/Ice/Lightning and six-combination execution, elemental status ownership, normalized payload results, Player assembly and lifecycle, time interactions, Chrono Warden conversion, stable Blind seeding, six-tile Planar Collapse, Ultimate invulnerability and reward routing, bounded ledgers, and stale-callback rejection. Its log scan contains no script error, parse error, ObjectDB/RID leak, orphan node, or unregistered warning.

### Complete repository gates

The final `./tools/validate_project.sh` run passed:

- shell and CI contracts with 97 discovered scenes;
- documentation governance `30 / 30`, `violations=0`;
- localization `8 / 8`;
- playtest data `13 / 13`;
- M1 release gate `27 / 27`;
- GDScript coverage contracts `5 / 5`, with line coverage honestly recorded as `not collected (godot_line_coverage_unsupported)`;
- export contracts `37 / 37` in contract mode;
- bootstrap import and clean second import;
- final Godot scene suite `97 / 97` with only the registered `reward_system_smoke` ObjectDB warning.

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.1Wdg8l
```

The import path emitted only the approved macOS CA-store and settings diagnostics. Final log review found no unexpected script error, parse error, ObjectDB/RID leak, orphan node, or unregistered warning. Final static and independent reviews reported no P0, P1, or P2 blocker. Final `git diff --check` and staged-diff checks passed before implementation commit `f1f022d`.

## Certification and release boundaries

- Staff remains `LAUNCH` / `EXPANSION`; M1 and NEXT availability are unchanged.
- M1 remains `M1 Candidate — External Validation Pending`; authentic external human playtests remain `0 / 20`.
- This record does not certify subjective combat feel, final balance quality, real controller comfort, external player acceptance, or real-world accessibility validation.
- GDScript line coverage is unsupported by the current toolchain and is not inferred from scene counts.
- Contract-mode export checks do not certify installed platform templates, packaged startup on Windows/Linux/macOS, signing identities, store credentials, publication, or remote push.
- Formal replay serialization remains P11G scope and is not claimed by this certification. The 30 weapon/time-loadout matrix remains P11H scope.

## Next handoff

P11F Gauntlets is the next implementation gate. It must reuse the coordinator, strict Profile authority, source-generation ownership, deterministic payload construction, bounded ledgers, generic Staff-compatible ViewState union, and the snapshot/reset discipline proven by the prior weapons.
