# P17A Actor Atlas Evidence

- Status: Approved / Current
- Document Role: Focused original raster library evidence
- Authority Level: Verification evidence below P17A
- Applies To: Ten actor animation atlases, provenance and deterministic native loading
- Owner: Project pixel presentation lane
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p17a-actor-atlases-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p17a-actor-atlases.md`
- Last Verified: 2026-10-05
- Implementation Status: Asset library and native gallery verified; gameplay projection remains the next focused task
- Exit Gate: Ten original nonblank atlases reproduce exactly and render all 240 cells in actual Godot

## Delivered

`assets/production/actors/manifest.json` declares five characters (48x48 cells)
and five bosses (80x80 cells). Every actor has four frames for each of idle,
move, attack, cast, hurt and death. PNGs have transparent padding, hard edges,
distinct silhouettes and right-facing presentation. Equipped character weapons
are drawn by the existing live weapon cue layer; atlas artwork does not bake in
a sword independent of the actual loadout.

`tools/production_art/generate_actor_atlases.py` reproduces every checked-in byte,
including the contact sheet and manifest, with pinned Pillow 12.3.0. The library
uses original project raster source and CC0 artwork provenance in LICENSE.txt.
There are no downloaded media, private credentials or external asset purchases.

## Verification

- Missing generator RED: focused Python suite failed with ModuleNotFoundError before implementation.
- Focused Python suite: 4/4 GREEN. It checks complete identity/action coverage, visible frames, three or more distinct frames per action, transparent padding, unique silhouette alpha, hashes and fresh byte reproduction. Missing/corrupt/undeclared files, unsafe paths and a blank PNG with an updated matching manifest hash are refused.
- `python3 tools/production_art/generate_actor_atlases.py --check`: GREEN, read-only validation.
- Godot native gallery: `planewalker-tests.Eb4O9U`, 1/1 GREEN, no script errors or leaks. Native PNG decoding verifies all 240 cells are visible and actual imported dimensions match the manifest.
- Actual OpenGL 640x360 gallery: `/private/tmp/plane-walker-p17a-native-gallery.log`, clean PASS. Import `/private/tmp/plane-walker-p17a-import.log` is also clean.
- Inspected `assets/production/actors/contact_sheet.png` and `build/visual-evidence/p17a-actor-atlases/attack.png`. All ten silhouettes are nonblank, fit their cells and have visible costume or structural differences.
- `python3 -m pip_audit --disable-pip --no-deps -r requirements-production-art.txt`: no known vulnerabilities; public advisory lookup used narrow network access after sandbox DNS refusal. Optional tooling only; checked-in runtime PNGs do not require Pillow.

## Limits And Rollback

This commit adds an independently usable resource library and test gallery.
It does not claim all Launch enemies, room bitmap environments, soundtracks or
five-boss native gameplay presentation are finished. Base pack manifest,
compatibility ledger, Meta state, typed Player Visual and combat domain data are
untouched. Root owns consolidated documentation indexing and retention review.
Each asset can be replaced without changing gameplay state; no push or public
publication is performed.
