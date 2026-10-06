# Native Mode Arena Framing Evidence

- Status: Focused native and rendered checks passed
- Document Role: Current mode presentation and camera evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Daily Boss, Boss Rush, Authored Challenges and Endless
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Implementation: `55738fd`

Mode arenas now own their active `Camera2D`, restore the previous camera on
exit, fit the logical 640x360 design to the current viewport, and add the
floor-specific bitmap room backdrop. Endless refreshes the route after native
room admission before the framing snapshot, and its backdrop follows room
transitions. Player and Boss atlas presentation is attached during admission
so the first visible frame does not rely on a delayed scan.

The changes are presentation-only. Player physics transforms, domain snapshots,
save state and replay state remain unchanged across every resize assertion.

`build/ui-mode-arena/native-target-headless` and
`build/ui-mode-arena/rendered-target` pass strict paired stdout/Godot log
validation. `tests/ui/mode_arena_framing_test.tscn` covers all four modes at
640x360, 1280x720, 1920x1080 and 3440x1440. The retained captures under
`build/ui-mode-arena-screenshots/` contain 16 nonblank images, one per mode and
resolution, and their PNG dimensions match the requested targets, including
3440x1440. A native bitmap backdrop covers the viewport side bands without
altering the logical arena.

This is a focused framing result. It does not certify the final 49-state UI
matrix, sustained 60 FPS, release signing, or human playtesting.
