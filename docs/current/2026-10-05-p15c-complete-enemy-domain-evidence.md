# Plane Walker P15C Complete Enemy Domain Evidence

- Status: Implemented / Current
- Document Role: Current focused enemy domain and lethal transition evidence
- Authority Level: Below Full Product completion and P15 hostile specifications
- Applies To: Twenty-two ordinary/elite action projections, species counters, deterministic motion and native first-lethal lifecycle
- Owner: Project owner
- Depends On: `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Canonical runtime admission and tested species transitions verified; native semantic effects remain a separate production slice

## Implemented Boundary

All twenty-two actual Base enemy definitions now configure both ordinary and
elite `LaunchEnemyRuntime` projections. Action IDs come directly from
`EnemyDefinition`, floor-one warnings retain 30 frames and later enemies retain
23 frames. Closed authored mechanisms, action IDs, handler parameters and strict
checkpoint fields remain validated. Selection uses deterministic seed streams,
authored weights, cooldowns and consecutive-use bounds when alternatives exist.

The runtime retains the existing Ruins mechanisms and adds Hunter flank/retreat,
Archer kiting, Caller retreat, Lurker bounded burrow damage, Guard recovery,
Hound dormancy/sigil state, Titan health thresholds and once-only overheat, and
Chaos form timers that wait for the committed action to finish. Accepted Health
facts synchronize HP without resetting revival, overheat or claim counters.
Guard and Hound recovery progress on unscaled accepted frames and reserve one
typed HP restoration request at their authored expiry.

The HealthComponent hook observes an immutable lethal decision and authenticates
its commit to the actual Health invocation before publication. Guard/Hound first
lethal holds HP at one, consumes the once-only flag and retains the counted
body. Guard's second lethal follows final death. Dormant Hound body damage is
blocked so its native sigil must be the finalization path. Signal callback reentry
cannot apply a second damage during the same synchronous lethal publication.
Health's existing Player/compatibility branch and frame-signal transactions retain
their regression behavior.

Blink landing is frozen at action submission, including the Rift-shortened
distance. Stop holds transit. The shared coordinator now warns that same landing.
The original elite timeline had offsets 0/27/54, which could not fit eight transit
frames plus twenty-five post-landing warning frames. The authored content and
specification now use active duration 70 and offsets 0/33/66, with local landing
offsets (0,0), (0,32), (0,-32). Domain motion lands at frames 8/58/91 and strikes at
50/83/116. Each strike carries only its own geometry and reserved generation.

## Verification

Run native scene tests with `./tools/run_tests.sh --filter <name> --timeout 45`.
Logs are under the platform temporary test root.

- `complete_enemy_runtime`: initial missing-species/lifecycle RED `pRHeln`;
  landing-envelope RED `tZb0St`; impossible triple timeline RED `9hkFWu`;
  independent per-strike envelope RED `c2WsOa`.
- `launch_enemy_lethal_transition`: real first-lethal RED `IEgHWn`, native
  dormant-body RED `eUpAVa`, synchronous signal reentry RED `5dfMfp`, and
  complete first-lethal/reentry GREEN `8Y6t1Z`, zero script errors/leaks.
- The earlier canonical/frame checkpoint GREEN `DqqM41`, landing GREEN
  `y1nIBP` and corrected triple timeline GREEN `Q0O1iU` establish the separate
  stages before the final independent geometry regression.
- Existing Launch enemy actor/runtime/presentation suite: `pQHbtf`, 4/4 GREEN.
- Existing Health component/frame observations: `uygmqC`, 2/2 GREEN before the
  reentry tightening; final rerun `IdU8b0`, 2/2 GREEN, clean logs.
- Final independent blink geometry/canonical checkpoint suite: `utlj4u`, 1/1
  GREEN; Ruins shell/interruption regression `ldAMJN`, 1/1 GREEN, clean logs.

An intermediate run `exWjQD` passed assertions but failed resource-log checks
because concurrently added localization translations had not yet been imported.
It is not counted as GREEN. The subsequent project import resolved those errors.
Godot line coverage is unsupported; no coverage percentage is inferred.

## Remaining Native Work

This evidence does not claim production completion for all twenty-two species.
The new semantic authority must still execute real zone ticks, capped support
healing/history, constructs, summons, links, portal transit, elemental zone swaps,
phase shifts, split/death hazards and destructible Hound sigils. Native body landing
collision and per-hit Health effects require actual room integration. The current
runtime emits typed restoration/explosion/consumption requests; shared native
router ownership is coordinated separately and must close those paths before full
Launch certification. Elite affixes, summon behavior subsets and whole-run content
replay remain governed by the P15 specification rather than these focused tests.
