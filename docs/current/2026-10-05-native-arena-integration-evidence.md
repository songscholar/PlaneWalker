# Native Arena Integration Evidence

- Status: Focused Verified / Combined certification pending
- Document Role: Current retention evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Forest, Void and Forge shared native Boss frame integration and replay
- Owner: Plane Walker integration lead
- Last Verified: 2026-10-05
- Depends On: [P15 design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md)

## Retained Integration

The shared Boss runtime owns the independent Forest auxiliary, Void arena and
Forge arena state. Native actors construct the matching colliders and raster
views, authenticate real Player weapon producers, and settle health changes
through the hostile frame transaction. Effects route flowers, drain healing,
Void P3 healing, Forge burns, ground pools and furnace pull through the same
prepared request and rollback boundary. Strict cold validation includes every
arena state and its frame, phase and terminal relationship.

Run replay projects Forest sacs, flowers, cages and erosion, Void pillars and
cores, and Forge anvils, vents and cooling pools from recorded domain state.
The projection preserves translated arena origins and authored atlas states.

Independent retained dependencies are Forest `fdf78ad`, Void `4a6f321` and
Forge `30d9f1f`. This shared retention makes their Actor/Runtime/Effects/Semantic
integration part of the committed source. The native Ruin Sword fixture now
belongs to the actual Player SwordWeapon producer.

## Verification

- Forest combined focused gate: `build/test-evidence/integrated-forest-retention`,6/6.
- Void domain and native gate: `build/test-evidence/void-domain-retention`,6/6.
- Void physical save and fresh cold reconstruction:
  `build/test-evidence/void-native-physical-save-final`,1/1.
- Forge domain/native, real five-weapon input and Boss regression gates are
  recorded in [Forge evidence](2026-10-05-p15-forge-native-evidence.md).
- Three-arena replay: `build/test-evidence/three-arena-replay-green`,1/1.
- Ruin normal production weapon inputs:
  `build/test-evidence/ruin-arena-normal-input`,1/1,all five weapons.
- Corrected authentic Sword fixture:
  `build/test-evidence/ruin-arena-owned-sword`,1/1.
- `git diff --check` passes. These are focused scene results, not line coverage.

The old clean-checkout validation certifies immutable `5eb4149`, which predates
these retained arenas. Its result cannot certify this integration. The next
committed-source run must include this milestone and all dependencies.

## Remaining Gates

Native summons, remaining elite affixes and species mechanisms, Void auxiliary
moves, complete gameplay/controller flows, full room artwork, actual instrumented
line coverage and retained release exports continue as separate gates. Void
healing never revives a dead Player, but a permanently consumed skipped receipt
after death is being added to prevent later delayed healing after revival.
Formal M1 remains `M1 Candidate — External Validation Pending`.
