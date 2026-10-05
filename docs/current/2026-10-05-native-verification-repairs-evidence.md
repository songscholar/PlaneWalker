# Native Verification Repairs

- Status: Verified Locally / Combined certification pending
- Document Role: Current runtime verification repair evidence
- Authority Level: Below the full product completion specification
- Applies To: Released semantic targets, lifecycle facades, actual run pause and audio cleanup
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

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

## Durable Records Stress Budget

The frozen certification's local record scene timed out at the default 90 seconds.
The same actual physical scene passes with an explicit 300-second budget in
`planewalker-tests.TE9bGd`; its log timestamps span approximately 150 seconds.
It retains and validates 1000 queued settlement records, producing an 8.65-MiB
profile. This scene now receives a 300-second minimum, alongside the existing
native combat checkpoint exception. The queue size, validation and failure/leak
gates are preserved. Default invocation GREEN: `planewalker-tests.FjyjkD`.

The complete native content migration scene passes at an explicit 300 seconds in
`planewalker-tests.pwF1EB`, with approximately 96 seconds between log creation and
completion. Its five actual physical fixtures, trusted historical migration and
forged-signature refusals remain intact. It now receives the same scene-specific
300-second minimum. Default invocation GREEN: `planewalker-tests.NcjsTZ`;
the complete fixture passes without an explicit timeout override.

## Limits

- The frozen full certification remains an immutable diagnostic run, not a certification of these later repairs.
- An exploratory event invocation without explicit log isolation encountered Godot's macOS rotating-log crash. The isolated verbose invocation specified its engine log and is the accepted diagnostic evidence.
- Boss Watch's matching deferred Gauntlets fixture repair is retained separately in `09e5774`; Ruin wall validation and its fixture repair are in `5aac34d`.
