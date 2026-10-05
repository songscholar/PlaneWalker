# Native Hound And Phase Mechanisms

- Status: Verified
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
- [x] Phase RED: native Ranger initially lacked a shift clock and relocation. Added deterministic reservation, safe/blocked landing, Stop/Rift, full recovery, rollback, cold and strict historical migration cases.
- [x] Phase implementation: independent species shift state, safe Actor frame hooks, exact historical normalization and native raster cue; frozen authored content unchanged.
- [x] Phase GREEN: focused shift/Teleporting/complete enemy regressions, actual natural Host physical checkpoint, normal Sword ingress, paid Rewind and historical aggregate reconstruction. See [retained Phase evidence](../../current/2026-10-05-native-phase-ranger-evidence.md).
