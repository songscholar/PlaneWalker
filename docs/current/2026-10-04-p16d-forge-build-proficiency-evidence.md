# P16D Forge, Build Library, and Proficiency Domain Evidence

- Status: Focused domain GREEN; native and durable integration pending
- Document Role: Current P16D isolated progression verification evidence
- Authority Level: Evidence beneath the approved P16 specification
- Applies To: Forge candidates, build candidates, bounded proficiency authority, domain schemas and tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`
- Last Verified: 2026-10-05

## Implemented domain boundary

`ForgeRuntime.configure(entries, meta_catalog)` consumes the twenty authoritative
forge JSON definitions. It rejects unknown fields, malformed nested costs,
invalid weapon/enchantment references, incompatible groups, and content beyond
the approved forge attack budget. A failed configure clears old definitions.

`ForgeRuntime.prepare_command(profile, command, expected_revision)` accepts
`forge_upgrade`, `enchant_preference`, and `void_temper`. It returns a detached
complete profile candidate and authored cost; it never spends or publishes live
state. Five upgrades succeed deterministically at costs 5/10/20/35/50 shards,
giving a maximum 5% attack bonus per weapon. Enchantment selection enforces one
or two available slots, prerequisite nodes, element/time-Void mutual exclusion,
and first-acquisition costs. Void temper costs thirty shards or three imprints
and adds no combat multiplier.

Acquired enchantments use at most fifteen fixed internal sources named
`forge-enchant-unlock:EN-01` through `forge-enchant-unlock:EN-15` in the existing
completed history. They survive unequip and JSON restoration; recall on another
weapon is free. Public commands cannot use the reserved namespace. EN-14's five
imprint unlock therefore spends only once. The integration lead owns the
reserved public namespace list in `MetaProfileState`/profile service.

`BuildLibrary.prepare_command` accepts `build_save` with the closed build shape
`{id, name, character_id, weapon_id, time_abilities}` and `build_remove` with
`build_id`. Storage is bounded at thirty-two entries and sorted by ID. Updating
an existing ID replaces one slot; removing an unknown ID fails. Production
character/weapon unlocks and one of the six distinct canonical time pairs are
required. `resolve(profile, build_id)` rechecks these conditions and returns a
detached selection. The full 150-loadout matrix is exercised.

`ProfileCommandCandidate` shares closed profile validation, stale/duplicate
command refusal, reserved source refusal, defensive candidate normalization,
and revision progression. Empty dictionaries are explicit refusals, not fresh
profile authority instances. Candidate producers remain below the profile
service; a caller cannot directly publish their returned state.

## Bounded proficiency authority

`WeaponProficiencyRuntime` has an independent schema-1 snapshot described by
`data/schemas/weapon_proficiency_v1.schema.json`:

```text
schema_id = planewalker.weapon_proficiency
schema_version = 1
revision
experience[weapon_id] = bounded integer
high_water[weapon_id][normal_run | training_drill] =
    {session_sequence, action_sequence}
```

Exactly five weapons and two contexts produce ten fixed high-water entries.
There are no per-action permanent markers or additions to the Meta root.
`prepare_observation(receipt, expected_revision)` accepts only the closed
`{session_sequence, action_sequence, weapon_id, action_id, context_id}` shape.
Each trusted accepted native weapon action grants one XP; a caller-supplied XP
amount is refused. A new session begins at action one; older sessions and
already observed actions refuse. Later sequence gaps do not synthesize XP for
the missing actions. The native adapter must authenticate both sequences and
allocate durable monotonic session identities before calling this domain.

Preparation returns an owner-bound ticket, `candidate_snapshot` returns a
detached value, and `commit_candidate` publishes once after later service
persistence. Stale, forged, cross-authority, or consumed tickets fail.
`discard_candidate` leaves committed state unchanged. Integer normalization
allows actual JSON restoration with identical semantic state and deduplication.
Thresholds 0/100/300/700/1500 project five drill/cosmetic/preview tiers and no
additional attack bonus. Overflow and malformed restore fail atomically.

## Verification

Missing implementation RED logs:

- Forge: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.AkwVMa`.
- Build: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.g715t6`.
- Proficiency: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.CTpzUj`.

Final focused GREEN on Godot 4.6.1:

- `tools/run_tests.sh --filter forge_runtime`, 1/1,
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.XvnSle`.
- `tools/run_tests.sh --filter build_library`, 1/1,
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.MgnvX7`.
- `tools/run_tests.sh --filter weapon_proficiency_runtime`, 1/1,
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.TzPCsF`.

Final engine logs contain no errors, script failures, or leaked objects. The
proficiency regression commits 4,200 unique actions, exceeds the previous
4,096-history risk, and verifies serialized history growth remains below
thirty-two characters. Its fixed fields and monotonically bounded counters
permit further progression without accumulating source lists.
Draft 2020-12 schema self-validation and `git diff --check` also passed.
This Godot build cannot collect line coverage.

Independent read-only review of all four domain scripts and three scene tests
found no blocking issue. It confirmed isolated candidate costs, bounded build
slots, reserved command refusal, atomic malformed restoration, and owner-bound
proficiency tickets. Durable native session allocation remains an integration
requirement rather than an authority reset at each launch.

## Remaining integration gates

The profile service must persist forge/build candidates before publication and
route only trusted native receipts to proficiency. Its eventual profile
composition/migration must store the proficiency snapshot and update the
existing proficiency mirrors in the same durable transaction. Meta schema-1
files were not modified at this domain boundary.

Native training, action source production, drills, Hub controls, save-write
failure compensation, real Player application, preference preview routing,
controller/visual QA, and clean checkout export are pending. This is a domain
verification claim, not complete Task 4 training or complete P16 certification.
