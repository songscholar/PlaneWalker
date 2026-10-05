# Native Teleporting Elite Evidence

- Status: Verified focused gate
- Document Role: Current retention evidence for native Teleporting behavior
- Authority Level: Evidence below approved P15 specification
- Applies To: Native revision six, actual room-bound teleport, compensation, persistence and presentation
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 enemies and bosses design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), section 6

## Verified Behavior

Teleporting entered native execution at revision six. The compiler now defaults
to revision seven for authenticated Shielded weapon components; Teleporting
keeps this milestone's revision-six state and behavior. Explicit historical revisions
one through five retain their original metadata-only Teleporting behavior and
signatures. The new authoritative state binds configuration, run, hostile source,
seed, accepted elapsed frames, phase and bounded relocation reservations.

Every480 unpaused frames the actual Actor searches32 deterministic candidate
offsets: eight directions at48,56,64 and80 pixels. Their order is seeded by run,
source, seed and reservation sequence. Every destination must fit within the
actual validated room boundary shrunk by the authored body radius and pass a
native collision-overlap check. No unsafe destination is clamped into a shorter
teleport. With no safe candidate, the interval is recorded as skipped and the
next attempt waits for the next complete480-frame interval. This finite search
and skip policy are reversible implementation decisions beneath the approved
distance and collision-safety contract.

The first reservation owns departure frames480 through509, then moves the actual
body at510 and owns arrival recovery510 through539. Ordinary action resumes at540.
The independent source/sequence reservation does not consume or reuse primary
damage generations. An in-flight primary warning preserves its commitment,
geometry generations and exact60-frame pause extension. Teleport itself deals
no damage and does not issue a damaging threat fact.

Stop, actual elemental freeze and compatible Nullified delay preserve the full
departure countdown. Rift retains its native source and slows ordinary movement,
while the authored teleport retains its exact reserved48-80 pixel displacement.
Internal Teleport recovery does not pause its own clock. Actual final death marks
an outstanding reservation cancelled, hides its cue, and closes future frames.

Destination collision is checked during reservation, arrival preparation, native
commit and publication. A wall introduced after preparation refuses commit;
a wall introduced after commit refuses publication. Both paths compensate the
exact original native transform and reservation. If the fixed destination is
still obstructed when the original frame retries, the accepted result records
blocked arrival and completes30 recovery frames in place. It cannot teleport
through the wall or repeatedly search for an unannounced destination.

Typed cold restoration validates ordered interval identities, authored offsets,
phase/countdown, arrival ordering and current room bounds. Forged destination or
shortened warning refuses. Same-seed native twins select identical reservations.
Actual SaveService retains both mid-warning and accepted-arrival aggregates.
The real Player/Bridge reaches480 and510; injected late World faults restore
complete Player and native Actor state, then original frames retry with one
reservation identity. These are actual fixed-frame integration probes.

## Presentation

The native double-arrow contour and reserved landing outline remain visible
through departure, then present arrival recovery. High contrast and1.5x scaling
only change projection. Compatible Shielded and Teleporting icons occupy separate
positions. Six native Metal screenshots under
`build/visual-evidence/native-elite-affixes/teleporting-*.png` cover departure,
high-contrast departure and high-contrast arrival at640x360 and1280x720. Pixel
checks verify viewport dimensions and actual double-arrow color pixels in its
projected bounds. All six were visually inspected for readable shapes and overlap.

## Executable Evidence

- Valid RED: `build/test-evidence/elite-teleporting-valid-red`,480 accepted frames lack any native reservation.
- Native full control/physical gate GREEN: `build/test-evidence/elite-teleporting-control-final`,1/1.
- Terminal cancellation GREEN: `build/test-evidence/elite-teleporting-terminal-final`,1/1, including all prior control/persistence probes.
- Shared elite GREEN: `build/test-evidence/elite-six-final`,6/6.
- Native Actor transaction GREEN: `build/test-evidence/elite-six-native-transaction`,1/1.
- Native room motion GREEN: `build/test-evidence/elite-six-room-motion`,1/1.
- Native Metal GREEN: `build/test-evidence/elite-teleporting-native-visual.log`, all assertions and pixel checks pass.

Injected late World failures emit the expected existing frame480/510 settlement
rejection diagnostics. Retained successful logs have no script/parse errors,
warnings, orphan nodes or leaks. Installed Godot does not support line coverage.
No dependencies or authored content fingerprints changed.

## Remaining Gates

Native Chaining, Splitting and Mirroring remain pending. The complete legal-pair
matrix, all-weapon physics contacts, extended4096-reservation capacity, whole-room
balance and full P15 certification remain separate gates. The production weapon
compatibility follow-up is retained in [Shielded evidence](2026-10-05-native-elite-shielded-evidence.md)
and the Walker Proof gate. This Teleporting milestone does not certify every
weapon's physical contact.
