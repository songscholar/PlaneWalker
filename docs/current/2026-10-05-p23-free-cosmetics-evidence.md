# P23 Free Cosmetic Collection Evidence

- Status: Focused Verified / Combined certification pending
- Document Role: Current milestone retention evidence
- Authority Level: Below the P23 free cosmetic specification
- Applies To: Authored appearances, durable claims and equipment, native gallery and Player projection
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p23-free-cosmetics-design.md`, `../superpowers/plans/2026-10-05-p23-free-cosmetics-plan.md`
- Last Verified: 2026-10-05
- Exit Gate: Strict authored catalog, physical Save faults and reload, native controls, raster provenance and Player independence pass

## Retained Behavior

Five characters each have an original, first-return and first-victory appearance.
The latter ten are free claims requiring durable character ownership and actual
Profile finished-run or victory statistics. All fifteen atlases are deterministic
original CC0 raster assets with six native animation states. Their catalog,
localization, license and SHA-256 digests are sealed into the Base pack.

The specialized `cosmetic_definition` discriminator and independently versioned
`cosmetic_collection_v1` payload preserve the frozen generic content-entry and
Meta Profile contracts. A missing collection retains the original appearance.
Claims and equipment consume actual Profile revisions and bounded command IDs.
They use the existing physical Save compare-exchange and promotion transaction.
Before-promotion failures publish nothing; post-promotion failures reconcile
only an authenticated actual primary. A competing collection writer at the same
Meta revision refuses instead of overwriting the durable extension.

Physical Save validation rejects unknown IDs, unclaimed or cross-character
equipment, forged progress, malformed collections and collections in pre-v4
saves. Active native runs block cosmetic changes. Cosmetic projection preserves
the exact Player, Health, weapon, time, replay and World snapshot.

The native Hub gallery preserves discovered items and provides fifteen actual
bitmap previews plus claim/equip controls. Keyboard and controller paths retain
failed-write retry, focus, return and retired-callback protection. Actual Main
launch and checkpoint resume apply durable equipment after character setup.
Both Chinese and English gallery rows fit at 640x360 and 1280x720.

## Verification

- Catalog/API RED: `build/test-logs/p23-cosmetics/initial-red/`, originally
  `planewalker-tests.9fVkeq`.
- Catalog, actual physical Save and all fifteen native appearance projections
  GREEN: `build/test-logs/p23-cosmetics/initial-green/`, originally
  `planewalker-tests.0t7wcv`, 3/3 scenes.
- Actual Main gallery, keyboard/controller input, cold Profile, second-character
  gateway launch and exact checkpoint resume GREEN:
  `build/test-logs/p23-cosmetics/native-main-green/`, originally
  `planewalker-tests.mtidN1`.
- Final cosmetic catalog, physical Profile, native Main and presentation suite
  GREEN: `build/test-logs/p23-cosmetics/final-focused/`, 4/4 scenes.
- Cosmetic/narrative/tutorial/workshop physical Profile regression GREEN:
  `build/test-logs/p23-cosmetics/profile-regression/`, 4/4 scenes.
- Production actor and Player atlas regression GREEN in
  `build/test-logs/p23-cosmetics/atlas-regression/`. The broader production filter
  was 7/8; its only failure exposed the missing cosmetic-content compatibility
  ledger transition described below.
- Cosmetic/Profile JSON-schema and raster contract tests pass. Deterministic
  generation check: `python3 tools/production_art/generate_cosmetic_atlases.py
  --check`, PASS. Native import also passes.
- OpenGL native Main tests at 640x360 and 1280x720 and actual five-character
  projection test pass. Gallery preview framebuffer checks find at least eight
  colors. The gallery screenshots and all five actual equipped sprites were
  visually inspected; logs and images are retained under
  `build/test-logs/p23-cosmetics/visual/` with no script/resource/leak diagnostics.
- Pinned development, coverage and production-art dependency advisory lookup
  reports no known vulnerabilities. No dependency was added.

## Remaining Certification

The actual Base pack fingerprint transition now retains eight authentic committed
descriptor proofs and seven exact reviewed transitions. The new cosmetic edge
admits only the twenty declared cosmetic files; existing Meta state and required
Profile v4 rules remain unchanged. `node tools/save/validate_actual_content_compatibility.mjs`
passes and the physical migration/fault suite passes in
`build/test-evidence/cosmetic-ledger/`. The strict ledger remains closed to unknown
targets, changed existing resources and unreviewed additions.
The combined checkout still requires full validation, instrumented coverage,
release export and packaged startup. This focused evidence certifies cosmetic
behavior and does not claim those combined release gates or human playtesting.
