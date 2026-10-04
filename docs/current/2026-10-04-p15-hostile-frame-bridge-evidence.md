# P15 Hostile Frame Bridge Evidence

- Status: Current / Focused GREEN
- Document Role: Native Player/hostile fixed-frame integration evidence
- Authority Level: Evidence below the approved P15 execution design
- Applies To: Player fixed-frame transactions, native Sentinel, Health observations, hostile effect authority, actor retirement
- Owner: Project integration lead
- Last Verified: 2026-10-04
- Implementation Status: Focused integration and regression gates pass; complete P15 actor/handler/content certification remains pending
- Exit Gate: Reproducible full P15 native content, lifecycle, replay, Save, interaction, and export certification

## Implemented Boundary

`HostileFrameBridge` captures native actor and frozen Health checkpoints before Player weapon/world updates. Native hostile candidates observe the Player's post-movement position. Actor candidates, effect candidates, enemy Health observations, and Player sibling publications are prepared and finalized before World commits. Checkpoints retire only after that irreversible commit; accepted observations publish once.

Rejected frames restore actor transforms, Health/ledgers, controls, elemental state, weapon metadata, threat registry, Player mastery/action state, and ordered Replay facts. Health retains each original HP transition and exposes its observation context only while staging or publishing the matching hit. Internal Player staging avoids replaying the same fact during the deferred public hit callback.

The character coordinator accepts an optional mastery observation sink. Player buffers mastery and weapon-hit observations during its fixed-frame transaction, discards them on refusal, and publishes them after the frame seals. Existing coordinator callers retain synchronous publication by default. An unexpected hostile seal failure after irreversible World acceptance stops the Player and preserves accepted clocks; it does not run ordinary compensation against an irreversible World frame.

Terminal actors leave the active bridge roster at seal. Their detached Health batch still publishes their final death receipt exactly once. Native corpse presentation lasts 0.2 seconds before freeing. Idle `register_actor` accepts a next-wave actor only with unique identity and matching run/frame; a live actor cannot be silently retired. Full roster rebinding is available through idle configuration.

## Executable Evidence

`tests/integration/combat/hostile_frame_bridge_test.tscn` verifies:

- Frame-start checkpoints compensate weapon hits and time-stop controls after effect commit refusal.
- Two same-frame native Health hits preserve HP transitions 80 to 70 and 70 to 60.
- A real thirty-frame charged Sword action stages both Replay facts and settles one mastery family claim before public observations.
- Late World refusal restores exact Player/actor snapshots and removes staged facts; retry publishes both hits and the mastery once.
- Same-frame lethal damage prepares terminal cancellation and publishes one final-death receipt.
- A freed corpse cannot block subsequent Player frames; a next native wave joins the current authoritative clock.
- The production Sentinel/effect authority applies one twelve-damage logical sweep to the actual Player, with exact registry/Health compensation and same-frame retry.
- Altered frame tickets cannot consume compensation, and injected irreversible seal failure never calls ordinary rollback.

Latest focused bridge GREEN logs: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.PGN0y8`.

Regression GREEN logs:

- Weapon mastery, 2/2: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.WnjVcI`.
- Replay, 11/11: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.0P1JXK`.
- Transaction suites, 5/5: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.E8QVjg`.

These runners reported no script failures or unknown leaks. Godot line coverage is unavailable in this engine build; scene assertions are executable behavior evidence, not line-coverage evidence. The injected World/seal failure diagnostics are intentional assertions.

## Remaining Certification

Only the native Sentinel melee handler is integrated by this focused gate. Other P15 actors/handlers, room encounter activation, native telegraph rendering, physical weapon payload replay against these actors, room Save restoration, full native content matrices, controller/visual QA, and reproducible native builds require their own complete gates. A tracked Bow projectile probe exposed an existing live-payload rollback/fact limitation; it is not counted as covered by the charged Sword/Health staging gate.
