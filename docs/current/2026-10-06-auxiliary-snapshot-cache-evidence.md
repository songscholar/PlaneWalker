# Auxiliary Snapshot Validation Cache Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: VoidArenaRuntime, ForgeArenaRuntime and ForestAuxiliaryRuntime
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-auxiliary-snapshot-cache-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: Cache contracts and focused native regressions passed; whole-game performance pending

## Delivered Behavior

Each of the three domains retains at most four fully validated snapshots in a
positive-only, static, Mutex-protected FIFO cache. A cache key contains detached
typed snapshot bytes, the complete stable validator context, and the independent
`accepted_boundary` mode. A miss executes the unchanged cold event reconstruction
validator. A general next-frame snapshot cannot admit that same snapshot at a
committed native boundary. Refused snapshots never occupy cache capacity.

Void context contains the authored definition, initial state, and bound arena
origin. Forge context contains the definition and initial state, which includes
the bound origin. Forest context contains initial state and bound origin; its
replay rules are fixed in the script. Context encoding runs after accepted
configuration and origin binding. Sequential advancement, retirement, and valid
same-origin historical restoration do not change the validator's stable inputs.

Existing failed-configuration policies remain intact: Void clears its domain and
context at configuration start; Forge and Forest preserve the previously accepted
domain when a new configuration fails. No failed new configuration becomes a
positive cache entry. Integral-float acceptance continues to follow each cold
contract rather than a new blanket type policy. Mutated caller snapshots cannot
modify retained bytes or another runtime's accepted state.

## Correctness Verification

Meaningful RED: `build/auxiliary-cache-red-20261006` failed exactly the three
missing-cache and three missing-independent-cold-validator assertions. Authentic
definition parsing, configuration, and original snapshot admission passed.

The final implementation passed 17 scene executions:

| Scope | Scenes | Log Directory |
| --- | ---: | --- |
| New cold/warm cache contract | 1 | `build/auxiliary-cache-final-green-20261006` |
| Native arenas, actual weapon input, training, and arena domains | 12 | `build/auxiliary-cache-final-arena-20261006` |
| Forest native auxiliary and domain | 2 | `build/auxiliary-cache-final-forest-20261006` |
| Native combat cold checkpoint | 1 | `build/auxiliary-cache-final-checkpoint-20261006` |
| Boss exposure checkpoint replay | 1 | `build/auxiliary-cache-final-exposure-replay-20261006` |

The new contract checks cold/warm verdict equality for typed and forged fields,
derived HP, changed identity/digest, extra fields, fractional and integral event
frames, caller mutation, staged versus committed events, eviction, historical
and terminal restore, origin rebind, owner reconfiguration, failed configuration,
and three concurrent independent readers per domain. The static caches remain
bounded during those concurrent reads. Concurrent mutation of one domain instance
is not an existing supported interface and is not introduced here.

Every final scene passed the repository's stdout and Godot engine log validator,
including script errors and native object/RID leaks, under
`4.6.1.stable.official.14d19694e`. The stock runner reports line coverage as
unsupported; 17 scene executions are not a coverage percentage. No project npm
or pip dependency manifest was present and no dependency was added.

The earlier Forest native run in `build/auxiliary-cache-forest-regression-20261006`
failed on stale player damage-source fixtures and their downstream scene
assumptions. The parent lane authenticated those fixtures in `ad1a8bd`; the final
Forest run above passed without weakening runtime admission.

A separate read-only review by the progress-validation lane found no correctness
issues in context completeness, boundary separation, typed keys, failed configure,
historical restore, Mutex release paths, eviction, or concurrent cloned readers.

## Frozen Native Measurements

Before: `build/retained-checkout/auxiliary-cache-before-20261006`.

Final after: `build/retained-checkout/auxiliary-context-cache-after-20261006`.

The before derives from the parent's frozen
`boss-validation-cache-after-20261006`: the retained `c1a24d4` source baseline,
the three hostile catalog/action cache runtimes from `fcb6040`, and the Boss
validation memo from `bbb8229`. The frozen Boss file has SHA-256
`ad35f71302bf0d28afe85bbab714eaeafde046356d4d4fc1643fc4d6b53cb90c`, equal to
that commit. These copied checkouts have no Git metadata; their reports explicitly
retain an empty revision and the full runtime source digest instead.

