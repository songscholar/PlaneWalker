# P21A Native Boss Rush Evidence

- Status: Verified / Current
- Document Role: Current milestone retention evidence
- Authority Level: Focused executable acceptance record
- Applies To: Native five-Boss stage loop, isolated challenge checkpoint and Main Hub entry
- Owner: Runtime integration lane
- Depends On: `../superpowers/specs/2026-10-05-p21a-native-boss-rush-design.md`
- Last Verified: 2026-10-05

Main's authored council gateway now starts an actual five-Boss challenge using the
selected unlocked character, weapon and two time abilities. Every stage binds the
production Player, Boss, authored room, HostileFrameBridge, native Effects and its
own RunOrchestrator. No ordinary Profile settlement, currency or local leaderboard
entry is produced by this mode.

## Retained Behavior

The JSON catalog supplies the canonical five stages and validates the actual
Registry definitions and scene paths. Each entrance uses the approved fresh-stage
preset, including full health and reset cooldowns. Timing counts committed native
Player frames. A completion notice advances only when the bound actor, native
terminal runtime, health, source identity, positive frames and exact death receipt
agree; arbitrary emitted notices cannot clear a stage.

The physical challenge save is separate from Profile and local boards and binds
the actual content snapshot, save domain, Profile and mode fingerprint. Launch is
saved before native play, and completed stages are saved before advancement.
Ambiguous post-promotion results require equality with the actual primary. Failed
promotion retains the pending command and freezes combat for retry. Independently
loaded stale writers and interleaved promotion are refused; the actual Reload
control reconstructs the latest physical challenge boundary.

Explicit save-and-return preserves completed receipts and attempted elapsed time.
Continuation recreates the incomplete stage at its entrance preset, retaining all
earned stages and marking the attempt continued. Pause disables independently
processing Player descendants as well as the stage. Native construction failures
retain the durable active checkpoint and expose a continuation retry.

The actual Hub controls support Start, Continue, Next Boss, controller pause,
Resume, save retry, stale reload and return. Retired controls cannot restart active
combat. Saved and current loadouts are shown separately. Main uses the actual Boss
music cue and victory/defeat cue, and prevents content mutation while the mode is
open.

## Verification

Final command:

```sh
TEST_LOG_DIR=build/test-logs/p21a-boss-rush/final \
  ./tools/run_tests.sh --filter boss_rush --timeout 120
```

All six scene suites pass:

| Suite | Executable evidence |
| --- | --- |
| Native combat | Actual five-stage progression, bound actor identity, forged notice refusal, native death, unchanged Meta and physical victory reload |
| Six loadouts | All five characters, all five weapons and all six time pairs; actual weapons damage the bound Boss through real physics collisions |
| Guardian native hit | Actual Boss geometry damages an unguarded Guardian; timed perfect guard prevents that damage and earns Ward |
| Physical checkpoint | Continuation, earned receipts/time, Player death, launch/terminal pre/post-promotion faults, retry, stale and interleaved writers, physical reload and content mismatch |
| Main controller | Actual council gateway/start, retired callback refusal, mapped controller Start pause/focus, frozen timing, native death save retry and Hub return |
| Native layout | English/Chinese, text scale 1.0/1.5, 640x360/1280x720; usable mode menu/combat/pause/results controls |

Initial meaningful RED evidence remains under `native-red`, `checkpoint-red` and
`main-red` in `build/test-logs/p21a-boss-rush/`. Real collision failures are retained
under `loadout-collider`; the final six-loadout test verifies the separately owned
shared weapon-mask, swept-projectile and deferred Gauntlets collision fixes.

`main-hub-regression` passes all three relevant Main/Hub scenes. The final import
and native OpenGL render logs are `import-final.log` and
`native-render-final/godot.log`. All final engine/stdout logs were explicitly
scanned: no script, parse, resource or leak diagnostics. Sandboxed headless runs
retain the existing macOS certificate lookup diagnostic only.

There are 32 nonblank native screenshots in `build/p21a-boss-rush-screenshots/`,
covering menu, combat, pause and victory across all eight locale/scale/resolution
combinations. Latest Chinese 640x360 at scale 1.5 combat/pause and English
1280x720 victory were visually inspected; labels and controls fit without overlap.
Localization validation, document governance and `git diff --check` pass.
`python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt` reports no
known vulnerabilities. No dependencies were added.

## Remaining Scope And Recovery

This certifies the approved P21A native fresh-stage loop. The wider original 3.7
Boss Rush design still requires its 1.2 HP / 1.1 damage preset, carried Build and
health, inter-Boss reward choice, post-victory unlock gate, dedicated history/best
times and cosmetic/reward routes. This milestone retains only the latest session
and result. Optional global/friend boards are not configured.

Checkpoints are stage-boundary recovery, not mid-projectile cold restoration.
Explicit return retains attempted time; an abrupt crash resumes the last saved
boundary. Continued and assisted attempts are identified separately from fresh
unassisted attempts. P21B daily/authored modes and the actual five-floor endless
loop remain separate work; this change does not claim them complete.

The focused local commit is the rollback point. This milestone has not pushed,
published or used external accounts. Combined clean-checkout/export certification
is owned by the integration lane.
