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
- [ ] Shield: thirty-percent absorption, once-only 1200-frame regeneration and 45-frame break exposure.
- [ ] Nullified and Anchored: retained Stop/Rift/Time/echo interactions, bounded delay/vulnerability and poise/recovery, displacement refusal.
- [ ] Teleport: seeded collision-safe 48-80 pixel landing, complete 30-frame departure warning and 30-frame arrival recovery.
- [ ] Chaining: accepted Player damage only, strongest two-ally 1.15 attack buff, 90-frame TTL and 120-frame source cooldown.
- [ ] Splitting and Mirroring: independently warned finite nonreward ordinary children, no recursive abilities and owner-death retirement.
- [ ] Whole legal-pair matrix, native presentation/accessibility, Save/Replay and full-room/whole-run certification.
