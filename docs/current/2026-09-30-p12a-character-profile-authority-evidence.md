# Plane Walker P12A Character Profile Authority Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P12A character-profile content, ingestion, loadout-policy, and validation evidence below the approved five-character design
- Applies To: Six milestone-aware character runtime profiles, five Launch characters, fifteen Talent identities, ContentRegistry resolution, canonical 150-loadout policy, schema validation, localization, manifest integrity, and CI reproducibility
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-30-plane-walker-p12-five-characters-design.md`, `docs/superpowers/plans/2026-09-30-plane-walker-p12-five-characters.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-30
- Evidence Status: Verified Locally
- Worktree Base HEAD: `3057c7c`
- Implementation Certification Commit: `61eaae6`
- Rollback Point: `3057c7c`

## Completion decision

P12A is locally complete at implementation commit `61eaae6`. The Base Pack now contains six exact, milestone-aware `character_runtime_profile` definitions: the frozen M1 Wanderer route, the Launch Wanderer route, and one Launch route for Time Guardian, Void Walker, Primordial Knight, and Time Lord. ContentRegistry resolves exactly one eligible profile per character and milestone, validates all cross-references before activation, and returns deep-copied profile authority to RunLoadoutPolicy.

Launch and Expansion each accept exactly:

```text
5 characters × 5 weapons × 6 canonical unordered time pairs = 150 loadouts
```

The serialized order is `stop < rewind < rift < accelerate`. All reversed duplicates are rejected, preventing a second 150-row ordered-slot space. M1/CURRENT/NEXT remain isolated to `wanderer_m1_v1`; no Launch character payload, Talent scope, stats, skill, resource, mastery, or presentation definition leaks into those milestones.

This certification closes content and policy authority only. It does not claim that the five complete character gameplay runtimes, character HUD, character animation/feedback, Replay schema 4, 150-loadout runtime smoke matrix, or 4500 synthetic samples already exist. Those remain in P12B–P12H.

## Profile and Talent authority

`character_runtime_profile_v1.schema.json` and `CharacterRuntimeProfile` require every v1 field explicitly. IDs use the project-wide 64-character limit. Handler parameter dictionaries are closed by handler, require exact v1 keys and values, reject unknown or non-finite payloads, enforce recursion limits, and fail closed on unsupported handler names or Profile versions.

The M1 compatibility profile requires zero/empty `none` payloads for its Resource, Character Skill, Mastery, and Time Interaction fields. This prevents hidden Launch behavior from being stored behind a nominal `none` handler.

The Base Pack contains exactly fifteen character Talent identities:

- three frozen Wanderer Talent identities, available across every milestone where a Wanderer profile references them;
- twelve Launch/Expansion character-scoped identities, exactly three for each non-Wanderer character.

Every referenced Talent must exist, use category `talent`, cover every required profile milestone, and declare exactly one `compatibility.character_ids` value equal to the owning character. Missing, mismatched, unrestricted, or overscoped Talent records reject the pack during ingestion. The twelve new Talent effects remain intentionally inactive until P12 Task 5 installs their typed runtime modifiers; P12A certifies their stable identities, localization, ownership, and availability rather than pretending their later mechanics are already complete.

Frozen authoritative file hashes are:

```text
character_runtime_profiles.json  c1d148fee2a0ab2d79efc14aeb684c3ea4b2e6954b830a75cc8dee14058bc3ff
talents.json                    0a70cb7c8b2aa9a1144f606a05e350b681a0e53d86ef6fa49e7e1a81ef3b6c8b
characters.json                 8fd8aef62d60112cc0db8600e76e7c9ba9f9a1cbbfec7a1d007a834413ce8f3a
base translations.csv           968e199a4331e251442589608965a27485e04f33b7c0959d9e227091c52bc8f8
```

All ten Base Pack manifest integrity hashes match their current file bytes.

## Frozen Content Pack v2 compatibility

P12A extends the frozen Content Pack v2 category catalog without silently redefining its generic compatibility grammar. The generic v2 schema continues to accept the previously valid empty compatibility arrays, `archetype_ids`, `modes`, and positive Profile versions needed by other categories. Character-profile-specific schema and Registry semantics then reject empty weapon/time constraints, unsupported `archetype_ids` or `modes`, wrong categories, missing IDs, and milestone widening for `character_runtime_profile` entries.

This split preserves existing Mod/DLC envelope compatibility while making the new character category fail closed. Real temporary-pack tests cover missing references, wrong categories, availability widening, malformed compatibility, missing character back-references, wrong Profile versions, missing Talent scope, mismatched Talent scope, and correct-plus-extra Talent overscope.

## Reproducible validation dependencies

The Draft 2020-12 schema contract uses `jsonschema==4.23.0`, pinned in `requirements-dev.txt`. The unified local gate fails fast with the exact installation command when the dependency is unavailable; it never installs from the network during validation. CI provisions pinned Python 3.12 through a commit-pinned `actions/setup-python` action, installs the same dependency manifest, and then calls the repository's single validation entry point.

This keeps local and CI schema behavior aligned without requiring an undeclared globally installed Python package.

## Complete repository gate

The final local `./tools/validate_project.sh` run passed:

- documentation governance: `30 / 30`, zero violations;
- character-profile Draft 2020-12 schema contracts: `9 / 9`;
- localization: `8 / 8`;
- playtest data contracts: `13 / 13`;
- M1 release contracts: `27 / 27`;
- GDScript coverage contracts: `5 / 5`;
- export contracts: `37 / 37` in contract mode;
- bootstrap import and clean second import;
- Godot scene suite: `115 / 115`;
- project validation: `PASS`.

Retained validation log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.XDYuFR
```

The only registered scene-suite warning is the existing `tests/reward_system_smoke.tscn` ObjectDB leak. The import path also retains the approved sandbox diagnostics for global Godot editor settings and the macOS CA store. No new parser error, runtime error, RID leak, orphan-node warning, or unregistered ObjectDB warning was found. `git diff --check` passes.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- No automated test, deterministic matrix, synthetic simulation, or agent review is represented as human experience evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.
- Export validation remains contract-only; installed templates, distributable packages, packaged startup, signing, credentials, remote push, store configuration, and publication are not certified here.
- The twelve new Launch Talent identities have no active effects until P12 Task 5 installs and certifies their typed runtime modifiers.

## Next local program

P12 Task 2A is the active implementation slice. It installs immutable `DamageInfo` and `DamageResolution`, true zero-damage prevention for Sword perfect guard, a monotonic irreversible HP ledger, authoritative run identity, and prepare/commit/rollback Gameplay Rewind. The execution plan is split into three focused commits so immutable damage, irreversible HP claims, and rollback-safe Rewind can each be independently rejected or retained without weakening the completed P12A authority.
