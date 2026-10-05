# P22A Player Replay Archive Evidence

- Status: Verified Locally / Partial Milestone
- Document Role: Current milestone retention evidence
- Authority Level: Below P22A replay archive specification
- Applies To: Player recording packages, durable local archive and isolated Player viewing
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22a-player-replay-archive-design.md`, `../superpowers/plans/2026-10-05-p22a-player-replay-archive.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual Player recording, physical archive fault/recovery and isolated seek/playback tests pass with clean logs

## Verified Behavior

The archive packages actual Launch Player movement and Time Stop recordings with
the existing object-disabled Variant codec. ReplayPlayer validates the entire
recording before storage or exposure. Packages bind exact game version, content
snapshot and save domain; content-derived identifiers never form file paths.
Import and export preserve the safe portable encoding. Rehashed invalid movement,
wrong bindings, unsupported schemas and malformed packages are refused.

A separate SaveService slot retains up to twenty recordings and sixty-four MiB
of encoded package data. The existing sixteen-MiB binary codec ceiling still
applies. Reads return defensive copies. Capacity refusal preserves every entry;
removal is explicit. Physical compare-exchange refuses stale and interleaved
writers. An idempotent duplicate also verifies the durable primary, so a stale
instance cannot claim that another writer's removed recording still exists.
Pre-promotion faults preserve committed memory. Post-promotion faults reconcile
only after physically verifying the exact candidate. Fresh instances reload
actual files, including verified backup recovery after primary corruption.

The viewing session holds WeakRefs to an actual independent Player and its
dedicated ReplayWorld SubViewport, whose World2D and typed event bus are separate
from live gameplay. The world creates and admits the Player before its ready
callbacks bind; reparenting a globally initialized Player cannot forge admission.
Processing and physics are disabled and there is no hostile frame participant.
Seek restores and verifies native snapshots through ReplayPlayer. Playback runs
the original movement/time commands through actual Player domain code. A
structurally valid but rehashed trajectory reports the first diverging frame and
atomically restores Player state and cursor. Freed, live or changed-identity
targets refuse commands.

Shared Player, Health, time, weapon and payload queries resolve the actual world
ancestor. Target groups and spawn roots remain local, and production queries
exclude replay actors. Time and weapon publications and incoming room facts use
the private typed bus. ReplayPlayer observes that bus for actual time execution
verification. All five actual weapons replay with their canonical hold/press
modes; a same-tree actual EnemyTank retains identical Health and Stop sources.
Tampering with the world or returning a target to live processing refuses.

## Reproducible Evidence

- Complete replay regression after all isolation changes:
  `./tools/run_tests.sh --filter tests/replay/ --timeout 90`, GREEN
  `planewalker-tests.SjNVP4` (14 / 14), including Boss exposure, character
  external facts, full-player snapshots, physical archive, isolated world,
  dungeon/reward seals, weapon external facts and restore atomicity.
- Missing archive RED: `planewalker-tests.vxqx9z`.
- Physically removed replay incorrectly accepted by stale duplicate RED:
  `planewalker-tests.llGqEa`.
- Missing isolated viewing session RED: `planewalker-tests.sodGwS`.
- Independent review's actual live EnemyTank Stop and global publication leak
  RED: `planewalker-tests.2NPZK7`; the disabled-only isolation was corrected.
- Three-scene regression after world/bus isolation:
  `./tools/run_tests.sh --filter player_replay --timeout 90`,
  GREEN `planewalker-tests.p83q0w` (3 / 3).
- Actual five-weapon recording/playback, private facts, physical world exclusion,
  live Health/Stop invariance, incoming room facts and invalid world/admission:
  `./tools/run_tests.sh --filter player_replay_world`, GREEN
  `planewalker-tests.hWsSFg`.
- Original actual typed combat publication regression: `combat_event_publication`,
  GREEN `planewalker-tests.IvbIfl`.
- Existing weapon and character runtime replay regressions: GREEN
  `planewalker-tests.OZwPeb`, `planewalker-tests.a2bTS6`.
- Original three-scene milestone before the isolation review:
  GREEN `planewalker-tests.pePl8L` (3 / 3), covering the existing full-player
  contract plus physical archive and actual isolated Player execution.
- Earlier archive/viewing GREEN: `planewalker-tests.xOQRAz` (3 / 3),
  `planewalker-tests.p8BFFM` (archive).

Passing logs were scanned for script errors, deferred failures and ObjectDB/RID
leaks. Exploratory failed fixtures are not passing evidence. Stock scene counts
do not establish line coverage; the instrumented clean-checkout lane is separate.

## Retention And Remaining Scope

The package, storage and viewing boundaries, tests and this evidence are retained
in one focused local commit. The implementation reuses SaveService and
ReplayPlayer, with no additional runtime dependency or remote service.

P22A alone does not complete full-product replay. Automatic native whole-run
capture, hostile/room/economy tape, compressed periodic keyframes, forty-five-
minute storage and Hub archive/player controls remain in the approved following
scope. This milestone supplies the tested durable boundary for that integration.
It does not authenticate leaderboard scores or provide human gameplay evidence.
