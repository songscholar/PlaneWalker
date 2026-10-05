# Native Main Performance Probe Design

- Status: Approved / Current
- Document Role: Current verification specification
- Authority Level: Below approved full-product completion contract
- Applies To: Uninstrumented production Main, Hub, native combat and automatic recording
- Owner: Plane Walker verification lane
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Real accepted samples, independent timings, authentic concurrent counts and exact physical recording readback pass

## Scope

Use the existing Main, physical unlocked Profile fixture, seeded floor catalog,
Player/Host and automatic NativeRunReplayRecorder. Measure Hub district/function
navigation and one current native combat or Boss encounter. Boss placement may
use the existing explicitly synthetic prerequisite-route fixture. Measured
frames never replace native state, damage, action generations or tape samples.
Later Boss phases must be reached with actual production Sword input.

The standalone tool is outside normal scene discovery. Defaults are bounded
development samples; an explicit 162000-frame run measures 45 native minutes.
Native duration and elapsed wall time are separate. Production physics remains
60Hz at time scale 1.0. Optional fixed-fps wall acceleration,
survival invulnerability and prerequisite fixtures are declared. This tool
cannot claim human playtesting, unassisted balance, full victory or 60Hz.

## Measurements

Record separate distributions for actual Player advancement (including automatic
recording), Host process, physical scheduler wait, optional real rendered frame
wait and observer sampling. Retain total wall time, native frame duration,
engine scheduler settings, rendering availability and peak native memory.
Sample real live actor, summon, projectile, zone, threat and construct counts;
reported maxima describe observed load and never assert theoretical saturation.

Every accepted measured frame must generate exactly one recorder observation
with increasing actual Player frame. Recording must stay active without failure.
Flush and finish as INTERRUPTED, then load a fresh physical store and compare
the first and last measured observations byte-for-byte. Retain hashes, counts,
content fingerprint and source identity in machine-readable JSON. A failure
retains diagnostics and exits nonzero, even if partial timings exist.

## Implementation Choice

Extending the repeated-sample storage probe would measure capacity, while a
standalone Boss arena would omit Main recording and Host composition. The tool
therefore uses actual Main and isolates metric collection in tools/p15. Existing
application validation and cold-envelope contracts remain unchanged. Python
contracts reject malformed durations, invented FPS claims, duplicate/missing
sample identities and successful reports without physical readback.
