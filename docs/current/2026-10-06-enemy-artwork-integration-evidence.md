# Enemy Artwork Integration Evidence

- Status: Focused Verified / Current
- Document Role: Current enemy artwork and model-source pipeline retention evidence
- Authority Level: Below AGENTS.md and the pixel asset pipeline specification
- Applies To: All 22 launch enemies, phase atlas bindings and optional local model ingestion
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/specs/2026-10-06-pixel-asset-pipeline-design.md`
- Last Verified: 2026-10-06
- Certification Status: Focused contracts and native raster checks passed; final gameplay, visual, performance and export certification pending

## Artwork and Runtime Binding

All 22 enemy atlases now use the shared 31-color modern-ruins palette. The
redraw adds metal bevels, stone plates and cracks, cloth folds, wing veins,
joint details, book markings, mechanical limbs and crystal facets. Selected
attack phases now change sword position, claw reach, bowstring draw, spell orb
size and titan arm height. The four phase cells remain 48x48 in a 192x48 row,
with binary alpha, consistent pixel density and four distinct phases.

The four early scenes for shattered sentinel, corrosive moth, stone-shell
strider and ruins wraith previously referenced old 32px textures. They now
reference the production library used by the other 18 scenes. Scene geometry,
health, motion and authored collision radii are retained. Base pack integrity
hashes authenticate the changed scene resources; the UI inventory records the
updated enemy atlas hashes.

## Source Models

Commit `49e7e18` extends the local GLB/FBX pipeline to ordinary enemies. The
generated catalog contains five characters, five Bosses and 22 enemies, with
every external source explicitly `awaiting_model`. A selected ready source can
build while unrelated catalog entries remain pending. Enemy and actor output
families require separate manifests, and provenance records selected IDs and
the original manifest hash.

The source-model contracts passed 13/13 with the three opt-in Blender tests
enabled, including real GLB and FBX rendering for both atlas families and
single-enemy builds against a partially pending catalog. The retained log is
`build/source-enemy-model-contract.log`. The local cube fixture remains a
technical preview; no Tripo model or Mixamo animation was acquired.

## Focused Validation

- Enemy palette contract initially failed for all 22 atlases; the regenerated library passes.
- Enemy visibility, padding, phase uniqueness, exact regeneration and palette contracts: 3/3 passed in `build/enemy-art-refresh-contract.log`.
- Python presentation discovery: 30 tests, 27 passed and three opt-in tests skipped, in `build/enemy-refresh-presentation-contract.log`. The opt-in source-model tests passed separately as described above.
- All 22 actual scene instances resolve the production texture, 48px cells, four phases, nearest filtering and retained collision radius in `build/enemy-refresh-binding-green`.
- Updated pixel catalog hashes pass the Godot pipeline scene in `build/enemy-refresh-pixel-green`.
- Native rendered previews cover four biome backgrounds and four phases. Every opaque source pixel matches the captured Godot raster within 0.005 RGB tolerance. Strict paired logs pass in `build/enemy-refresh-capture-2.stdout.log` and `build/enemy-refresh-capture-2.engine.log`.

The first binding test also exposed three pre-existing scene radii that differ
from their eventual runtime definitions; the test was corrected to retain
authored geometry rather than changing combat during an art update. A later
binding run passed assertions but failed strict logs while new UI translations
had not yet been imported. The clean focused result above follows that import.

## Visual Review and Limits

The contact sheet was inspected before and after two drawing passes. Sixteen
native previews are retained under `build/visual-evidence/enemy-refresh`. Native
scale review confirms distinct silhouettes, readable material planes and no
clipped phase poses over the actual room textures. These static posed previews
do not certify gameplay timing, controller flow, sustained frame rate or player
feedback. Full candidate certification and the Shenzhen playtest remain open.

Reproduction uses `generate_enemy_atlases.py`, `generate_ui_asset_slice.py` and
the rendered `capture_enemy_atlases.tscn` tool. The original source-model tool
and preceding actor/font changes are recoverable at `a1c9822`, `46c76a0` and
`49e7e18`; this enemy integration is retained in its own focused commit.
