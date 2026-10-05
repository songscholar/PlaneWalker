# P15B Native Ruin Debris Evidence

- Status: Retained native integration; full Boss arena certification remains open
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below the approved P15 specification and arena implementation plan
- Applies To: Authored Ruin barrage landing, debris collision, shared construct budget, accepted frame compensation and cold continuation
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05

## Retained Behavior

- The actual P2 `guardian_debris_barrage` completes its forty-frame warning before reserving six real projectiles. Flying projectiles never create ground obstacles prematurely.
- Authored projectile world contact, target contact or flight expiry records an explicit landing receipt. Each receipt retains the original projectile definition, generation, hit lane and landing frame. Restore validation checks the reservation claim, trajectory and physically possible speed budget.
- Each admitted debris body has HP20, radius12 and a full480-frame lifetime. Six landings create at most four active bodies; additional reservations remain pending without spending lifetime.
- Debris placement uses a stable16px grid. The conservative grid retains48px perimeter and central crossing corridors; active debris surfaces remain48px apart. Occupancy includes current and prepared Boss bodies, Player bodies, existing covers/walls and actual native room physics queried with60px clearance envelopes.
- Newly admitted positions are checked again before commit and publication. A physical obstacle moved into a sealed landing rejects publication, and the same accepted frame can retry after full compensation.
- Covers, walls and active debris share eight construct slots. Four surviving covers plus four debris defer a warned wall pair. Breaking two real covers admits the original wall decision on frame256 with wall age0.
- Real authenticated Player weapon Hurtbox collisions reduce only debris HP, reject duplicate identities and retire the physical collider. Refused frames restore state, claims, work ownership and the collider under its stable identity. Node instances may be reconstructed during compensation.
- Actual Encounter work retains active and pending debris under bounded64-character `debris_` work identities. Candidate weapon destruction stays prior active work until its frame is accepted. Accepted destruction retires old work before admitting a pending replacement. Actual Boss death retires both active and pending debris without orphaned room work.
- Debris targets have no enemy/Boss group, counted death signal, separate Health component or independent reward.
- A live debris authority cannot reconfigure into another run while retaining colliders. Independent review found this lifecycle guard gap; the final regression verifies rejection and exact retained state.

## Explicit Payload Compatibility

- Payload configuration remains exact schema1. A new authored barrage recipe explicitly upgrades the payload state to schema2, adding `arena_debris` and `debris_impacts`.
- Exact historical schema1 projectile definitions retain their original flight and landing behavior. Restore does not silently introduce debris into an old recording.
- Schema2 validates exact root, recipe, domain and receipt fields. Incomplete schema2, unknown fields and an unnormalized schema downgrade reject.
- No content descriptor or fingerprint was changed to represent native completion. The runtime selects authored debris behavior through the Boss's prepared mechanism parameters.
- The native Driver additionally requires all debris owners and recipe projectiles to belong to declared Ruin spawns and rejects future damage claims at a cold accepted boundary.

## Executable Evidence

The meaningful initial native RED was `planewalker-tests.70XDqH`: the actual authored barrage lacked the required schema upgrade and debris bodies. Later fixture repair runs and transient parser failures are excluded from accepted evidence.

- Final native integration: `./tools/run_tests.sh --filter ruin_debris_native --timeout 120`, GREEN `planewalker-tests.RHiZq7`,1/1. Includes actual barrage, collision/expiry receipts, physical room obstacle clearance, late geometry rejection, frame rollback/retry, schema1/2 compatibility, live reconfiguration refusal, fresh native Boss/effects/Encounter cold reconstruction, shared wall capacity, real damage and terminal work retirement.
- Fresh current cold continuation compares original and isolated native Boss, effects, threats and Encounter states at every accepted frame191 through200. This is a focused actual Actor/effect/Encounter gate, not whole production Host certification.
- Payload regression: GREEN `planewalker-tests.0qjoRs`,1/1.
- Encounter frame authority regression: GREEN `planewalker-tests.ckJPnZ`,1/1.
- Native wall regression: GREEN `planewalker-tests.nsRv5f`,1/1.
- Native cover/aftershock/enrage regression: GREEN `planewalker-tests.Aw7MdC`,1/1. The final implementation preserves existing covers-only fixtures that intentionally have no room binding.
- Native combat checkpoint regression: GREEN `planewalker-tests.7oK0im`,1/1. This existing gate does not contain a live debris Host checkpoint.
- Hostile frame bridge regression: GREEN `planewalker-tests.pk8Mxi`,1/1.
- Semantic native effects regression: GREEN `planewalker-tests.2Lgnka`,1/1.
- Native OpenGL execution with `PLANEWALKER_CAPTURE_NATIVE=1` passes; log: `build/test-logs/p15b-native-debris/engine.log`. Screenshots: `build/visual-evidence/p15b-native-arena/ruin-debris-intact-640x360.png` and `ruin-debris-intact-1280x720.png`. Both pass raster color/pixel checks and visual inspection.
- Accepted final logs have no script errors, deferred errors or known leaks. Ordinary scene tests report `godot_line_coverage_unsupported`; no line-coverage percentage is claimed.

## Artwork And Limits

- Debris reuses frame2 of the original CC0 Ruin cover raster. It adds no third-party asset, font, dependency or generated media license obligation.
- Five-weapon debris certification, combined arena placement at all angles, actual whole Host current/historical debris checkpoints, complete750 loadout/Boss matrix and content-pack native actor/art declarations remain separate open gates.
- Forest, Time response, Forge and Void native arena work remains open in the implementation plan. This document does not mark the full P15 milestone complete.
