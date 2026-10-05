# P22C Streamed Run Replay Implementation Plan

- Status: Active / Current
- Document Role: Current focused implementation plan
- Authority Level: Below the streamed run replay specification
- Applies To: Codec, durable streams, automatic native observations and whole-run viewer
- Owner: Project integration lead
- Depends On: `../specs/2026-10-05-p22c-streamed-run-replay-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Strict codec, physical recovery, actual automatic capture, isolated native viewing and bounded long-run tests pass with clean logs

**Goal:** Record and expose an entire native Launch run within explicit budgets.

**Architecture:** RunReplayChunkCodec handles exact keyframe/delta bytes.
RunReplayStreamStore owns immutable chunks and physical manifest transactions.
NativeRunReplayRecorder observes accepted production state. A separate isolated
world/panel path reconstructs the recorded Player, room and hostiles.

**Tech Stack:** Godot 4.6.1, object-disabled Variant codec, Zstandard and SaveService.

## Current Implementation Detail

Whole-run presentation uses a private `PlayerReplayWorld` subclass with disabled
simulation, the actual authored room scene, production raster enemy and Boss
assets, and read-only hostile/effect geometry. It validates native observations
before replacing the visible world. `RunReplayLibrary` shares the existing panel
control contract; `ReplayLibraryRouter` lets Player packages and whole-run tapes
coexist without changing their formats. Timeline navigation is over accepted
observations, and retained transition bookmarks identify rooms and floors.

- [x] Run `tools/run_tests.sh --filter run_replay_library` to retain missing-viewer RED.
- [x] Implement private world, atomic seek, bounded chunk read cache and authenticated stream import/export.
- [x] Expose complete/interrupted/failed states and transition navigation in the native library.
- [x] Verify real production recording, private-world exact seek, no live mutation, package roundtrip and explicit deletion.

## Task 1: Exact Bounded Chunks

Files: `scripts/replay/run_replay_chunk_codec.gd`,
`tests/replay/run_replay_chunk_codec_test.gd` and its scene.

- [x] Write ResourceLoader-based missing-codec RED using actual Player snapshots.
- [x] Run `tools/run_tests.sh --filter run_replay_chunk_codec` and retain RED.
- [x] Implement encode(Array[Dictionary]) and decode(Dictionary) with checked budgets and immutable copies.
- [x] Verify type changes, nested additions/removals, empty dictionaries, malformed rehashed deltas and exact byte digests.
- [x] Retain passing evidence and focused codec commit.

## Task 2: Physical Streams

Files: `scripts/replay/run_replay_stream_store.gd`,
`tests/replay/run_replay_stream_store_test.gd` and its scene.

- [x] Define missing-store RED for actual multi-chunk writes, physical restart and random seek.
- [x] Implement configure, begin, append, finish, reload, rows, read and remove using bound SaveService CAS.
- [x] Verify stale writers, promotion faults, missing/corrupt files, incomplete state and compressed run budgets.
- [x] Retain the physical stream boundary before automatic capture changes.

## Task 3: Automatic Production Capture

Files: `scripts/replay/native_run_replay_recorder.gd`, `scripts/main.gd`,
actual native replay integration scenes and documentation.

- [x] Define missing-recorder RED from actual native Main; expand subsequent real room/reward/terminal assertions during implementation.
- [x] Observe committed frames and flushed authoritative native state; append exact complete observations.
- [x] Keep capture failure independent from gameplay and classify interrupted recordings explicitly.
- [x] Verify actual rejected-frame rollback adds no observation and fresh reload preserves the exact tape.
- [x] Retain slow-disk RED, move automatic chunks to one bounded background writer, and verify saturation keeps Player frames active and shutdown joins pending failure.

## Task 4: Complete Native Viewing

Files: whole-run isolated world/controller, library projection/panel and native visual tests.

- [x] Define RED for private actual room/hostile reconstruction and seek across room/floor boundaries.
- [x] Expose complete/incomplete recordings without conflating snapshot viewing with simulation.
- [x] Verify live state/facts remain unchanged, physical controller controls and supported resolutions.
- [x] Run synthetic 45-minute physical storage and throughput budgets, retaining exact hashes and clean logs.
- [ ] Complete separate actual 45-minute gameplay and concurrent recording evidence; retain final milestone review.

Focused evidence: `../../current/2026-10-05-p22c-native-run-replay-evidence.md`.
The final long native run and combined clean-checkout gates remain open.
