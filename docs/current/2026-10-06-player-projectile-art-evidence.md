# Player Projectile Raster Integration

- Status: Focused native and raster checks passed; final product certification pending
- Document Role: Current player projectile presentation evidence
- Authority Level: Execution evidence below the full completion scope
- Applies To: Arrow, gun bullet and four staff element visual projections
- Owner: Project integration lead
- Depends On: [Content and Player effect evidence](2026-10-06-content-vfx-art-integration-evidence.md)
- Last Verified: 2026-10-06

## Runtime Behavior

The three actual projectile scenes now use Sprite2D Visual nodes with
authenticated 32x32 four-frame production atlases. Arrow and bullet select
their fixed identity. Staff projects its existing arcane/fire/ice/lightning
element field; unknown elements hide the image. The art is authored in the
deterministic UI generator, uses the shared palette and binary alpha, and
is included in the same CC0 dedication and asset inventory.

The raster script only updates texture, frame and visibility. It caches
textures after checking size, filter and source SHA. Reduced motion selects
the first frame and follows the existing GameState setting signal. Native
arrow/bullet completion retains ownership of Visual visibility, so an
animation update cannot reveal a completed flight.

Arrow/bullet visual references now accept CanvasItem. Hit radii remain
5/4/9.6 for arrow/bullet/staff, respectively; collision masks, damage,
movement, range, targets and execution snapshots remain unchanged.

## Executed Checks

| Evidence | Result |
| --- | --- |
| `build/player-projectile-art-red` | All three scenes failed the missing raster consumption check |
| `build/player-projectile-pixels-red.log` | Missing projectile asset batch retained RED |
| `build/player-projectile-pixels-green.log` | Six Python art contracts passed, including exact generation, frame variation, palette and binary alpha |
| `build/player-projectile-art-green` | Actual native scenes select all six identities, preserve execution snapshots and honor completed visibility/reduced motion |
| `build/player-projectile-native-regressions` | Eight scenes passed, including native overlaps, swept same-frame targets and terminal contacts |
| `build/player-arrow-art-regression` | Existing arrow reward/flight contract passed |
| `build/player-projectile-launch-regressions` | Five native player/profile integration scenes passed |
| `build/player-art-final-presentation` | All nine current presentation scenes passed strict paired-log validation, including the four time abilities and projectile projection |
| `build/player-projectiles-import.{stdout,engine}.log` | Editor import passed strict paired-log validation |
| `build/player-projectile-room-render.{stdout,engine}.log` | Four phases and reduced motion match opaque PNG pixels over an actual production room |

The rendered fixture instantiates the real projectile scenes with processing
disabled while projecting visual time. Complete domain snapshots remain
equal across capture. Dynamic flight and hit behavior is checked by the
separate native regressions above. Screenshots are retained under
`build/visual-evidence/player-projectiles/`; their display scale is 2x.

## Remaining Gates

These focused tests do not certify the final source checkout, combined
coverage, 750-case gameplay matrix, sustained FPS, 45-minute soak or final
distributable builds. Full UI and other presentation work remain active.
External source models and real-world Shenzhen playtesting are not claimed.
