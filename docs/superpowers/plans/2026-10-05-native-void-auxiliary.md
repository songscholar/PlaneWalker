# Native Void Auxiliary Implementation Plan

- Status: Active
- Document Role: Current implementation plan
- Authority Level: Execution details below approved P15 specification
- Applies To: Void Throne authored auxiliary attacks, status receipts, native pickup resources and cold recovery
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual native auxiliary mechanics, accepted-frame compensation, strict cold recovery, physical saves and raster/normal-input checks pass without script errors or leaks.

## Approved Scope

Execute the remaining P15 section7.5 mechanics using independent deterministic
auxiliary state and existing native Player, Health, semantic, projectile and
frame authorities. P3healing is consumed permanently even if the Player is dead
when it resolves; it never revives or heals after later external revival.

## Execution

- [x] Define meaningful failing domain and native tests before implementation.
- [x] Retain closed, reconstructible finite burn, slow, damage-output debuff,
  delayed burst, landing/follow-up and pickup receipts.
- [x] Relocate actual Void Step to committed safe landing; independently warn
  the follow-up28frames and validate room clearance.
- [x] Apply scepter2/30 burn180frames, bolt0.65slow120frames, grasp0.40slow90frames,
  tentacle30frame exposure and devour0.85damage-output180frames through actual
  source-owned native boundaries without removing inventory or time abilities.
- [x] Execute tear final25/r32 burst after its own40frame warning; actual vortex
  capped32pull and inner24/40once reuse the verified transactional pull boundary.
- [x] Create at mostfour native pickup constructs TTL180 granting5energy once
  through authenticated Player resource receipts; keep outside reward roster.
- [ ] Author room-relative half-arena Void End and finiteTTL300 zones; retain
  opposite48px safe route and core-break denial/enrage interruption.
- [x] Verify late refusal/retry, phase/death cleanup, Save/Replay codecs,
  fresh native reconstruction, normal inputs and three-resolution raster evidence.
- [ ] Retain independent modules and shared integration in coordinated precise
  local commits; update milestone evidence and document index.
