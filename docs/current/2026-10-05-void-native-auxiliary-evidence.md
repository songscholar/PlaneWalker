# Void Native Auxiliary Evidence

- Status: Focused Verified
- Document Role: Current implementation evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Void Throne finite auxiliary status, burst, vortex and shard pickup mechanisms
- Owner: Native Boss implementation lead
- Last Verified: 2026-10-05
- Depends On: `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `2026-10-05-void-auxiliary-domain-step-evidence.md`

## Retained Behavior

Actual authenticated Scepter Health loss installs a source-owned burn with six
2-damage ticks at30-frame intervals through180frames. Actual Bolt and Grasp
Health loss apply movement multipliers0.65for120frames and0.40for90frames.
Actual Devour applies damage-output0.85for180frames through the Player's real
weapon attack boundary. Exclusive status expiry, phase transitions, terminal
Boss death and room disposal remove only owned modifiers. Disposal also works
after the original Boss node has been released. Item, weapon and time ability
ownership remain intact.

Enemy semantic zones and Void status sources use their strongest slow once,
with a0.40hostile floor. Other floor-rule multipliers retain their prior
independent behavior. This fixes the native0.65x0.50overlap becoming0.325when
the authoritative domain calls for0.50.

Tear creates an actual radius32endpoint burst with its own40-frame warning,
then deals25Void damage on one frame. Its endpoint remains the originally
committed line endpoint. Vortex projects a32px/sec capped pull, a radius24
inner contact dealing40once, and expires after120frames. Ordinary outward
Player movement overcomes its pull. Tentacle opens exactly30accepted frames
of core exposure.

Shard Projection materializes at most four radius8native pickups using the
retained compatible CC0core atlas. Pickups are outside the reward roster,
expire after180frames and grant up to5time energy through an authenticated
real Player resource receipt. Full energy consumes the pickup with a zero
gain receipt. No false energy-change signal is emitted. Overlapping edge
pickups admit one receipt per Player per frame, allowing the next pickup on
the next accepted frame without competing resource revisions.

## Transaction And Recovery Evidence

- Native late refusal restores exact Boss receipts, native pickup nodes,
  Player status modifiers, resource value and resource revision; retry claims
  the same frame once.
- Actual `Player.advance_action_frame` with the real hostile bridge and an
  injected late World rejection restores the complete Player Replay snapshot,
  Boss snapshot and Effects claims. No energy signal escapes the refusal.
- Fresh physical `SaveService` reads typed Replay data containing the native
  Boss, Effects, Player resource and modifiers. A fresh World2D, Boss, Player
  and Effects authority reconstruct identical finite state and actual Player
  modifiers. New test storage is isolated per scene.
- Normal Stop input remains usable during the actual pickup encounter and
  continues accepted Player frames without changing loadout ownership.

## Executed Checks

| Check | Evidence | Result |
|---|---|---|
| Actual pickup baseline RED/GREEN | `build/void-pickup-native-red`, `build/void-pickup-native-green` | Native nodes/resource receipt added;1/1GREEN |
| Pickup transactions and edge overlap | `build/void-pickup-transactions-red`, `build/void-pickup-transactions-green2` | Meaningful resource-signal RED;1/1GREEN |
| Status, Tear, Vortex, phase and exposure | `build/void-aux-lifecycle-red`, `build/void-aux-lifecycle-green` | Phase cleanup RED;1/1GREEN |
| Physical Save/Replay reconstruction | `build/void-aux-physical-green` |1/1GREEN |
| Actual Player outer transaction | `build/void-player-frame-green` |1/1GREEN |
| Strongest native hostile slow | `build/void-hostile-slow-red`, `build/void-hostile-slow-green` |0.325vs0.50RED;1/1GREEN |
| Freed source and shared semantic regression | `build/void-semantic-fixed-regression` |2/2GREEN;no script errors/leaks |
| Released Void source cleanup | `build/void-released-owner-red`, `build/void-released-owner-green` | Stale native output RED;1/1GREEN |
| Broader Void regression before final disposal/slow refinements | `build/void-native-final-regression` |15/15GREEN |
| Native OpenGL/Metal raster plus continued Player input | `build/void-player-native-raster4.log` |PASS;640x360,1280x720,2560x1080 |

The actual Player rejection cases intentionally emit the established
`Fixed-frame event buffer settlement rejected runtime frame89` diagnostic.
The successful native raster log contains this injected refusal andPASS;
there are no script errors, unexpected refusals or leak diagnostics.

Raster artifacts are in
`build/visual-evidence/void-arena/native-shard-pickups-<resolution>.png`.
The640x360and2560x1080captures were inspected: formal tile art, cyan pickups,
Boss, Player and debris cover remain visible. Each surviving pickup passes
a nonblank region pixel check. Shared-World2D capture avoids reparenting live
bodies and preserves native collision exceptions while gameplay continues.

## Remaining Gates

Room-relative Void End/enrage half-arena geometry and its historical cold
normalization are coordinated separately. This evidence certifies the
auxiliary mechanisms above; it does not close the whole P15milestone or the
remaining time-response, roster, presentation and full-product gates.
Shared Actor/Effects/Semantic integration is retained in the coordinated
native-combat commit. Local rollback uses the focused commit boundaries;
there is no remote push or external publication.
