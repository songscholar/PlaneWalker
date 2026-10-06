# Held Weapon Raster Artwork

- Status: Focused native and rendered checks passed
- Document Role: Current equipped weapon projection evidence
- Authority Level: Local execution evidence below full-product completion scope
- Applies To: Sword, bow, gun, gauntlets and four staff elements
- Owner: Project integration lead
- Depends On: [Player Projectile Artwork](2026-10-06-player-projectile-art-evidence.md)
- Last Verified: 2026-10-06

Eight independently authored 32x32 weapon families now replace the procedural
equipped weapon bodies. Each 128x32 atlas contains four distinct phase poses,
uses the shared palette and binary alpha, and has a SHA-256 inventory entry
and CC0 provenance. Source scripts reproduce the shipped PNG bytes.

The production Player proxy selects equipment and staff element from the copied
weapon presentation snapshot. Ready, anticipation, active and recovery phases
select their corresponding poses. Reduced motion holds the ready pose. Unknown
equipment, unknown phases, unavailable snapshots and death suppress the weapon
sprite. Screen pixels stay unscaled along cardinal facing directions. Existing
challenge tint, hit flash, reload timing and resource/zone feedback remain.
The integration does not write gameplay, action, time or replay state.

| Evidence | Result |
| --- | --- |
| `build/held-weapon-native-red` | All eight equipment identities/phases and five actual Player entries failed missing raster consumption before integration |
| `tests.contract.presentation.test_held_weapon_art_assets` | Two contracts passed: identity, dimensions, alpha, palette, distinct poses, SHA inventory and reproducible PNG bytes |
| `build/held-weapon-native-green` | Eight identities, six mapped phases, reduced motion, unknown identity rejection and five actual Player snapshots passed |
| `build/held-weapon-presentation-regressions` | All eleven presentation scenes passed on the stable test runner with strict per-scene logs |
| `build/held-weapon-pixel-pipeline-green` | Native catalog/import and complete asset pipeline contract passed |
| `build/held-weapon-room-render-fixed.{stdout,engine}.log` | Unoccluded source pixels, four phase poses, reduced motion and unchanged actual Player snapshots passed in the production room |

The room capture's top row uses eight presentation fixtures to expose all
equipment/element phases. Its lower row contains five actual equipped Player
nodes with their native ready snapshots. It does not claim a complete native
weapon combat sequence. At the active phase, production attack effects naturally
occlude weapon pixels; the first direct source comparison failed for this
reason. Those original logs remain under `build/held-weapon-room-render.*.log`.
The corrected capture checks every opaque weapon source pixel with the effect
temporarily hidden, then restores effects and retains the complete composition.
Both views are saved under `build/visual-evidence/held-weapons/` and inspected
at native resolution. The strict paired log validation passes.

This closes the focused held-weapon artwork slice. Final committed-source
gameplay/UI certification, performance, soak, exports and human feedback remain
open. Human feedback remains 0/20.
