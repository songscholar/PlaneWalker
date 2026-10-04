# P15D Native Semantic Effects Implementation Plan

- Status: In Progress / Current
- Document Role: Current focused native semantic effect implementation plan
- Authority Level: Below P15 hostile specification
- Applies To: Native healing, bounded zones, status sources, delayed hazards and room lifecycle
- Owner: Project owner
- Depends On: `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual Health, native projections, registry facts and compensating rollback match authored effects; unimplemented handlers remain fail-closed

## Transaction Foundation

- [x] Define an authority that authenticates sealed native Actor batches and prepares without mutation.
- [x] Reject forged tickets and strict snapshot corruption; restore state, native projections and status sources on rollback.
- [x] Support capped healing, independent Blink geometry, native zones, restoration, independently warned explosions and paired Boss self-rewind.
- [x] Verify native competing healers charge only actual missing HP and publish one buffered Health observation.
- [x] Preserve pending zone decisions when global or owner budgets are full; admit only after accounting for all surviving hazards.
- [x] Extend fixed-frame controls with strongest attack/speed buffs and strongest attack debuff while preserving the default modifier contract.

## Remaining Production Mechanics

- [ ] Verify all native zone damage, strongest-only slowdown, safe owner immunity and finite TTL under the integrated Router.
- [ ] Record only observed accepted-frame HP history and verify Priest native healing and cap expiry.
- [ ] Execute final-death effects, residual pools, elemental pattern swaps and declared elite affixes.
- [ ] Provide actual destructible sigils, walls, links, safe portals and nonreward summons through tested authorities.
- [ ] Verify full twenty-two native enemy kits and five Boss arenas, checkpoint recovery, replay and whole-room completion.

This plan certifies individual tested mechanics as they land. It does not infer production completion from content definition or domain-only coverage.
