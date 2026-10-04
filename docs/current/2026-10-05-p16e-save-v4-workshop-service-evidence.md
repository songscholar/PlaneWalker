# Plane Walker P16E Save V4 and Durable Workshop Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Opt-in Save/Profile and workshop service contracts
- Applies To: MetaProfileCompatibility, Save v4 migration, ProfileRuntimeService workshop commands and focused tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16c-settlement-service-evidence.md`, `docs/current/2026-10-04-p16d-forge-build-proficiency-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused Save and workshop persistence; production Main activation and combined checkout certification pending

## Save V4 Boundary

SaveService enables Profile schema 4 explicitly with an authoritative Meta
catalog. Default callers and global settings retain schema 3. ProfileRuntimeService
enables the strict profile path during configuration. A caller without that
catalog rejects version 4 as a forward version.

The declared v3-to-v4 migration authenticates the original envelope before
normalizing it. Versions 1 and 2 follow each adjacent step. The pre-envelope
legacy wrapper retains its existing v0-to-v3 import, then enters version 4
through create_profile. The exact raw v3 source survives in backup_1 after
physical migration. Caller-owned source dictionaries remain unchanged.

Legacy currency, unlocks, partial proficiency and affinity maps, statistics,
achievement first_return and character-scoped default cosmetics are preserved.
The node alias node_guard_1 maps explicitly to W-01. Declared legacy achievement
and cosmetic identities live in data/content/meta_legacy_references.json;
unknown identities refuse. Fresh baseline ownership merges Wanderer, Sword and
Bow without dropping earlier unlocks. Nested authority and compatibility
mirrors must agree. Mutual element and time/Void enchantment exclusions also
apply to restored profiles, rather than only to commands.

An existing active run receives a frozen no-benefit projection. Later upgrades
cannot replace that projection. The unchanged active run is a positive save
control; a forged benefit fails specifically with profile_run_mismatch. A live
launch must match its receipt/configuration/projection, and a retained settled
terminal must match its reason and terminal phase. Projection digest keys use
ordinary JSON strings, avoiding native StringName serialization rejection.

## Durable Workshop Boundary

enable_workshop validates the twenty authored forge definitions and the build
producer. The closed execute entry point routes meta_unlock, forge_upgrade,
enchant_preference, void_temper, build_save and build_remove to their exact
domain producer. A returned candidate enters the existing owner-bound Profile
ticket transaction. No public caller can directly publish candidate state.

Forge levels, currency, preferences, fixed acquisition markers and build slots
write together in one validated v4 envelope before live publication. Failed
pre-promotion writes leave all live fields unchanged. Retry commits once.
Ambiguous post-promotion failures reconcile only the exact durable primary.
Stale services refuse to overwrite newer persisted state. Build resolution
rechecks current unlocks; preference recall after physical restart does not
spend acquisition currency again.

## Verification and Retention

Meaningful RED evidence: planewalker-tests.q1yG86 exposed missing legacy
identities and the invalid positive active-run control; Mkr7f8 exposed all four
mutually exclusive preference pairs. EJAEnq identified the native projection
StringName key. The earlier forged-projection refusal without its positive
control was not valid evidence for the intended boundary. Workshop missing-API
RED: planewalker-tests.hnINct.

Save group GREEN: planewalker-tests.bXiuQc, 10/10 scenes including workshop.
Progression group GREEN:
planewalker-tests.DxLEAT, 9/9 scenes. Physical workshop GREEN:
planewalker-tests.5iCo6b, 1/1 scene. No script failures or leaked objects were
reported. Godot line coverage remains unsupported.

The companion closed JSON Schema contracts passed 11/11 Python tests, including
native-emitted fresh and active-run envelopes. Independent read-only review
found no blocking issue in migration authentication, mirrored state, frozen
projection matching or workshop publication ordering. Documentation governance
and git diff --check passed.

These are focused native domain and physical JSON results. They do not certify
Main activation, real weapon proficiency receipt production, native training,
Player Meta effects, Hub controls, ending resume, content activation, all hostile
kits, combined export or packaged startup. The later combined revision remains
an independent check. No external publication is claimed.
