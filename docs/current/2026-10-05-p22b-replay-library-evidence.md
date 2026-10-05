# P22B Native Replay Library Evidence

- Status: Focused Verified / Combined certification pending
- Document Role: Current milestone retention evidence
- Authority Level: Below the P22B replay library specification
- Applies To: Physical local recordings, isolated snapshot playback, native Hub entry and controller controls
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22b-replay-library-design.md`, `../superpowers/plans/2026-10-05-p22b-replay-library.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual library, identity/history, physical input, native visual and Main integration tests pass with clean logs

## Retained Behavior

Main owns a physical replay library and an independent native viewing panel.
The Hub Archive opens it and restores Archive focus on return. Viewing locks
content activation, hides Hub travel and releases its private Player on close.
Fresh Main instances reload the physical archive; no replay command changes
the live Profile. Import validates the entire bounded package before mutation,
exports remain inside application storage, and deletion requires confirmation.

All five characters, all five weapons, recorded initial Meta stats and nondefault
generation reconstruct only in an admitted disabled ReplayWorld. The native
viewport renders the actual sprite and recorded payloads. Pause, seek, restart
at the end and 0.5/1/2 speed present exact validated snapshots.

World invalidation history may move backward only for the admitted independent
Player with no physics processing or hostile participant. Live, shared-world,
reparented and wrong-authority cases refuse all three restoration entry points.
Full Health restoration validates reward-owned and other invulnerability as one
target pair, including token-owner changes. Crossed token sets and differing
token ceilings refuse atomically. Ordinary reward restoration preserves its
live protection boundary. Stale physical archive duplicate writes also refuse.

Explicit project menu bindings retain keyboard confirmation, arrows and Esc,
and add controller A/B, D-pad and left stick. Replay selectors support horizontal
cycling. Retired selector, slider, speed and action callbacks cannot mutate a
replacement view. File and confirmation windows own cancellation; controller B
first cancels a visible dialog without closing the library or deleting data.

## Verification

- Actual Main controller B RED: `planewalker-tests.wMIKNx`; its diagnostic
  confirmed that the previous ui_cancel defaults contained only Esc.
- Physical selector/speed/delete input RED: `planewalker-tests.WFR8mA`.
- Actual Main entry, exact seek, content lock and controller return GREEN:
  `planewalker-tests.DvqzED`.
- Final complete replay suite GREEN: `planewalker-tests.RlhLVV`, 18/18 scenes,
  including paired Health history, strict live refusal and stale-control tests.
- Final native UI suite GREEN: `planewalker-tests.KXBE0a`, 20/20 scenes with the
  explicit project controller mappings.
- Final OpenGL native panel test GREEN, including physical controller input,
  at `build/test-logs/p22b-replay-final-visual.godot.log`. Screenshots at 640x360,
  1280x720 and 1920x1080 and the isolated Player image are retained under
  `build/test-logs/p22b-replay-final-visual/`. Bounds and center-pixel diversity
  checks pass; the native image was also visually inspected.
- Accepted logs have no script, invalid-call, resource or ObjectDB/RID leak
  diagnostics. Direct pinned development and coverage dependency pip-audit
  reports no known vulnerabilities.

## Remaining Scope

This library presents validated Player snapshots. Automatic complete-run capture,
hostile/room/economy recording, long-run compression and native whole-run replay
certification remain required. These tests do not certify online leaderboard
scores, complete real combat, line coverage or human playtest gates. The next
immutable combined checkout must independently pass validation, instrumented
coverage, retained release export and packaged startup.
