# Plane Walker P11A Shared Weapon Authority Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P11A shared weapon profile, action authority, semantic input, modifier, and typed-fact certification evidence
- Applies To: WeaponRuntimeProfile v1, milestone-aware profile resolution, WeaponActionCoordinator, WeaponRuntime contract, WeaponIntentRouter, WeaponModifierState, semantic InputMap actions, additive typed weapon facts, Content Pack integrity, and regression isolation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified Implementation HEAD: `5369bf9`
- Certified Repository State: `5369bf9` plus this documentation-certification commit
- Rollback Point: `40c10ba`

## Completion decision

P11A is locally complete. The repository now validates seven milestone-aware weapon runtime profiles for all five weapons, resolves exactly one profile before a run reaches the Player boundary, owns a single reusable weapon action transaction/phase coordinator, normalizes legacy input into semantic weapon intents, freezes bounded weapon modifiers per action, and exposes additive typed weapon facts without removing the still-required Sword/Bow compatibility path.

This gate does not claim that Sword or Bow has already migrated to the coordinator, and it does not claim that Gun, Staff, or Gauntlets gameplay is complete. Those remain P11B–P11F work. Formal M1 remains `M1 Candidate — External Validation Pending`, authentic human playtests remain `0 / 20`, and GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.

## Certified implementation chain

| Commit | Deliverable |
|---|---|
| `40c10ba` | Approves the unified five-weapon design and supersedes the Staff-only integration path |
| `ed65449` | Defines the P11A–P11H executable plan and shared-file ownership rules |
| `245b533` | Adds Profile v1 schema/parser, seven Base Pack profiles, integrity hashes, weapon references, Registry validation, and milestone profile resolution |
| `ed03dff` | Adds the atomic coordinator, runtime contract, phase/buffer/cancel/generation/snapshot logic, and exactly-once local committed facts |
| `5369bf9` | Adds semantic input migration/edges, bounded modifier snapshots, semantic project actions, and additive typed EventBus facts |

## Profile and availability authority

The Base Pack contains exactly seven profiles:

- `sword_m1_v1`: `M1`, `CURRENT`
- `sword_launch_v1`: `NEXT`, `LAUNCH`, `EXPANSION`
- `bow_candidate_v1`: `NEXT`
- `bow_launch_v1`: `LAUNCH`, `EXPANSION`
- `gun_launch_v1`: `LAUNCH`, `EXPANSION`
- `staff_launch_v1`: `LAUNCH`, `EXPANSION`
- `gauntlets_launch_v1`: `LAUNCH`, `EXPANSION`

Every profile contains typed actions, resources, capabilities, payloads, cues, all four time interactions, and a Chrono Warden conversion. Profile availability cannot widen beyond its referenced weapon, and `RunLoadoutPolicy` rejects a missing or ambiguous profile before returning an accepted loadout.

## Action and input authority

`WeaponActionCoordinator` proves:

- read-only planning before commit;
- atomic runtime rollback when commit fails;
- immutable token and generation invalidation;
- deterministic phase timing and half-open recovery-cancel boundaries;
- buffered intent expiry and replacement discipline;
- idempotent cancellation;
- safe snapshot restore that cannot revive stale callbacks;
- recursive rejection of non-finite plan data;
- exactly one local `weapon_action_committed` fact per accepted transaction.

`WeaponIntentRouter` proves schema 1 to schema 2 migration for weapon actions, lossless binding-family merge, hold/toggle edge equivalence, and fail-closed ambiguous profiles. The project now declares semantic weapon and equipped time-slot actions while the legacy input profile remains operational for the P11B/P11C compatibility window.

## Full validation evidence

Authoritative command:

```bash
VALIDATION_LOG_DIR=/tmp/planewalker-p11a-final \
TEST_LOG_DIR=/tmp/planewalker-p11a-final/scene-tests \
./tools/validate_project.sh
```

Result:

- Shell/CI contract: PASS, `69` discovered scene tests.
- Documentation governance: `30 / 30` PASS, zero violations and zero baseline debt.
- Localization contracts: `7 / 7` PASS.
- Playtest data contracts: `13 / 13` PASS.
- M1 release-gate contracts: `27 / 27` PASS.
- GDScript coverage contracts: `5 / 5` PASS; line coverage remains unsupported and uncollected.
- Export contracts: `37 / 37` PASS in contract mode; templates and packaged startup remain externally unverified.
- Godot bootstrap and clean second import: PASS with only approved sandbox environment diagnostics.
- Godot scenes: `69 / 69` PASS.
- Registered warnings: one known `reward_system_smoke` ObjectDB warning.
- Validation logs: `/tmp/planewalker-p11a-final`.

## Remaining boundaries

- P11B must migrate Sword while preserving the certified M1 action/feedback timing exactly.
- P11C must migrate Bow charge/cooldown ownership and preserve the P10 candidate.
- P11D–P11F must implement Gun, Staff, and Gauntlets runtimes.
- P11G must finish cross-weapon HUD, feedback, modifiers, replay, reset, and remove legacy facts/branches.
- P11H must pass the `5 weapons × 6 time pairs = 30` matrix and deterministic balance simulations.
- Authentic human playtests, three-platform packaged startup, signing, publication, and commercial credentials remain outside local evidence.
