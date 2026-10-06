# Player Zone Raster Artwork

- Status: Focused native and rendered checks passed
- Document Role: Current Player spatial effect projection evidence
- Authority Level: Local execution evidence below full-product completion scope
- Applies To: Nine staff zone/combination identities, four gauntlets zones and two device glyphs
- Owner: Project integration lead
- Depends On: [Held Weapon Raster Artwork](2026-10-06-held-weapon-art-evidence.md)
- Last Verified: 2026-10-06

Thirteen original 64x64, four-frame atlases replace the Staff zone's generic
translucent polygon and add the previously absent gauntlets zone presentation.
The shared palette, binary alpha, distinct identity/poses, SHA-256 inventory,
CC0 provenance and byte-exact source reproduction are retained. Two original
32x32 keyboard/mouse and controller glyphs extend the settings artwork catalog.
Device header consumption belongs to the UI finishing lane.

`PlayerZoneAtlasProjection` reads the native owner's execution mode, parameters
and accepted frame without advancing or modifying them. Its sparse ring and
identity glyph use the actual authored world radius, with nearest filtering.
Chain combinations use every frozen absolute origin. Reverse steam switches
from the actual freeze radius to explosion radius at its declared delay.
Unknown identities, invalid geometry, inactive or retired owners hide the art.
Reduced motion fixes the pose, and cold-restored zones resume their accepted
execution phase. The existing damage, collision, timing, status and result
contracts are unchanged.

| Evidence | Result |
| --- | --- |
| `build/player-zone-art-red.log` | Two missing-family asset assertions failed before production |
| `build/player-zone-native-red` | All thirteen actual native zone identities failed missing raster assertions before integration |
| `build/player-zone-and-device-art-green.log` | Eight source art contracts passed, including new family integrity/reproduction and complete command set |
| `build/player-zone-art-family-regressions.log` | Nine challenge, held-weapon, narrative and zone art contracts passed |
| `build/player-zone-art-import.{stdout,engine}.log` | Native editor import passed strict paired log validation |
| `build/player-zone-native-green` | Thirteen native identities, exact radii, chain origins, execution-clock poses, reduced motion, reset, unknown identity rejection and two cold restores passed |
| `build/player-zone-room-render.{stdout,engine}.log` | All opaque source pixel samples and full native snapshots passed over the production room |
| `build/player-zone-staff-regressions` | Eight Staff damage, status, Boss, profile, replay and Time scene contracts passed |
| `build/player-zone-gauntlets-regressions` | Seven gauntlets execution, Boss, profile, replay and combo scene contracts passed |
| `build/player-zone-presentation-regressions` | All twelve presentation scenes passed with strict paired logs |
| `build/player-zone-pixel-pipeline-fixed-green` | Complete inventory, imports, dimensions, hashes and font/catalog checks passed |

The initial catalog run correctly rejected the omitted 64x64 zone-family size
registration. Its failures remain at `build/player-zone-pixel-pipeline-green`;
the explicit family size registration and the independent expected-size
contract were corrected before the later passing run.

Room screenshots are retained at `build/visual-evidence/player-zones/`. They
use actual configured Staff/Gauntlets zone nodes and an actual equipped Player
on a frozen presentation stage. Four accepted clock phases are inspected for
persistent/delayed zones. The one-frame Steam explosion captures its initial
native pose only; the implementation follows its existing retirement and does
not extend native damage lifetime. Unoccluded captures check every opaque source
pixel, then the Player is restored for the full floor composition. This verifies
projection, not an unassisted combat sequence or a completed-action visual soak.

Source previews underwent two visual refinement passes; room compositions
were inspected at native resolution. Radius scaling preserves native gameplay
geometry and is not restricted to an integer screen magnification. No isolated
frame budget or final clean-checkout claim is made. Full UI/gameplay validation,
performance, exports and human feedback remain open; human feedback is 0/20.
