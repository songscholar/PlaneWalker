# Native Verification Repairs

Date: 2026-10-05

## Retained behavior

- Delayed terminal cleanup reads bound targets as Variant and checks validity before calling target methods. A native Actor that has actually died and been freed cannot block cleanup of a surviving Player's semantic slowdown.
- The semantic regression uses actual Health damage, the actual native death retirement, the public effect aggregate and the real Player modifier projection. Cleanup preserves unrelated modifiers, clears finite status ownership and remains idempotent.
- Both lifecycle publication test facades accept the production three-argument `start_run(config, run_id, progression_projection)` contract. Their first-room rejection, synchronous clear and synchronous failure publication assertions remain intact.
- The pause integration fixture enters a real accepted Main compatibility run before asserting paused and resumed enemy/projectile/room processing. The raw Host HUD contract fixture explicitly enables its run presentation before checking the authoritative clock projection.
- Event encounter teardown tracks active music playbacks through weak references and waits at most twenty 10ms timer steps for the independent AudioServer mix thread to release them. It asserts completion before process exit; music behavior and native event assertions are unchanged.

## Evidence

- Frozen certification at `a26b674` exposed lifecycle signature errors, the inactive-room pause fixture and the event test's ObjectDB leak in `build/test-logs/native-collision-replay/validation.stdout.log`.
- Lifecycle full suite GREEN: `planewalker-tests.r6lJuJ`.
- Released semantic target clean RED: `planewalker-tests.WfpJq2`. Actual final death had completed, and both `_status_checkpoints` and `_apply_statuses` produced the expected previously-freed typed-assignment script errors before the guard.
- Full semantic effects suite GREEN after guard: `planewalker-tests.IDUm7C`.
- Actual runtime Host suite GREEN: `planewalker-tests.F9EVZl`.
- Isolated event leak diagnosis: `build/test-logs/qa-event-leak/verbose.log`; the pre-fix test passed its gameplay assertions but retained AudioStreamWAV and AudioStreamPlaybackWAV at exit.
- Native event encounter GREEN after bounded playback release check: `planewalker-tests.hmzL5l`.
- All accepted focused logs were scanned for script/deferred errors, physics-query mutation, invalid calls and ObjectDB/RID leaks. No such failures remained.
- Stock Godot focused runs report `godot_line_coverage_unsupported`; this evidence does not claim a line-coverage percentage.

## Limits

- The frozen full certification remains an immutable diagnostic run, not a certification of these later repairs.
- An exploratory event invocation without explicit log isolation encountered Godot's macOS rotating-log crash. The isolated verbose invocation specified its engine log and is the accepted diagnostic evidence.
- Boss Watch's matching deferred Gauntlets fixture repair is retained separately in `09e5774`; Ruin wall validation and its fixture repair are in `5aac34d`.
