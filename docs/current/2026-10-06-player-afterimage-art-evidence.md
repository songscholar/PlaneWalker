# Player Raster Afterimages

- Status: Focused native and rendered checks passed
- Document Role: Current Player afterimage projection evidence
- Authority Level: Local execution evidence below full-product completion scope
- Applies To: Five native Player identities and their dash afterimages
- Owner: Project integration lead
- Depends On: [Player effect artwork](2026-10-06-content-vfx-art-integration-evidence.md)
- Last Verified: 2026-10-06

Player afterimages now capture the actual selected ActorAtlas texture, frame,
facing, offset and tint in an independent Sprite2D. The original geometry
fallback remains for actors without an accepted raster source. The snapshot
stays fixed while the source Player moves or changes pose. Existing lifetime,
alpha fade, screen footprint, camera compensation, pixel snapping and reduced
motion suppression are preserved. No actor/domain references are stored in
the copied sprite and no gameplay/replay writes are added.

| Evidence | Result |
| --- | --- |
| `build/player-afterimage-art-red` | All five native Players failed missing raster consumption assertions |
| `build/player-afterimage-art-green` | All five native identities preserve texture/pose/facing and full native snapshots; fade, pixel drift and reduced motion checks passed |
| `build/player-afterimage-feedback-regression` | Existing camera, footprint and combat feedback regression passed strict logs |
| `build/player-afterimage-room-render-fixed.{stdout,engine}.log` | Five native Player source poses match tinted alpha blending against the real production room across three fade phases |

The first capture failed a fixture-only inferred Color type and was corrected;
its failing logs remain under `build/player-afterimage-room-render.*.log`.
The attempted ten-scene presentation regression had passing per-scene logs
but the runner was edited concurrently and emitted a shell syntax error. It
is not accepted as a complete passing suite; a stable-runner rerun is pending.

Actual images are retained under `build/visual-evidence/player-afterimages/`.
They verify frozen raster pose and blending, not sustained performance or the
final clean checkout. Full gameplay/UI suites, soak, exports and human
feedback remain open. Human feedback remains 0/20.
