# Native Enemy Spatial Mechanisms Implementation Plan

- Status: Implemented; shared certification pending
- Document Role: Current
- Authority Level: Execution details below approved P15
- Applies To: Bramble Mage and Web Weaver walls, Web Weaver links, Plane Ripper portals
- Owner: Native enemy spatial implementation lead
- Depends On: `AGENTS.md`, `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Real species casts, physical interactions, accepted-frame compensation, finite retirement, current/historical cold reconstruction and raster presentation pass.

**Goal:** Execute every authored ordinary/elite wall, link and portal cast without rejecting the native combat frame.

**Architecture:** A pure spatial runtime stores authenticated construct identities, frozen geometry, HP, lifetime and portal transit claims. The existing semantic authority owns its transaction snapshot and physical projections. Native weapon callbacks settle construct damage through the domain; semantic frame settlement applies link statuses and collision-safe transit with compensation.

**Tech Stack:** Godot 4.6.1, GDScript, accepted 60 Hz frames, original project raster assets.

## Constraints

- Preserve all declared warning durations and stable source/generation identities.
- Three wall segments retain a 32px passage; safe activation may defer and rewarn rather than overlap a body.
- HP30/TTL240 Bramble walls and HP25/TTL360 Web walls are separate destructible targets without enemy rewards.
- Web links use HP15/TTL480, at most three owned links, ATK1.15/speed1.10 strongest-only and 35f collision warning.
- Plane portals use one pair/TTL720, endpoints at least96px apart, 12f per-actor transit cooldown, 48px safe arrival clearance and team-specific presentation.
- Owner death retires walls and links; portal collapse has its own45f warning before20damage/r32.
- Every rejected frame restores physical bodies, target positions, modifiers, HP, claims and work records.
- Exact historical semantic schema1 migrates to empty spatial state; current state rejects missing and unknown fields.

## Task 1: Real Cast Regression

- [x] Add `tests/integration/combat/native_enemy_spatial_test.gd` and scene with actual authored Bramble Mage, Web Weaver and Plane Ripper actors.
- [x] Execute all five real warnings through native Actor and Effects transactions; assert the complete warning is harmless and active frame is admitted.
- [x] Retain rejected wall/link/portal RED in `build/native-enemy-spatial-red2` and focused GREEN3/3 in `build/native-enemy-spatial-final`.

## Task 2: Domain And Native Interaction

- [x] Create `scripts/enemies/launch/enemy_spatial_runtime.gd` with strict state, authenticated reservations, damage claims, shared8construct cap, owned caps and finite lifetimes.
- [x] Create `scripts/enemies/launch/launch_enemy_spatial_construct.gd` with physical wall body/Hurtbox, destructible link Hurtbox and portal raster projection.
- [x] Extend `launch_semantic_effect_authority.gd` with schema2 spatial state, handler dispatch, projection matching, compensated positions and link modifiers.
- [x] Extend the Effects normalizer to normalize exact historical semantic state before whole-checkpoint comparison.
- [x] Verify all five real weapon input producers against both wall and link targets, duplicate claim rejection, physical wall movement blocking, link buff removal and safe portal transit/cooldown.

## Task 3: Recovery And Retention

- [x] Inject late-frame portal refusal and prove exact position, claims, owner and Player compensation/retry; restore exact wall HP/claims and projection.
- [x] Physically encode Save and typed Replay, reconstruct fresh native authorities and compare live next-frame settlement; restore exact historical semantic schema1.
- [x] Generate five original raster atlases with CC0 provenance and inspect640x360,1280x720,2560x1080 native captures.
- [x] Finish focused shared Semantic2/2, Void1/1 and Summon4/4 regressions; scan logs for errors/leaks. Production Host checkpoint has a separately owned content-migration startup fix under validation.
- [x] Retain precise source ownership and indexed evidence with executable results and remaining full-run/matrix limits; local retention commit follows verification.

## Reversible Decisions

The original canonical wall action freezes three rays at its caster. Spatial
reservation creates a target-centered U with three48px segments and a48px open
passage. Its separate physical projection completes the authored50/55frame
collision warning before any segment becomes solid, preserving historical action
digests while avoiding activation on the caster. Unsafe or over-budget segments
defer and restart a complete collision warning. Link geometry follows recipients
only at accepted frames. Portal transit occurs after whole-frame checkpoints and
before actor preparation so rejected frames restore physical positions and claims.

Focused current evidence is [Native Enemy Spatial Evidence](../../current/2026-10-05-native-enemy-spatial-evidence.md).
