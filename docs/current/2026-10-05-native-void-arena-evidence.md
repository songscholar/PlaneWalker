# Native Void Arena Evidence

- Status: Focused Verified / Full P15 certification pending
- Document Role: Current retention evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Void Boss schema5, native constructs, accepted healing and cold restoration
- Owner: Plane Walker native hostile team
- Last Verified: 2026-10-05
- Depends On: [approved P15 enemies and bosses design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md),section7.5

## Implemented Behavior

The native Void Boss owns four independent HP120 pillar bodies and Hurtboxes.
P2 retains their raster debris and removes their collision. P3 creates four
HP100 plane cores. Each accepted core break removes exactly100 actual Boss
Health and grants60 accepted exposure frames. Completing a round extends
exposure to120 frames. Regeneration waits600 frames and is limited to two
rounds,eight total core breaks. Breaking a core cancels an owned existence
denial or enrage primary. Existing character conversion respects core exposure.

P3 requests one30%-maximum-HP Player heal. The effect authority authenticates
the prepared Boss request and actual Player Health,records the capped actual
amount,including zero for a living full-health Player,and never revives a dead
Player. A dead Player skips healing without rejecting the native frame.
Actual Player Health belongs to the outer Player transaction during rollback;
Boss Health and core state belong to the Hostile Bridge transaction.

The domain reconstructs every accepted phase,damage and heal event. Current
schema5 requires the complete authoritative arena. Historical schema1 receives
explicit initial arena defaults without invented core-break or healing claims.
Physical geometry,atlas frames,positions,visibility and collision layers are
checked before accepting native weapon settlement or a frame boundary.

## Executable Evidence

- Domain RED: `build/test-evidence/void-arena-red`,missing independent arena.
- Boss ownership RED: `build/test-evidence/void-boss-arena-red`.
- Native ownership RED: `build/test-evidence/void-native-red`.
- Native heal routing RED: `build/test-evidence/void-native-phase-refresh`.
- Dead-Player boundary RED: `build/test-evidence/void-heal-boundary-red`.
- Domain/Character/native GREEN: `build/test-evidence/void-domain-retention`,6/6 scenes.
- Normal physics input: all five selected weapon loadouts hit actual pillars;
  no manually dispatched collision is used for this input gate.
- Finalized publication refusal restores actual core HP,body Health,colliders,
  exposure and receipt identities; the original frame retries once.
- Native physical persistence: typed Replay JSON is stored by SaveService,
  recovered by a fresh service and used to reconstruct a fresh Boss in a private
  native World2D. Altered derived heal data refuses cold restoration.
- Three-arena Replay GREEN: `build/test-evidence/three-arena-replay-green`,1/1;
  Forest auxiliaries,Void pillars/cores and Forge fixtures use production rasters.

Six native Metal captures under `build/visual-evidence/void-arena/` cover initial
pillars and one broken P3 core at640x360,1280x720 and2560x1080. Exact-size native
SubViewports prevent the desktop window manager from silently clamping ultrawide
evidence. Pixel checks require nonblank actual construct regions. The original
window-size assumption failed in `void-arena-visual-resolution-red.log`; the
corrected run `void-arena-native-visual-sized.log` passes without engine errors.
The displayed poses preserve a centered640x360 arena with ultrawide side margins.
Original Pillow-generated rasters have their generator,manifest and CC0 notice.

Dependency audit found no known vulnerabilities in the three tracked Python
requirement sets. Installed Godot has no built-in line-coverage provider; these
scene counts are not coverage percentages.

## Remaining Work

This milestone covers the finite arena and its native transactions. Void step
relocation/follow-up,tear final burst,other status and pickup auxiliaries,half-arena
mechanics,full authored action matrix,long real gameplay,controller/resolution
workflows and clean committed release certification remain separate gates.
The raster evidence verifies constructs;it does not certify all room artwork.
