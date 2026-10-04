# P17A Actor Atlases Design

- Status: Approved
- Document Role: Current focused production raster design
- Authority Level: Project implementation design below AGENTS.md
- Applies To: Five character and five boss animation atlases and deterministic asset validation
- Owner: Project pixel presentation lane
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-wave-4c-pixel-feedback-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Ten original nonblank atlases reproduce exactly, obey frame contracts, and render in Godot

## Decision

Extend the existing locally authored pixel raster pipeline. Five characters use
48x48 cells; five bosses use 80x80 cells. Each atlas has four columns and six
rows: idle, move, attack, cast, hurt, death. All art faces right and consumers
may mirror in presentation. Logical frame timing stays independent of gameplay
state. Character silhouettes, costume details and boss structures are distinct;
palette swapping alone is insufficient.

An alternative is to keep programmatic PixelProxy drawing as the sole final
presentation. That preserves feedback but leaves no inspectable authored atlas.
External image generation would require another asset source and cleanup to
guarantee transparent, aligned pixel frames. Deterministic original rasters fit
the existing toolchain and can be replaced asset by asset.

## Boundaries

Create only new tools, tests, assets and documentation in this step. Do not edit
the strongly typed Player Visual, base pack manifest, compatibility ledger or
Meta catalog. The generator produces a sorted manifest with dimensions, frame
states, per-file SHA-256 and original-project provenance. PNGs have hard pixel
edges and transparent padding; no downloaded media or external rights are used.

Validation reads actual PNGs with Pillow, verifies every frame is visible and
differs during animation, checks cell edge transparency, rejects missing,
modified or undeclared files, and checks silhouette uniqueness across actors.
Checked-in PNGs remain usable in Godot without the optional generator library.

## Runtime Follow-Up

Attach presentation-only Sprite2D resources to existing actor projection nodes.
Keep gameplay collisions, snapshots, action frames, save compatibility and
weapon cue consumption intact. Preserve the existing proxy as a fallback and
for weapon VFX, character aura, accessibility and afterimages. A later focused
runtime test must verify actual rendering and neutral gameplay snapshots before
this library is described as a completed gameplay presentation milestone.
