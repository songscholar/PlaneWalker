# Plane Walker Pixel Asset Pipeline

- Status: Active / Authorized
- Document Role: Current production asset redraw specification
- Authority Level: Below `AGENTS.md` and the full product completion design
- Applies To: Characters, enemies, bosses, weapons, projectiles, effects, items, icons, rooms and environment atlases
- Owner: Plane Walker integration lead
- Depends On: `docs/5_6_UI美术音效技术设计.md`, `docs/superpowers/specs/2026-10-06-native-ui-finish-design.md`
- Last Verified: 2026-10-06
- Exit Gate: Every shipping raster reference is authenticated, visually reviewed, nearest-filtered, localized where applicable and covered by a runtime screenshot or scene contract

## Intent

The current production raster library is functionally complete but visually
uneven. Several assets read as generator placeholders when viewed together:
silhouettes are too similar, outlines are inconsistent, and effects, weapons
and environment tiles do not share a clear pixel grammar. This specification
defines a replacement pipeline without changing gameplay identities, scene
paths, animation state names or content contracts.

## Visual Direction

Plane Walker uses a modern pixel-ruins language: hard-edged silhouettes,
weathered stone and patinated metal, restrained time-energy accents and strong
readability at the 640x360 logical canvas. Assets are authored on integer grids
and imported with nearest filtering. The base palette is ink `#111619`, stone
`#242d2d`, stone edge `#697771`, bone `#edf0dc`, muted `#abb8ac`, patina
`#79baa1`, time `#61d5e7`, brass `#e5bd69`, danger `#f07065`, ember `#df9b65`
and void `#b897d7`. Each family may add two local shades and one highlight, but
no family may become a hue-only recolor of another.

## Asset Rules

- Characters use 48x48 frames and six states: idle, move, attack, cast, hurt and death.
- Bosses use 80x80 frames with the same state set and a distinct silhouette, weapon or mechanism.
- Ordinary enemies and summons use 48x48 or 64x64 frames according to body plan; spatial hazards use authored 32x32 or 48x48 tiles.
- Weapons use 32x32 icon art plus authored projectile and impact frames where the runtime exposes them.
- Time abilities and active items use 24x24 or 32x32 icons with a readable internal glyph and a semantic accent.
- Rooms, doors, walls and constructs keep their existing scene dimensions and atlas regions. Redraws may improve border detail, depth bands and landmark readability, never collision geometry.
- Effects use short, deterministic frame strips or pooled particles. Every effect has a readable start, active and retire state and must not introduce unbounded nodes.
- UI art and gameplay art share palette tokens, but UI frames remain separate from world textures so accessibility scaling and nearest filtering stay stable.
- No asset is accepted when the only difference from another identity is hue, border or a single pixel.

## Production Workflow

1. Inventory every raster reference in `assets/production`, every atlas region in content manifests and every scene texture path.
2. Create a family recipe with silhouette masks, palette roles, frame count, anchor point and semantic identity.
3. Use image generation only for style exploration or a key visual reference when the image tool is available. Final shipping sprites are normalized into deterministic project recipes so regeneration is offline and byte-stable.
   Optional local GLB/FBX/Blender sources use `tools/production_art/source_model_pipeline.py` and `tools/production_art/SOURCE_MODELS.md`. Tripo and Mixamo source records stay pending until an actual file and applicable rights record are available. A local cube fixture proves import/render mechanics only. Model renders keep `technical_preview` status until native-scale art and gameplay inspection pass; they never automatically overwrite the shipping library.
4. Generate atlases and contact sheets with the existing Pillow toolchain. Record source kind, license, dimensions, nearest-filter policy and SHA-256 in a manifest.
5. Run contract checks for declared identities, bounds, alpha, meaningful frame differences, unique normalized silhouettes, deterministic regeneration and undeclared-file rejection.
6. Import in a clean Godot profile, scan strict runtime logs, then capture representative scenes at 640x360, 1280x720, 1920x1080 and 3440x1440 in both locales.
7. Replace a batch only after its focused scene and screenshot evidence pass. Preserve old assets until the new batch is authenticated and referenced.

## Batch Order

1. Player characters and five Bosses, because they dominate the first combat read.
2. Launch enemies, summons and spatial hazards, grouped by silhouette and threat role.
3. Five weapons, projectiles, hit effects and four time abilities.
4. Active items, blessings, curses, talents, reward icons and Hub/codex art.
5. Five room families, doors, walls, constructs, landmarks and floor-specific overlays.
6. Final UI frame sheets, portraits, mode art, replay and platform status icons.

Each batch produces a focused evidence document and updates `docs/README.md`.
The batch status must distinguish generated, integrated, visually inspected and
fully certified. Unredrawn legacy assets remain explicitly listed until their
batch passes.

## Quality Gates

- Source paths and content IDs remain unchanged unless a migration is recorded.
- Every atlas has a manifest hash and a license/provenance entry.
- Every required frame has non-zero alpha inside the safe bounds and at least three distinct frames per animated state.
- A normalized silhouette comparison rejects palette swaps and duplicate shapes.
- Nearest filtering and integer alignment are asserted by scene tests.
- Runtime logs contain no script errors, object leaks or missing texture warnings.
- Screenshots show readable character/enemy separation, effect timing, HUD contrast and no clipping at supported resolutions.
- Asset regeneration from a clean checkout produces identical bytes.

## Explicit Boundaries

This work changes raster resources, atlas manifests, import metadata, preview
tools and presentation references. It does not change combat damage, enemy
AI, save schemas, replay schemas, collision shapes, content eligibility or
online services. Human playtesting remains a separate final gate.
