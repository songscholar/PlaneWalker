# Native Elite Mirroring Implementation Plan

- Status: Active / Current
- Document Role: Current focused implementation plan below approved P15 specification
- Authority Level: Project standing authorization; approved P15 section 6
- Applies To: Native Mirroring clocks, owned reservations, unrewarded children, rollback and cold continuation
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 enemies and bosses design](../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), section 6
- Exit Gate: Native interval, forty-frame warning, real mirror attacks, bounded admission, rollback, typed/physical cold continuation and native visual gates pass with retained evidence.

## Goal And Architecture

Every 900 unpaused accepted owner frames reserve one `elite_mirror` with a
40-frame warning and 480-frame lifetime. No more than one pending, warning or
active mirror belongs to an owner. Copies use 20% ordinary parent HP and 50%
ordinary parent damage, execute only the first safe damaging action, have no
affixes or recursive abilities, and grant zero independent reward.

Revision nine enables native Mirroring while explicit revisions one through
eight retain their exact metadata-only behavior and signatures. A pure module
owns the 900-frame clock and finite ordered reservation ledger. The Actor exposes
only the new reservation sealed into its prepared frame. Existing SummonAuthority
authenticates that request and owns frozen positions, 40-frame warnings, eight
global child slots, deferred safe admission, one mirror per owner, child lifetime
and owner retirement. Stop pauses the interval clock; an already published spawn
warning uses accepted encounter frames and never shortens its 40-frame floor.

Independent parent binding is reconstructed from the canonical ordinary enemy
definition, excluding elite scaling and the second affix. Mirror row identities
hash the dedicated `[run, source, "affix:mirroring", sequence, slot]` namespace.
Mirroring scheduling receipts are bounded to 4096; exhaustion stops optional
mirror scheduling without preventing owner combat or frame advancement.

## Interfaces And Files

- Create `scripts/enemies/launch/launch_elite_mirroring_runtime.gd`: closed state `{elapsed_frames, reservations}`; each receipt has `{sequence, elapsed_frame, runtime_frame, source_position}`. `advance(state, frame, paused, position)` advances the clock; `can_restore(state, identity, frame)` authenticates sequence, exact multiples of 900, accepted deadlines and positions.
- Modify `launch_elite_affix_projection.gd` and `launch_elite_affix_runtime.gd`: native revision nine, strict schema seven with `mirroring`, accepted clock and restoration.
- Modify `launch_hostile_actor.gd`: pass the actual source position to the pure clock; `prepared_launch_mirroring_reservation() -> Dictionary` returns only the newest accepted prepared interval; `launch_mirroring_reservations() -> Array` provides accepted ledger for authority reconstruction.
- Modify `launch_summon_authority.gd`, after summon milestone retention: authenticate sealed reservation, dedicated `MIRROR` row identity, canonical ordinary projection, budget/collision safety, warning floor and owner lifetime. Shared authority changes are coordinated with its owner.
- Modify `launch_elite_affix_cue.gd`: outlined duplicate cue with native high-contrast/scaled presentation and no gameplay mutation.
- Create focused unit/integration/visual gates and current evidence document. Existing elite and summon regression suites remain required.

## Executable Completion Criteria

1. [x] Retain real metadata-only RED: actual elite configures Mirroring at revision eight, passes native owned frames through 900, and has no native mirror warning or child.
2. [x] Pure revision-nine gate: no receipt before 900; frame 900 receipt; Stop pauses the interval; receipt sequence/deadline/position tampering refuses; historical revision eight remains pending; capacity exhaustion does not block owner frames.
3. [x] Actual native gate: sealed frame 900 creates visible warning; no child before 940; frame 940 materializes one actual raster child with ordinary HP/damage and real production attack/Player weapon contact.
4. [x] Owner death, eight-child capacity, collision obstruction and delayed admission preserve one owner mirror, warning floors and frozen slot. TTL retires both combat source and room work; no reward, affix, regeneration, revival or child recursion is possible.
5. [x] Inject late World rejection at reservation, birth and child-death boundaries. Complete Player, owner, child, authority and encounter work restore exactly; retry accepts once. Exact TTL expiry and deferred admission also compensate.
6. [x] Typed replay and physical SaveService cold state reconstruct owner clock, reservation, warning, active child and remaining lifetime. Erased/future/foreign-owner records refuse reconstruction.
7. [x] Native 640x360 and 1280x720 Metal captures show the actual owner cue, warning and mirror raster; accessibility scaling and legal paired cues remain readable with no overlap.
8. [ ] Scan retained logs for script/parse errors, warnings and leaks; run existing elite, summon, native checkpoint and production encounter gates; retain precise commit and informational milestone evidence.

Verification commands use `tools/run_tests.sh --filter elite_mirroring --timeout
180` and `--filter native_summon`, with explicit `TEST_LOG_DIR` for retention.
