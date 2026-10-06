# Pixel Production Integration Evidence

- Status: Focused Verified / Current
- Document Role: Current asset production and offline integration retention evidence
- Authority Level: Below AGENTS.md and the pixel asset pipeline specification
- Applies To: Actor artwork, cosmetic variants, bundled fonts and UI raster catalog
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/specs/2026-10-06-pixel-asset-pipeline-design.md`
- Last Verified: 2026-10-06
- Certification Status: Focused tests passed; final visual, controller, performance and export certification pending

## Implemented Assets

The five player and five Boss atlases keep their original IDs, paths, 48/80px
cells, four columns and six animation states. The redraw adds articulated arms,
cloth folds, metal facets, weathered armor, root details and mechanical ribs.
The shared modern-ruins palette is recorded and authenticated in the actor
manifest. The validator refuses nonbinary alpha and undeclared palette colors.
All fifteen cosmetic variants are regenerated from the same updated body source.
Cosmetic IDs, unlock routes and gameplay effects are unchanged; asset hashes in
the content catalog and Base pack are updated by the existing generator.

The nine-slice chrome panel, button and focus sheets have a uniform center and
four-pixel borders. They are stretchable control artwork rather than enlarged
icon art. The catalog now resolves existing world atlas paths relative to the
production root and includes all twenty-two launch enemy sheets.

## Bundled Fonts

The immutable Google Fonts CDN regular-weight files are stored with complete
SIL OFL 1.1 licenses in `assets/production/fonts`. These are static weight 400
resources; they are not the variable binaries inspected in the earlier UI
preparation audit. Their distinct hashes and source URLs are recorded accurately
in the font manifest. The license hashes match the earlier official-source audit.

| Font | Bytes | SHA-256 | Character Coverage |
| --- | ---: | --- | --- |
| Noto Sans SC Regular | 10,540,644 | `450625c8d46ab3df97b7904ded955ec2746d17ec76740cb1e91d1ba63a0f89af` | 30,890 mapped codepoints, Chinese body text |
| Pixelify Sans Regular | 49,840 | `616f3be4921e2e79ad58fc15fcfd0b3c3508a615811b1a518130d623030764e9` | 574 mapped codepoints, Latin display text |

CoreText and fontTools 4.60.1 independently identify the expected families,
versions, copyright records and OFL URLs. Godot loads both bundled resources;
the focused scene asserts Latin coverage and Noto Chinese time/space glyphs.
The raster inventory no longer claims a system-font fallback as a shipped font.

## Focused Validation

- Python presentation discovery: 23 tests, 21 passed and 2 opt-in Blender tests skipped in this command.
- Cosmetic content contracts: 3/3 passed after the atlas and Base pack hashes changed.
- Actor palette, padding, state diversity, SHA-256, exact regeneration and malformed-asset rejection: 6/6 passed.
- Nine-slice center/alpha contract: 1/1 passed.
- Godot presentation scenes: 7/7 passed with strict paired stdout/engine log validation in `build/actor-refresh-presentation-tests`.
- Expanded Godot pixel asset pipeline scene: passed with strict logs in `build/actor-font-validation-2-stdout.log` and `build/actor-font-validation-2-engine.log`.
- The production-art dependency audit has no known vulnerabilities.

The uninstrumented presentation command honestly reports coverage unavailable;
these scene passes do not establish line coverage. The full instrumented suite,
immutable final candidate, 750 native cases, sustained recording/frame budget,
complete UI visual/input matrix and retained distributable builds remain gates.

## Model Sources and Remaining Review

The local source-model tool has a separate GLB/FBX smoke test and preserves
technical previews in `build/`. No Tripo model or Mixamo animation has been
obtained in this milestone. External source files and applicable rights records
remain pending. The cube fixture is an import/render test, not game artwork.

The contact sheet was inspected before and after the redraw, and articulated
attack frames were inspected at integer display scale. These reviews are not a
substitute for final in-game art acceptance or real player feedback. The artwork
and font changes are reversible through their focused Git commit.
