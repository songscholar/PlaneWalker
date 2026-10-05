# Native Elite Affixes Implementation Plan

- Status: In Progress / Current
- Document Role: Current focused native elite implementation plan
- Authority Level: Below P15 hostile specification
- Applies To: Canonical elite affix configuration, actual Health/control effects and physical checkpoints
- Owner: Plane Walker implementation team
- Depends On: `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, section 6
- Last Verified: 2026-10-05
- Exit Gate: All ten authored affixes execute native bounded behavior with rollback, cold restore and nonrecursive children; static slices do not imply dynamic completion

The approved P15 design supplies exact behavior. A focused configuration compiler
will consume verified `EliteAffixDefinition` rows and derive immutable runtime
stats/actions. The existing runtime definition digest seals those derived values;
the Actor checkpoint additionally binds the accepted affix IDs and pending dynamic
IDs. Native Driver construction and cold reconstruction share this compiler.
Historical closed V1 actors without affix configuration retain their original
metadata-only behavior for that restored room; no old effect is fabricated.

## Static Native Slice

- [x] Inspect actual catalog, Actor/Health/Router, physical motion and cold Driver boundaries.
- [x] Add `launch_elite_affix_test` before implementation; missing native configuration must fail.
- [x] Retain parsed canonical affix rows in `LaunchEncounterCatalog.affix_definition(id)`.
- [x] Add `LaunchEliteAffixProjection.configure(rows, floor)` and `project(definition)`; reject unknown fields, duplicate/excluded IDs, wrong floors and nonelite bodies.
- [x] Add Actor `configure_launch_affixes(rows, floor)` before base definition configuration; actual Frenzy applies damage 1.25, speed 1.15 and incoming damage 1.20.
- [x] Actual Fortified applies HP 1.50, speed 0.80 and knockback resistance 0.20 capped at 0.90; unchanged body geometry and elite silhouette 1.15 are independently verified.
- [x] Bind immutable affix configuration into frame checkpoints; commit/reject/retry, typed cold replay and changed-affix refusal preserve native Health and action state.
- [x] Configure actual Driver spawns from canonical affix rows, and preserve the explicit closed legacy V1 cold actor variant.
- [x] Run native affix, enemy Actor, production encounter and physical checkpoint regressions; record [current evidence](../../current/2026-10-05-native-static-elite-affix-evidence.md) and exact local commit.

Native acceptance uses the actual sentinel elite: base 80 HP becomes 160,
Fortified becomes 240, Frenzy's 12-damage ordinary move becomes 18.75 after both
elite and affix multipliers, its warning remains 30 frames, and a net ten-point
incoming hit removes twelve HP. Fortified retains 10 incoming damage and scales
a ten-pixel knockback vector to eight. All ten definitions remain visible in the
configuration report; the eight dynamic IDs are explicitly pending in this slice.
The optional `affix_signature` participates in the existing runtime definition
digest even for a pending-only pair. Removing the Actor extension therefore
cannot masquerade as a historical metadata-only actor, whose original unmodified
definition digest remains required. The immutable signature hashes sorted
canonical rows and floor; it does not revise authored content or Save schema.

```sh
./tools/run_tests.sh --filter launch_elite_affix --timeout 45
./tools/run_tests.sh --filter launch_enemy_actor --timeout 45
./tools/run_tests.sh --filter production_launch_encounter --timeout 45
./tools/run_tests.sh --filter native_combat_checkpoint --timeout 150
```

## Dynamic Native Gates

- [x] Regeneration: actual three-percent healing every 120 unpaused frames within the total thirty-percent cap, heavy-hit 120-frame interruption, once-only Health publication, typed physical cold recovery and whole-Player frame compensation. Native compiler revision 2 retains the authentic affix clock; explicit historical revision 1 retains its original metadata-only regeneration behavior. Same-frame support healing consumes only actual regeneration gain. See [native regeneration evidence](../../current/2026-10-05-native-elite-regeneration-evidence.md).
- [x] Shield: native post-defense thirty-percent absorption, once-only 1200-frame regeneration,45-frame break exposure, actual Sword/Player compensation and accessible contour. See [native Shielded evidence](../../current/2026-10-05-native-elite-shielded-evidence.md).
- [x] Anchored: native poise/recovery and displacement refusal, actual Stop/Rift, physical checkpoint and accepted-frame compensation.
- [x] Nullified: retained Stop/Rift/Time/echo interactions, bounded delay/vulnerability, Anchor/Frenzy composition and accessible clock-fragment cue. See [native Nullified evidence](../../current/2026-10-05-native-elite-nullified-evidence.md).
- [x] Teleport: seeded collision-safe48-80 pixel landing, complete30-frame departure warning and30-frame arrival recovery, actual Player late compensation, typed/physical persistence and accessible native projection. See [native Teleporting evidence](../../current/2026-10-05-native-elite-teleporting-evidence.md).
- [ ] Chaining: accepted Player damage only, strongest two-ally 1.15 attack buff, 90-frame TTL and 120-frame source cooldown.
- [ ] Splitting and Mirroring: independently warned finite nonreward ordinary children, no recursive abilities and owner-death retirement.
- [ ] Whole legal-pair matrix, native presentation/accessibility, Save/Replay and full-room/whole-run certification.

## Nullified Native Revision Four

The existing approved P15 section 6 supplies thirty delay frames, thirty
vulnerability frames, and a 0.70 Rift movement floor. Revision four retains
source claims and absolute accepted-frame expiry in the affix domain snapshot.
The Actor uses those facts to pause its existing warning/action clock, then
applies a twenty-percent incoming damage bonus for the following thirty frames.
The bonus is a reversible tuning choice because P15 does not specify a magnitude.
The native time and echo damage pipelines remain active. Explicit revisions one
through three retain their original metadata-only Nullified behavior.

- [x] Add `tests/integration/combat/launch_elite_nullified_test.gd` and scene;
  retain RED for the 0.70 Rift floor and missing bounded native Stop conversion.
- [x] Compile `nullified` as native at revision four in
  `launch_elite_affix_projection.gd`; retain the old definition signatures.
- [x] Add bounded source receipt and thirty/thirty timing validation in
  `launch_elite_affix_runtime.gd`; duplicate and forged expiry refuse.
- [x] Connect Stop conversion, Rift clamp, action delay and damage exposure in
  `launch_hostile_actor.gd` through existing frame transaction snapshots.
- [x] Pass actual Health/time/echo, action warning extension, reject/retry,
  typed cold restore, physical SaveService, and legacy revision checks.
- [x] Run `tools/run_tests.sh --filter launch_elite` plus native Actor/physical
  checkpoint regressions and record focused evidence before revision promotion.

## Shielded Native Revision Five

Shield absorbs the final amount after the existing defense and incoming damage
modifiers. Its pool is30% of the native elite maximum HP, including compatible
Fortified scaling. The first break grants45 frames of20% incoming exposure and
starts an unscaled1200 accepted-frame deadline. That deadline regenerates the
full pool once; a second break never schedules another regeneration. The exposure
magnitude and deadline-from-break semantics are reversible tuning decisions
where P15 does not supply those details. Historical revisions one through four
retain metadata-only Shielded behavior.

- [x] Retain native Shielded RED for actual absorption and missing authoritative pool.
- [x] Add a narrow optional Health post-defense absorption prepare/commit/rollback boundary; unchanged owners keep the existing pipeline.
- [x] Seal bounded shield hit receipts, pool/break/regeneration/exposure clocks and legacy revision signatures.
- [x] Verify actual partial/full absorption, overflow, duplicates, defense/Frenzy/Fortified/Nullified composition, terminal cleanup, late rejection retry and typed/physical cold reconstruction.
- [x] Project an accessible gold shield contour with visible intact/broken states.
- [x] Run native Shielded, Health/damage, shared elite, production encounter and physical checkpoint gates; retain focused evidence.
- [x] Retain Shielded/Anchored absorbed-control RED/GREEN: honest zero-body resolution, one control receipt, threshold recovery, typed/physical persistence and actual Player late rejection retry.

## Teleporting Native Revision Six

- [x] Retain480-frame actual Actor RED before native reservation implementation.
- [x] Bind deterministic48-80 pixel candidate search to actual room/body authority, complete30-frame departure and30-frame arrival recovery, independent reservation identity and unchanged primary warning ownership.
- [x] Verify Stop/freeze/Nullified/Rift, same-seed twins, no-safe skip,960-frame retry, typed mid-warning/arrival cold state and physical SaveService.
- [x] Recheck collision during arrival preparation, commit and publication; compensate late walls and safely complete blocked arrival in place.
- [x] Verify real Player late World rejection/retry at reservation480 and arrival510; retire pending landing and projection on actual final death.
- [x] Retain shared elite6/6, native Actor/room regressions and six visually inspected Metal captures.
