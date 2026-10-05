# Dungeon Probe Encounter Repair Evidence

- Status: Verified Locally / Combined Certification Pending
- Document Role: Current integration repair evidence
- Authority Level: Below dungeon probe encounter specification
- Applies To: Tool-only canonical encounter adapter, report source binding and scene-runner gates
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-dungeon-probe-native-encounter-design.md`, `../superpowers/plans/2026-10-05-dungeon-probe-native-encounter.md`
- Last Verified: 2026-10-05
- Exit Gate: Focused actual Player and core adapter regressions pass; immutable thirty-seed/five-floor report and combined clean-checkout certification remain required

## Repair

The clean checkout at `5a3639c` passed synthetic CI orchestration, Python
contracts, bootstrap/second imports and real content-pack export checks, then
failed seven canonical sleeping-guardian event continuations. It did not reach
the scene suite, instrumented coverage or retained release export gate. The
simulation used the legacy EncounterRunner without a native binding, while
canonical event definitions correctly required the production Launch driver.

The tool-only DomainEncounterRunner now delegates canonical definition
validation, sequential frames, warning/spawn delays, roster admission, exact
defeat receipts and terminal completion to LaunchEncounterRuntime. RoomRuntime
still processes event options and actual continuation results. Synthetic
entities receive explicit domain completion commands. The probe neither removes
recipe markers nor weakens production binding requirements. Its bounded
4096-frame loop reports rejection or exhausted work, and report runtime digests
include every GDScript tool adapter. The existing report retains
`synthetic: true`, `human_playtests: 0` and
`combat: domain_completion_commands`.

The fifteen-case native combat checkpoint scene exceeded the runner's default
ninety seconds while its actual physical branches passed at 150 seconds. Its
default minimum is now 300 seconds, scoped to that single scene. Script,
deferred-call and leak detection remains enforced.

The typed event source gate falsely banned any `func publish` method across all
production scripts, including the native payload/effects authority's bounded
frame publication API. Generic EventBus calls remain forbidden everywhere;
generic bus method declarations are checked on the EventBus implementation.
Independent semantic-authority publication is no longer mistaken for a generic
EventBus dispatcher.

## Reproducible Evidence

- Actual Player seed 20261006 sleeping-guardian continuation RED:
  `dungeon_seed_reward_regression`, `planewalker-tests.YxdjSU`.
- Canonical warning/spawn timing, forged/duplicate registration and defeat
  rejection, completion exactly once, defensive snapshot, malformed recipe,
  failed spawn and cancellation: `domain_encounter_runner`, GREEN
  `planewalker-tests.PUSqW0`.
- Actual Player five-floor reward regression including affected seed:
  `dungeon_seed_reward_regression`, GREEN `planewalker-tests.IuK7lm`.
- Heavy native physical checkpoint using the default runner invocation:
  `native_combat_checkpoint`, GREEN `planewalker-tests.Y4ugkV`.
- Typed EventBus source gate: false-positive RED `planewalker-tests.tZJHHf`,
  corrected GREEN `planewalker-tests.PwiJFD`.

Passing scene logs contain no script errors, deferred failures or ObjectDB/RID
leaks. The new adapter is synthetic domain integration evidence, not native
combat or human gameplay evidence. The complete immutable thirty-seed report,
full instrumented suite and packaged startup must be certified separately.
