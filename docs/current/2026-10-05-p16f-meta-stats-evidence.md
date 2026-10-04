# Plane Walker P16F Permanent Stats Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Pure permanent stat preparation
- Applies To: MetaStatsApplicator, native Stats compatibility, and loadout matrix tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-04-p16a-profile-domain-evidence.md`, `docs/current/2026-10-05-p16e-save-v4-workshop-service-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Pure domain verified; Player integration and combined checkout certification pending

## Delivered Boundary

`MetaStatsApplicator.prepare(character_profile, character_bonuses, weapon_id, projection, catalog)` parses the supplied full character definition with the existing `CharacterRuntimeProfile`, authenticates the frozen Meta projection against its catalog, and enforces the existing character/Meta/forge combined budget. The caller supplies the character identity selected through the authoritative content pipeline. This domain does not replace that selection boundary.

Every call derives from authored base stats. HP, attack, defense, movement speed, and attack speed multiply the character permanent percentage and Meta percentage once; attack then multiplies only the selected weapon's forge percentage. Permanent `speed` maps to the native Stats `move_speed` field. Critical values and time-energy values retain their authored base. Final totals pass the actual `Stats.apply_profile` validation and are returned as a detached Stats-compatible snapshot.

The three context fields are `stats`, `entrance_healing`, and `void_reduction`. The last two are policy ratios rather than executed effects. The domain has no Player, Health, Save, or publication side effects. Absent a native character-level source, callers use an empty character-bonus dictionary. Existing run talents and reward handlers retain their application order; the Wanderer talent's fixed twenty HP is not added a second time.

Invalid definitions, missing catalogs, unknown weapons, excess character percentages, Boolean/nonfinite bonuses, rehashed contradictory projections, unknown fields, and excess forge percentages refuse without clamping or mutating input. Repeated calls return the same totals and cannot compound benefits.

## Verification

Meaningful missing-implementation RED: `build/test-logs/p16-meta-stats-domain-red`. An earlier test parse failure caused by using Godot's builtin `Projection` as a constant name was corrected before this domain RED and is not counted as feature evidence.

`TEST_LOG_DIR=build/test-logs/p16-meta-stats-green ./tools/run_tests.sh --filter meta_stats_applicator_test --timeout 30` passes one native scene. It reads the actual Launch character catalog and exercises five characters, five weapons, and six time pairs at both fresh and complete permanent tiers: 150 unique loadouts, 300 stat preparations. Every total enters the real Stats resource. Additional cases verify exact capped character multiplication, nonzero defense, weapon-specific forging, unchanged time capacity, absence of duplicate talent HP, JSON restoration, detached results, repeat determinism, and corrupt-input refusal.

No script failures or engine object leaks occur in GREEN logs. The known macOS sandbox certificate diagnostic is classified by the existing runner. Godot line coverage is unsupported; the loadout count does not imply a coverage percentage. Independent read-only review found no blocking issue in projection authentication, stat mapping, selected-weapon forging, or alias isolation.

## Remaining Integration

Player configuration must apply these totals once from the authored base, preserve run reward/talent effects through their existing handlers, and execute entrance healing and Void mitigation at their proper native boundaries. The domain tests do not certify these integration paths, Main activation, replay/save restoration of applied effects, real player experience, or distributable exports.
