# Native Five-Floor Room Artwork Evidence

- Status: Focused Verified / Current
- Document Role: Current native room raster retention evidence
- Authority Level: Below approved P14 and full-product specifications
- Applies To: Thirty templates, five floor palettes, seven categories, native binding and private replay
- Owner: Plane Walker integration lead
- Last Verified: 2026-10-05
- Depends On: `../../AGENTS.md`, `../superpowers/plans/2026-10-05-native-room-artwork.md`

## Retained Behavior

Sixteen original CC0 rasters provide five four-frame tile atlases, masonry,
doorways and seven category landmarks. The reproducible Pillow generator and
SHA-256 manifest remain beside the assets. Reproduction uses
`requirements-production-art.txt` (Pillow 12.3.0).

LaunchRoomScene binds the palette, landmark and deterministic 240-tile layout to
the authoritative floor, template and room seed. Tiles cover 640x360 exactly,
including the cropped final row. The successful binding hides the existing
placeholder layer; reset hides the former room identity. Rebinding replaces the
sprites instead of accumulating them. Physical anchors, floor-rule zones and
collision remain controlled by the existing native room contract.

The presentation helper is RefCounted and creates an unscripted Node2D. This
preserves RoomSceneContract's single scripted owner rule. A first Node2D helper
failed the actual production spawn gate; the corrected owner contract and real
production encounter spawn both pass. Private replay already uses the same
native room binding and now reconstructs the exact raster layout with gameplay
processing disabled.

## Verification

- Meaningful missing-raster RED: `build/test-evidence/native-room-artwork-red`.
- Final binding, reduced-motion, geometry, reset/rebind and private replay:
  `build/test-evidence/native-room-artwork-final-corrected`, 1/1.
- Existing P14 room presentation and room scene contract suites:
  `build/test-evidence/native-room-artwork-p14-regression`, 1/1, and
  `build/test-evidence/native-room-artwork-contracts`, 2/2.
- Corrected production spawn and fighting cold checkpoint:
  `build/native-summon-spawn-green`, 1/1, from the parallel integration worktree.
- Native OpenGL/Metal capture: `build/native-room-artwork-capture-pixels-final.log`.
  Nine representative rooms render at 640x360, 1280x720 and 2560x1080. Exact
  raster dimensions, camera scale and ultrawide centering pass. Opaque pixels
  from an interior tile, masonry, both doors and the category landmark match
  their actual source texture pixels within one channel byte at every size.
- All 27 screenshots are retained under `build/visual-evidence/native-rooms/`.
  Inspected examples include Forge 640x360, Forest 1280x720 and Void 2560x1080.
  Logs were scanned for script/resource errors and engine object leaks.

A previous whole-image color-count check incorrectly rejected the deliberately
limited Forge palette. Source-pixel checks replace that heuristic and test each
actual component independently.

## Remaining Gates

These are focused room-presentation fixtures. Full native combat, HUD overlap,
controller navigation, packaged visual walkthroughs and combined clean-source
certification remain separate product gates. Summon and Void auxiliary work
continue under their active plans. Formal M1 remains
`M1 Candidate - External Validation Pending`; authentic external playtests remain
0/20.
