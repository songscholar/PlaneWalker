# Native Hound And Phase Mechanisms

- Status: In Progress
- Document Role: Current
- Authority Level: Implementation plan below approved P15 specification
- Applies To: Eternal Hound dormant sigil and Phase Ranger shift
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 design](../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md)
- Exit Gate: Actual weapon ingress, rollback, cold reconstruction, historical migration and focused native regressions pass with local retention commits.

## Architecture

The Hound's existing species runtime owns once-only dormancy, sigil HP and
duplicate claims. A derived Actor-owned native construct supplies the physical
Hurtbox and raster presentation. Player weapon authentication precedes every
sigil mutation; terminal sigil destruction settles the original parent's Health
and final-death signal through the ordinary damage publication boundary. The
construct is neither another counted body nor a reward source. Shared Effects
budget accounting includes live sigils.

Phase Ranger uses a separate deterministic species shift module. The Actor owns
its accepted clock, sealed candidate sequence and native arrival cue. Existing
room bounds, occupancy and relocation checks approve its at-most-80px landing.
The shift retains a marked departure and thirty vulnerable nonattacking recovery
frames, with a 180-frame cooldown. Historical snapshots migrate explicitly to
disabled shift state and retain their prior continuation. Current snapshots
strictly validate sealed reservation receipts.

## Executable Tasks

- [x] Hound RED: real Health lethal enters dormancy but initially had no physical sigil. Added authenticated hits, duplicate refusal, final parent death, 300-frame recovery, complete-frame rollback and typed cold recovery tests.
- [x] Hound implementation: `launch_hound_sigil.gd`, narrow Actor hooks, normal five-weapon targeting and foreign construct accounting; content and pack fingerprints preserved.
- [x] Hound GREEN: integration, physical checkpoint, complete enemy and native summon regressions; see [retained Hound evidence](../../current/2026-10-05-native-hound-sigil-evidence.md).
- [ ] Phase RED: current native Ranger has no shift clock or relocation. Add deterministic reservation, safe/blocked landing, Stop/Rift, recovery vulnerability, rollback, cold and historical migration cases.
- [ ] Phase implementation: independent shift state, Actor frame hooks, sealed migration and native raster cue. Do not alter frozen authored content.
- [ ] Phase GREEN: focused shift and teleport regression, real weapon ingress and physical checkpoint. Retain evidence and focused commit.