All 408 GDScript files under `scripts` and `autoload` were compared. Exactly the
three affected runtime files differ between the frozen before and final after.
The aggregate source digests are:

- Before: `790c85af69da110dfef4a886adcfc2a9036edd2dfc459f2eb189807a4fb7d205`.
- Final after: `272a1ee8faa7b8d70216207b9ad3c2151e615284ef87e03ef54099480bff444c`.

Each run used `python3 tools/p15/native_performance_probe.py --output <new-report>
--frames 600 --hub-frames 12 --boss-floor <floor>`. Each pair retained exactly
600 unique consecutive actual Player frames, 601 physical tape observations,
equal content snapshots, encounter identity, sample boundaries, physical peak
counts, native scheduler settings, and exact first and last replay hashes. The
probe also verifies unchanged runtime sources across each measurement.

| Boss Floor | Before Mean / p95 | Final Mean / p95 | Recorded Peak Physical Counts |
| --- | --- | --- | --- |
| 1, Forest | 24.998 / 42.471 ms | 25.177 / 41.067 ms | actor 1, constructs 6, threats 9, zones 5 |
| 3, Forge | 28.476 / 47.433 ms | 26.563 / 43.282 ms | actor 1, projectile 1, threats 4, zones 2 |
| 4, Void | 32.215 / 54.978 ms | 29.626 / 48.403 ms | actor 1, projectile 1, threats 2, zone 1 |

All three samples observed zero summons; omitted peak count categories were zero.
The Forest mean did not improve and is explicitly a mixed result. Forge and Void
improved in these samples. These are single paired runs on the development host,
not a statistically controlled benchmark or evidence of a whole-game frame-rate
pass. No result is promoted to the game's performance certification gate.

Reports under the before checkout are
`build/auxiliary-before-floor1-600/report.json`,
`build/auxiliary-before-floor3-600/report.json`, and
`build/auxiliary-before-floor4-600/report.json`. Reports under the final after
checkout are `build/auxiliary-context-after-floor1-600/report.json`,
`build/auxiliary-context-after-floor3-600/report.json`, and
`build/auxiliary-context-after-floor4-600/report.json`.

## Diagnostic And Rejected Draft

The first cache draft reencoded the whole context on every validation. Its frozen
`auxiliary-cache-after-20261006/build/auxiliary-after-floor4-600/report.json`
retains mean 32.538 ms and p95 59.681 ms against the same 32.215 / 54.978 ms before.
It showed no stable timing benefit and led to the final context precomputation.
This unfavorable draft result is retained rather than omitted.

The separate instrumented
`auxiliary-cache-diagnostic-20261006/build/auxiliary-hotpaths-floor4-180/report.json`
recorded 926 Void arena validations but only 155 cold reconstructions. The old
wrapper/context encoding contributed approximately 0.609 ms per sampled frame;
the cold body contributed 0.383 ms. The diagnostic provides a mechanism for the
optimization and is explicitly instrumented, not a release benchmark.

The prior broader diagnostic retained in
`cache-hotpath-diagnostic-20261006/build/hotpath-recorder-floor2-180-fixed/report.json`
identified remaining repeated Host runtime snapshots and recording/cold-checkpoint
work. Its timing store captures only the measuring caller thread; an earlier
worker-thread stack assertion belongs to diagnostic instrumentation and is not
counted as gameplay failure or valid performance evidence.

## Limits And Recovery

All performance samples are headless, phase-zero native Boss encounters with
60 Hz native scheduling and time scale 1, `--fixed-fps 60` wall acceleration,
explicit survival/prerequisite fixtures, and incomplete interrupted recordings.
They claim zero human playtests, no unassisted victory, and no FPS certification.
They do not certify rendering, maximum enemy/summon concurrency, later Boss
phases, completion of the whole game, or the current checkout's unrelated later
changes. Those checks remain in the full gameplay and UI acceptance program.

The production change only adds in-memory optimization state around the previous
cold authorities. It changes no save/replay schema, data, deterministic seeds,
damage rules, or persistent cache. Recovery is a focused revert of the cache
milestone's three runtime changes and its dedicated test; the authoritative cold
bodies remain available in the frozen before and in normal Git history.
