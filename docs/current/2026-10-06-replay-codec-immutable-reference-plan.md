# Replay Codec Immutable Reference Plan

- Status: Implemented / Current
- Document Role: Current focused performance repair plan
- Authority Level: Below the approved full-product completion contract
- Applies To: Native replay worker chunk encoding and unchanged typed format
- Owner: Native matrix and codec lane
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-native-recording-snapshot-evidence.md`, `2026-10-06-replay-codec-difference-evidence.md`
- Exit Gate: Failing meaningful regressions pass, public rejection and exact physical corpus bytes remain unchanged, isolated timings demonstrate the benefit

## Observed Failure

The untouched `54866d4` actual Main P3 probe cannot retain its full 600-frame
recording. It fails with `RUN_REPLAY_RECORDER_CAPACITY` at frame 2741; only 239
measured samples and 240 total observations are retained. Its report is under
`build/retained-checkout/native-recording-after-54866d4-20261006/build/floor4-phase2-late-600/`.
The writer has not completed a 120-observation chunk before the next buffer
fills. Existing capacity and typed chunk format must remain unchanged.

The prior physical 240..359 corpus takes 8.701 seconds to encode: safety
traversal 3.918 seconds, difference traversal 3.526 seconds, and per-observation
snapshot digests 1.222 seconds. Those measurements used detached mutable data.
Measure the new recorder's readonly sharing separately before changing code.

## Execution

- [x] Freeze a separate `git archive 4a8fc6f` diagnostic; keep the original
  `be58030` failed 750-case archive and evidence untouched.
- [x] Validate and decode the retained physical 240..359 chunk, reconstruct
  readonly event sharing without changing any typed observation bytes, and
  measure existing encode stages.
- [x] Add failing contracts for repeated immutable-history throughput and
  correctness: first full validation, depth limits, same-count replacement,
  mutable and Packed aliases, freed Objects, typed containers and exact bytes.
- [x] Implement only a bounded, per-encode reference certificate. A first
  complete safety walk and recursive readonly/no-Packed proof are mandatory;
  a typed serialization/hash never proves safety. Reuse only identical retained
  references at a depth no deeper than their proved boundary.
- [x] Skip redundant difference serialization only when exact typed equality
  is established by compatible immutable references, preserving every patch,
  raw/compressed digest and byte. Leave public untrusted/decode validation cold.
- [x] Retain before/after stage measurements and original physical corpus
  hashes, run scoped codec/store/recorder regressions and strict log checks,
  and obtain independent review. Final focused scenes pass 2/2; all ten
  adjacent replay scenes pass, with both logs strictly validated per scene.
- [x] Create the focused local codec/test/evidence commit.

The actual shared corpus encode falls from 8,145,764 to 3,269,701 microseconds,
with every typed envelope field and compressed byte unchanged. Detailed
source hashes, RED/GREEN observations, retained paths and limits are recorded
in [immutable-reference evidence](2026-10-06-replay-codec-immutable-reference-evidence.md).

Root owns Main-thread work and `tools/p15/native_performance_probe.py/.gd`.
This lane owns `scripts/replay/run_replay_chunk_codec.gd`, its focused tests
and these documents. Diagnostics stay in the separate retained checkout.
An isolated speedup does not certify full sustained recording, 60 FPS, the
750 native matrix, unassisted victory, UI, exports or human playtests.
