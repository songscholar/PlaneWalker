# P22C Native Run Replay Evidence

- Status: Focused Verified / Full program active
- Document Role: Current milestone retention evidence
- Authority Level: Evidence below the approved full-product and P22C specifications
- Applies To: Automatic recording, physical whole-run archives and private native viewing
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22c-streamed-run-replay-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual recording, private native seeking, physical recovery, supported resolutions and focused regressions pass with clean logs

## Delivered

Main records accepted Launch frames, room/floor transitions and terminal state
into exact compressed chunks. Rejected native frames do not enter the tape.
Recording failure leaves gameplay active and displays a bounded notification.
Restored or interrupted sessions retain their honest incomplete classification.

Automatic chunk compression and physical writes use one background worker with
a strict two-chunk bound. A blocked physical promotion stops recording once the
buffer fills, publishes one failure, and leaves actual Player frames active.
Retirement joins the pending writer before classifying the partial tape. The
explicit flush/terminal/retirement paths may wait for disk; accepted combat
frames never wait for a physical batch. Main excludes archive mutation until
the live recorder releases ownership.

The native Archive combines Player packages and whole-run streams. Selection,
timeline seek, playback speed, transition navigation, import, authenticated
export and explicit deletion use the physical store. Removing an unselected
tape preserves current playback. Chunk reclamation authenticates primary,
pending and both recovery manifests before deleting unreferenced managed files.
Concurrent multiprocess reservations and garbage collection are not certified.

RunReplayWorld reconstructs the actual disabled Player in a private World2D
and event bus. It projects the authored room, production hostile/Boss raster
assets, roots, covers, walls, payloads, semantic zones and actual telegraph
geometry. Whole-run seek can cross accepted Rewind and death/reset tombstones
in either direction only within the private disabled world. Cold gameplay
restore may rebase matching tombstone revisions upward, while changed reasons,
missing history and revision rollback refuse.

Player/atlas/stage replacement publishes only after candidate validation.
Invalid cosmetic selection preserves the previously visible avatar. Viewing
does not alter live Player state, progression or global gameplay facts.

## Evidence

- Missing viewer RED: `build/test-evidence/run-view-red`.
- Review RED: `build/test-evidence/run-view-review-red`.
- Actual production recording, router selection, failed cosmetic atomicity,
  package roundtrip and deletion/reclamation: `build/test-evidence/run-view-review-green`.
- Full existing replay suite: `build/test-evidence/replay-final`, 24/24 scenes.
- Background-worker whole replay suite: `build/test-evidence/replay-worker-suite`,27/27 scenes.
- Actual Rewind followed by actual Health death and private backward restore:
  `run_replay_history_test` in that suite, including shared-world and enabled-Player refusal.
- Domain-backed translated roots/covers, semantic raster zone, cone projection
  and leak regression: `build/test-evidence/run-projection-green-2`, 1/1.
- Slow disk RED and native background write GREEN:
  `build/test-evidence/replay-async-{red,green}`. The 250 ms physical delay
  does not enter the accepted frame; exact cold reads and error isolation pass.
- Blocked-promotion saturation RED and GREEN:
  `build/test-evidence/replay-backpressure-valid-red` and
  `build/test-evidence/replay-backpressure-green`. The test drives real Player
  frames while disk is gated, checks both 120-entry bounds, and joins the worker
  through actual Main retirement with FAILED classification.
- Native OpenGL rendering: `build/test-evidence/run-replay-native-final.godot.log`.
  Captures under `build/visual-evidence/run-replay-native-final/` cover
  640x360, 1280x720 and 1920x1080. Framebuffer checks require nonblank actual
  raster/room colors. Logs contain no script errors, warnings or engine leaks.
- Latest native viewer after background integration and enlarged preview:
  `build/test-evidence/run-replay-native-async.godot.log` and captures under
  `build/visual-evidence/run-replay-async/`, with the same three resolutions and
  framebuffer checks. The earlier `run-replay-native-resume.godot.log` was
  rejected because it began during an incomplete Daily source edit.
- Synthetic162000-observation physical capacity: `build/test-evidence/replay-budget-45m/report.json`,
  1350 chunks,45117332 compressed bytes, exact first/last hashes and412888049
  peak static bytes. The2.389-second maximum promotion exceeded the2-second
  buffer window, so this is capacity evidence only. Deferred-reclamation RED/GREEN:
  `build/test-evidence/replay-reclamation-{red,green}`. Continuous append retains
  orphan bytes; terminal and explicit archive boundaries authenticate all recovery
  manifests before reclamation. Physical quota checks still count every file.

## Remaining Gates

These are focused functional and presentation gates. A complete native
45-minute five-floor playthrough, long-run recording performance, final
combined clean-checkout certification, exact-source runtime line coverage and
retained platform exports remain separate gates. Storage COMPLETE describes a
finalized tape; only the production recorder's terminal checks establish a
complete native run. No human playtest evidence was created.
