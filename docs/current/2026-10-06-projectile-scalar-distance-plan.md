# Projectile Scalar Distance Validation Plan

- Status: Approved
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: LaunchHostilePayloadRuntime and its native projection
- Owner: Project owner
- Depends On: Approved full-product completion contract
- Last Verified: 2026-10-06

## Observed Failure

The frozen native Main floor-four phase-two admission run refuses frame 1466 in
`effects_can_commit`. Isolated failure instrumentation identifies only the
payload candidate validator as false. Native projection, target descriptors,
repeated contacts, effect ticket, semantic candidate, summons, and registry all
match their sealed observations.

The diagonal projectile at age 93 has travel `198.40001002628927`, exceeding the
strict `128 * 93 / 60 + 0.00001` bound of `198.40001`. The runtime currently
integrates the norm of displacement calculated from a float32 normalized
direction. A direction norm slightly above one accumulates error across frames.

## Executable Completion Criteria

1. Establish RED with a legal normalized diagonal matching the captured failure,
   advancing through the authored 120-frame lifetime. Every intermediate state
   must pass the existing cold validator and scalar travel must stay within
   `0.000000001` of the authored 60 Hz distance integral.
2. Preserve Stop and Rift behavior, finite retirement, strict rejection of a
   trajectory-consistent forged overspeed state, and deterministic replay from
   a restored historical boundary.
3. Repeat the diagonal lifecycle through native payload projections and a real
   Player collider. Verify late target changes are rejected, rollback restores
   complete state and body positions, and the same frame retries once.
4. Change only the scalar distance propagation in the payload runtime. Keep
   snapshot, authored range, contact, and maximum-speed validators unchanged.
5. Run focused payload, overlap, retirement, replay, and cache regressions with
   strict Godot error/leak scanning. Reproduce actual Main phase-two admission
   and retain its independent measured tape evidence after the fix.

## Evidence Boundaries

The diagnostic snapshots under `build/retained-checkout/` are isolated from
production. Performance probes use an explicit survival fixture and prerequisite
route fixture. They cannot certify rendered FPS, unassisted victory, human
playtesting, or project coverage.
