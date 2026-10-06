# Narrative Raster Artwork

- Status: Focused source, import and rendered checks passed; UI consumption pending
- Document Role: Current narrative and command artwork evidence
- Authority Level: Local execution evidence below full-product completion scope
- Applies To: Eight NPC portraits, five ending scenes and fourteen additional command symbols
- Owner: Project integration lead
- Depends On: [Content artwork evidence](2026-10-06-content-vfx-art-integration-evidence.md), [UI finish design](../superpowers/specs/2026-10-06-native-ui-finish-design.md)
- Last Verified: 2026-10-06

## Source And Identity

The deterministic UI renderer now produces 64x64 four-frame portraits for
all eight authoritative narrative NPC IDs and 128x72 four-frame artwork for
all five ending IDs. The subjects follow the authored narrative: Council
speaker, heart seeker, boundary listener, planar merchant, Stonekeeper,
scarred mentor, war priest and fading Warden. Separate clothing, hair,
facial markings and artifacts distinguish the first frames. A second art
pass refined brows, beard, braid, cheek plates and fading armor edges after
native-scale review.

The endings depict heart reconstruction, a quiet void threshold, shared
gold/grey roads, released fragments and a renewed Hub doorway. No ending
eligibility, dialogue, reward or profile state changes. Four-frame variations
remain subtle and the first frame is independently readable.

Fourteen new symbols cover settings, bindings, restart, quit, build, import,
refresh, next, screenshot, account, storage, community, content and sharing.
They join the eight existing command symbols. All generated assets use the
shared palette, binary alpha, nearest filtering, declared dimensions and
SHA-256 inventory authentication. The existing original-art CC0 dedication
explicitly includes narrative and ending artwork.

## Executed Checks

| Evidence | Result |
| --- | --- |
| `build/narrative-art-red.log` | Three meaningful checks failed for missing narrative resources and command symbols |
| `build/narrative-art-green.log` | Three Python contracts passed: complete authoritative identities, distinct frames, source hashes, palette/alpha, independent command symbols and exact reproduction |
| `build/narrative-content-regression-green.log` | Six existing content/projectile art contracts passed |
| `build/narrative-art-catalog-green` | Godot catalog imports all declared frames at exact dimensions and validates hashes |
| `build/narrative-art-import.{stdout,engine}.log` | Editor import passed strict paired-log validation |
| `build/narrative-art-render.{stdout,engine}.log` | All opaque source pixels matched the actual Godot render in all four phases |

`assets/production/ui/narrative_contact_sheet.png` retains the focused first
frame review. Actual Godot captures are under
`build/visual-evidence/narrative-art/`. The capture uses imported sprites in
a native SubViewport; it verifies raster projection, not narrative UI flows.
The UI lane owns the real dialog/gallery bindings and interaction tests.

## Remaining Gates

Actual narrative UI consumption, the complete 49-state visual matrix,
final stable-source suites, performance, soak and distributable startup
remain separate gates. External Tripo/Mixamo source models are pending;
human feedback remains 0/20. This evidence does not certify the full game.
