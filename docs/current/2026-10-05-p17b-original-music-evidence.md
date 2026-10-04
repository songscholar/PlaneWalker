# P17B Original Music Evidence

- Status: Approved / Current
- Document Role: Current focused soundtrack verification evidence
- Authority Level: Verification below P17B original music design
- Applies To: Fifteen original loops, imported resources and actual Main playback
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p17b-original-music-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p17b-original-music.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Soundtrack assets and focused native/packed lifecycle verified; combined product certification separate
- Exit Gate: Byte reproduction, audio contracts, real Main and packed fixture pass without errors or leaks

Fifteen original stereo sources cover Hub, training, credits, victory, defeat,
five explorations and five boss battles. Each eight-bar composition has authored
scale, harmony, melody, bass and arrangement; pulse/battle cues add original
synthesized percussion. The standard-library score renderer and CC0 provenance
ship alongside the WAV manifest. No third-party samples or paid assets are used.

MusicDirector uses two players on the existing Music bus, validates every cue,
crossfades on a separate clock and freezes both players during pause. Source WAVs
are 16-bit PCM, 22050 Hz stereo; Godot's default QOA imports are supported by
validating decoded sample counts. Loop endpoints refer to decoded frames.
Stream references are released on exit. Main supplies a read-only context for
Hub, practice, active floor, uncleared boss, terminal phase and selected credits.
Profile, Run, Player replay and accessibility bus-volume authority are untouched
by playback.

## Verification

- Missing source/renderer RED: asset suite reported FileNotFoundError before implementation.
- Missing native director RED: `build/test-logs/p17b-music-red`.
- Asset contracts: 2/2 GREEN, exact regeneration of all files; all fifteen cues have distinct hashes, finite audible energy, peak below 0.80, duration above 15 seconds and quiet loop endpoints.
- Clean Godot import: `build/test-logs/p17b-music-import.godot.log`, no errors or leaks.
- Native lifecycle GREEN: `build/test-logs/p17b-music-native-final`, 1/1, no errors/leaks. All imported cues decode, interrupted fades and pause work, and actual Main starts Hub/Launch music with unchanged complete Player, Run and Profile snapshots.
- Actual OpenGL window: `build/test-logs/p17b-music-window.godot.log`, clean PASS.
- Actual PCK export and fixture: `build/p17b-music-runtime.pck`, `build/test-logs/p17b-music-export.godot.log`, `build/test-logs/p17b-music-packed.godot.log`; all cue resources and actual Main load from the pack, clean PASS.
- M1 compatibility: `build/test-logs/p17b-m1-compatibility`, 1/1 GREEN, no leaks. The explicit M1 laboratory still verifies five authored rooms and one terminal fact; it cannot settle an unissued production Launch or mutate its canonical Profile mirror.
- Actual training route: `build/test-logs/p17b-music-training`, 1/1 GREEN, verifies Main's training state selects and pauses its original training cue.
- Shared Main lifecycle regression: `build/test-logs/p17b-main-audio-drain-final`, 9/9 GREEN, no errors or leaks across soundtrack, checkpoint, training, Hub and terminal flows.
- Content export lifecycle: `build/test-logs/p17b-export-audio-drain`, 1/1 GREEN, no errors or leaks with the shared test shutdown boundary.

The initial compressed-stream contract refusal and immediate-exit asynchronous
audio-buffer leak remain diagnostic RED evidence. Native teardown now releases
stream references, and the common TestSuite shutdown waits 0.1 seconds for the
audio server to drain queued buffers before quitting. The log scanner continues
to reject errors and leaks. Technical checks do not replace listening feedback or actual player
evaluation. The local PCK is a focused fixture artifact, not a full-product
release certificate. Reverting the focused soundtrack commit removes this
presentation layer without changing save/content compatibility.
