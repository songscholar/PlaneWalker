# Native Production Frame Integration Plan

- Status: Approved / Current
- Document Role: Current production Bridge integration and executable criteria
- Authority Level: Below approved full-product completion contract
- Applies To: NativeLaunchEncounterDriver fresh and cold-restored encounters
- Owner: Project integration lead
- Depends On: `2026-10-06-native-owned-frame-token-evidence.md`
- Last Verified: 2026-10-06

## Observed Gap

The exact Script whitelist in commit `86aef36` recognizes the base
HostileFrameBridge. Actual Main constructs the Driver's inner ProductionBridge
for both fresh encounters and cold restoration. That distinct Script retains
the public fallback, so the `8011d1b` editor/release 600-frame measurements do
not establish that the owned token path ran in Main. Keep those reports as
actual public-path measurements and monitoring/recording evidence.

## Focused Design

Move the existing inner ProductionBridge unchanged into
`scripts/enemies/launch/production_hostile_frame_bridge.gd`, with global class
`ProductionHostileFrameBridge`. Driver retains the local `ProductionBridge`
name as a preload of that canonical Script. Both constructors use it.

Base Bridge exposes a static Script-identity predicate accepting only the
exact Base and Production Script objects. Actor binding calls the same static
predicate. Unknown subclasses, claimed support methods, alternate Scripts
and resource-path takeover cannot opt in. Global class object references
match the existing Actor/Boss pattern; use real clean imports to verify the
dependency cycle. Do not replace Script identity with runtime path loading.

Preserve Production register_actor's roster-configuration window and its
is_ready_for_frame/begin_frame native_boundary_ready checks. Preserve all
candidate validation, Effects, pre-weapon compensation, publication, summon
fallback and closed-frame semantics from the owned token implementation.

## Executable Acceptance

Before changing production, an actual Main fixture must retain a valid RED
on fresh and physically cold-restored Driver transactions: genuine canonical
Actor records must have native_actor_frame true, empty public actor_ticket,
and the exact Actor-owned empty marker. Legacy transactions, typed state
compensation, physical checkpoint reload and original boundary refusal must
already pass. Setup, script or import errors are not assertion RED evidence.

GREEN repeats those paths and the complete existing token fixture. Extend
same-path spoofing to the Production Script and retain unknown subclass
fallback. Run the relevant physical resume/checkpoint, recording, summon,
Forest/teleport/phase landing, Effects refusal and Boss neighbors. Validate
strict paired logs and clean-import the integrated committed source.

Commit the narrow production, tests and evidence together with exact paths.
Repeat uninstrumented editor/release 600 frames from a new frozen checkout.
The native-aware diagnostic must observe actual native preparation calls;
old public-only wrappers cannot certify the new path. Passing integration
does not certify 16.667-ms work, rendered saturation, sustained recording,
the 45-minute soak, UI completion or human playtests.
