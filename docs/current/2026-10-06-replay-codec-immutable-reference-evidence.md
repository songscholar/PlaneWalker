# Replay Codec Immutable Reference Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native replay worker chunk encode, safety admission and exact typed differences
- Owner: Native matrix and codec lane
- Depends On: `docs/current/2026-10-06-replay-codec-immutable-reference-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No sustained recording, full matrix, unassisted victory, FPS, UI or human playtest certification

## Failure And Production Change

The untouched `54866d4` actual Main P3 probe refuses frame 2741 with
`RUN_REPLAY_RECORDER_CAPACITY`. The probe has 239 accepted measured frames and
the recorder has counted 240 observations. Its retired physical FAILED entry
contains only one completed 120-observation chunk: an in-memory recorder count
does not establish physical retention. The worker has not finished the next
120-observation chunk before the next buffer fills.
The retained report is
`build/retained-checkout/native-recording-after-54866d4-20261006/build/floor4-phase2-late-600/report.json`.
This change leaves buffer sizes, the public codec API and chunk format intact.

Each encode owns an independent certificate Dictionary with separate Array and
Dictionary buckets, bounded to 256 retained references each. A reference is
remembered only after the original complete safety admission and a recursive
readonly/no-Packed proof. Exact `is_same` identity is required, and reuse is
allowed only at a depth no deeper than the certified boundary. Certificate
lookups stop at depth 3; the original depth-32 safety limit remains authoritative.
Packed or mutable descendants always use the cold safety path. Decoder and
public untrusted validation do not receive certificates. No serialization,
digest, global cache or loose equality establishes safety.

Compatible dictionary type metadata and ordered keys now permit child
differences before whole-parent serialization. Readonly Array wrappers can skip
equality serialization only when their admitted container children have exact
identity and their scalar/vector/Color values have identical `var_to_bytes`.
Typed metadata, insertion order, patches, raw/compressed SHA-256, compression
and cold reconstruction stay unchanged.

Production codec SHA-256 is
`93fb3b27b95b9c385a2cb41982fc63ece03a3fe79c08fd8929a9ca133daea459`.
The new contract script and scene hashes are, respectively,
`336ee49467c5e3851339011a9c2cf2364763191630fe3b9544cc8b3bc0975717`
and `cf8baf2cc5d0b50ee1e57b9e389972835cf11915970e7ec4d9fdbe646d2b8658`.

## Meaningful RED And GREEN

`tests/replay/run_replay_chunk_immutable_test.tscn` checks 120 observations with
shared recursively readonly history against detached mutable history. It
compares the complete typed envelope and compressed bytes, reconstructs exact
cold bytes, and checks caller isolation. Additional contracts cover same-count
replacement and append, depth-boundary reuse, mutable and Packed aliases,
freed-Object/null serialization collisions, typed roots and arrays, key order,
StringName/String keys, unsafe float keys and independent parallel workers.

- Throughput RED: `build/replay-codec-immutable-red/`. Only the intended
  throughput assertion fails: detached 1,970,312 / shared 1,928,193 microseconds.
- Signed-zero RED: `build/replay-codec-signed-zero-runtime-red/`. An intermediate
  loose scalar comparison fails exactly the compressed-byte and cold-readback
  assertions. The actual negative-zero fixture is constructed from IEEE bytes
  with `PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)`;
  the earlier `-0.0` literal fixture normalized and is not counted as RED evidence.
- Final focused GREEN: `build/replay-codec-immutable-final-green/`. Both original
  codec and new immutable scenes pass, with detached 1,795,283 / shared 291,279
  microseconds. Both stdout/engine pairs pass strict error/leak validation.
- Adjacent GREEN: `build/replay-codec-immutable-regressions/`. All ten scenes
  pass: backpressure, native recorder, terminal recorder, budget, codec,
  immutable sharing, history, library, projection and physical stream store.
  Each stdout/engine pair passes `tools.runtime_log_validation` independently.
  The immutable scene observes detached 1,778,644 / shared 295,050 microseconds.

The adjacent command uses the existing workspace-scoped portable Godot editor:

```sh
TEST_LOG_DIR="$PWD/build/replay-codec-immutable-regressions" \
  ./tools/run_tests.sh --filter run_replay --timeout 180
```

The independent progress-validation reviewer reports no remaining correctness
finding and confirms the production/test hashes, physical corpus fields and
restricted certification claims. Its signed-zero confirmation is retained under
`build/test-evidence/codec-immutable-review/signed-zero-final-green.*`.
Godot is `4.6.1.stable.official.14d19694e`; stock scene coverage is explicitly
unsupported. No dependency changes are part of this repair. The previously
retained pinned requirement audit reports no known vulnerabilities at
`build/test-evidence/void-phase-regression/pip-audit.json`.

## Actual Physical Corpus

The diagnostic is a separate `git archive 4a8fc6f` extraction at
`build/retained-checkout/replay-codec-immutable-4a8fc6f-20261006`.
Its `tools/p15/replay_codec_immutable_probe.gd` and stage timers exist only there;
the final diagnostic codec differs from production only by encode stage timers.
Fresh two-stage import retains both logs. Approved bootstrap translation errors
are classified with remaining errors 0; the second import is strictly clean.

The source is the third physical chunk under
`build/retained-checkout/projectile-scalar-after-4735176-20261006/build/floor4-phase2-late-600/isolated-files/plane_walker/run_replays`.
It contains sequences 240..359 and actual Player frames 2741..2860. The driver
first validates and decodes the physical chunk, reconstructs readonly sharing,
checks every observation's exact typed bytes, and reuses 13,804 event references.
Both candidates match every typed envelope field and every compressed byte.

| Isolated Encode Stage | Before ms | Final ms |
| --- | ---: | ---: |
| Complete encode | 8145.764 | 3269.701 |
| Safety traversal | 3702.675 | 1243.301 |
| Difference traversal | 3249.789 | 846.805 |
| Snapshot digest | 1158.939 | 1144.620 |

This one before/after pair observes a 59.9% total reduction on a shared host.
Records are `build/readonly-before.json` and `build/readonly-final.json` in the
diagnostic archive; both stdout/engine pairs pass strict validation. The
intermediate `readonly-after.json` is a superseded prototype, not final evidence.
Instrumented codec hashes are
`ef09a6bf687a65ed42f688b90eda4aa2e3c8d5d8805925092ac227dc752dbc4e`
and `7b68f0494ae55a58451d98c9f57d4a7a38e168f9c028a3c7431a65a67960d200`.

Original and both final candidates retain raw SHA-256
`98eab2dcf87b89fba466d7f360297d5a97a6984d9d1701e64dfb870a61245b03`
and compressed SHA-256
`38e5385d4d1334fc22145ad3ed269b871a179addb16afc46b42256dbc76d178d`.
Snapshot digests still cost approximately 1.14 seconds per measured chunk.

## Remaining Product Gates

This certifies focused encode correctness and an isolated improvement. It does
not show that the actual concurrent recorder can sustain this workload without
capacity refusal, satisfy the 16.667 ms gameplay frame budget, render at 60 FPS,
or stay inside its final memory budget. A new actual Main probe from a unified
committed source remains required. The unchanged original `be58030` 750-case
matrix finished with five failures and is not promoted by these contracts.
UI implementation remains behind the gameplay gate, and human playtests remain
uncertified.
