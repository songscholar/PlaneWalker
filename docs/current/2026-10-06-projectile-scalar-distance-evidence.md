# Projectile Scalar Distance Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: LaunchHostilePayloadRuntime and its native projection
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-projectile-scalar-distance-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Root Cause and Change

An isolated actual native Main run fails floor-four phase-two admission at frame
1466. The diagnostic baseline is the archived `959696e` checkout plus the native
narrow-query production files retained in
`build/retained-checkout/native-query-late-baseline-959696e-20261006`.

The failure is reproduced unchanged in the instrumentation copy. Its two-stage
failure evidence is retained at:

- `build/retained-checkout/native-query-late-diagnostic-959696e-20261006/build/floor4-phase2-effects-detail/`.
- `build/retained-checkout/native-query-late-diagnostic-959696e-20261006/build/floor4-phase2-payload-detail/`.

Both directories retain stdout, Godot logs, the rollback boundary, and the
detached typed `.bin` and readable `.json` rejection detail. The refusal is
`effects_can_commit`, specifically the payload candidate cold snapshot validator.
Payload ticket, before snapshot, native projection, target descriptors, repeated
contacts and landing queries all match. Effect ticket, registry, source batches,
semantic candidate/native observations, and summon ticket pass. There are no
effect damage or health records in the refused frame.

The legal diagonal direction is `(0.5927259922027588, 0.8054042458534241)`. Its
float32 normalization has a squared norm slightly above one. Integrating the
norm of the per-frame displacement produces travel `198.40001002628927` at
age 93, while the unchanged strict maximum is `128 * 93 / 60 + 0.00001 =
198.40001`. The candidate is correctly refused by that maximum-speed validator.

The runtime now retains its already calculated scalar `distance` in the motion
plan and integrates that value. This keeps the authored speed, Stop/Rift
modifiers, range clipping, direction, contacts, and retirement rules authoritative.
No validator tolerance or snapshot schema changes. Diagonal travel and derived
positions differ from the earlier erroneous integration by subpixel amounts;
that correction is intentional. Same-version replay is deterministic.

## Focused Verification

RED: `build/projectile-scalar-distance-red-20261006`. The real native projectile
is refused at offset 93, with downstream incomplete retirement. The domain test
also detects accumulated scalar error and the cold refusal. Fixture admission
and script parsing pass, with no unrelated engine or leak failure.

GREEN and regressions so far:

| Scope | Scenes | Evidence Directory |
| --- | ---: | --- |
| New domain and real native diagonal contracts | 2 | `build/projectile-scalar-distance-green-20261006` |
| Payload execution, result contracts, authority, Boss/identity/retirement, Moth and domain | 8 | `build/projectile-scalar-payload-regression-20261006` |
| Actual Player/projectile overlap | 1 | `build/projectile-scalar-overlap-regression-20261006` |
| Terminal projectile owner contact | 1 | `build/projectile-scalar-terminal-contact-regression-20261006` |
| Boss exposure checkpoint replay | 1 | `build/projectile-scalar-replay-regression-20261006` |
| Native combat cold checkpoint | 1 | `build/projectile-scalar-checkpoint-regression-20261006` |

The new domain contract advances the complete authored 120-frame lifecycle with
and without bounded Stop/Rift, validates every retained state through the
unchanged cold validator, compares travel to an independently calculated scalar
integral, rejects a trajectory-consistent forged overspeed snapshot, and restores
a historical boundary to reproduce the exact later state. The native contract
uses an actual Player collider and projectile projection. It verifies late target
movement rejection, exact domain/body rollback, identical same-frame retry,
publication and finite physical retirement.

Every listed GREEN scene passes the repository's strict stdout and Godot log
validator, including script errors and ObjectDB/RID leaks, under
`4.6.1.stable.official.14d19694e`. The stock runner reports line coverage as
unsupported. No dependency was added.

The progress-validation lane's independent read-only review found no correctness
issues in scalar ownership, typed snapshot boundaries, Stop/Rift clocks, contact
branch behavior, strict overspeed rejection, rollback/retry, or finite retirement.

All fourteen focused scenes pass. New actual Main phase-two reproduction remains
pending in this first retention record. The earlier refusal runs contain
no qualified late-phase timing samples. Any subsequent performance run retains
its survival fixture and route prerequisites and cannot certify production FPS
or human completion.
