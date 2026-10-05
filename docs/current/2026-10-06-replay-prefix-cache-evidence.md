# Replay Prefix Cache Evidence

- Status: Focused Verified / Native frame performance pending
- Document Role: Current verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: ReplayRecorder exact-source digest caches
- Owner: Plane Walker verification lane
- Depends On: `2026-10-06-replay-prefix-cache-plan.md`
- Last Verified: 2026-10-06

## Correctness

The helper RED fails precisely because the bounded cache is absent, after an
initial test-script constant expression error was corrected. Its logs are in
`build/replay-exact-cache-red-clean`. Both new scene tests pass with strict
stdout and engine error/leak scanning. The complete 29-scene replay suite passes
in `build/replay-cache-regressions`, including native automatic recording,
physical stream persistence, complete Player restoration, weapon external
facts, Gun completion variants, and observable restore atomicity. An additional
freed-Object collision regression passes in
`build/replay-prefix-cache-freed-object`.

Two independent read-only reviews found no remaining blocking issue. One
review identified that Godot's hexadecimal predicate accepts signed and
uppercase strings. The helper now enforces the original lowercase SHA syntax;
the repaired guard and its regression pass in the complete replay suite.

The caches retain only certified positive String results, keyed by complete
privately owned typed source bytes. Mutex-protected FIFO storage has separate
entry and source-byte bounds. Prefix storage permits 128 entries / 16 MiB;
capture storage permits 4096 entries / 16 MiB. Each digest has fixed length 64,
so digest and per-entry overhead are also bounded. Miss calculation runs outside
the mutex. Oversized or unsafe sources take the original algorithm path.

Canonical roots, public schemas, prefix history and detached caller state are
unchanged. A selected non-Dictionary prefix now explicitly refuses instead of
indexing the empty ordered array. The original valid count-zero behavior,
ignored unsafe extra fields, typed containers, StringName, canonical-equivalent
numeric variants, append/replacement/truncation/restore and parallel independent
calls are exercised against a retained copy of the old algorithm.

## Performance Limits

The isolated microbenchmark uses the actual physical frame-2741 history:
116 events / 1,246,548 typed bytes. Ten calls per case preserve canonical SHA
and caller source bytes, with strict logs. Results are retained under
`build/retained-checkout/replay-codec-diagnostic-4735176/build/prefix-cache.json`.
These are diagnostic timings on a shared host, not FPS certification.

| Case | Existing median | Cache median |
| --- | ---: | ---: |
| Cold caches | 168.199 ms | 254.813 ms |
| Repeated identical source | 163.046 ms | 45.305 ms |
| Appended event | 165.074 ms | 137.638 ms |
| Replaced event | 160.893 ms | 132.093 ms |

Warm reuse removes repeated canonical hashing, but copying, serializing and
walking full history remain above the 16.667 ms frame budget. Cold cost is higher.
The next repair must use privately owned immutable history certificates to
avoid repeated work while preserving full public snapshots. This focused
change does not close the native gameplay performance gate.

## Rejected Shortcut

A separate Godot 4.6.1 probe demonstrates that default `var_to_bytes` silently
serializes a freed Object to exactly the safe-null bytes, including nested
arrays and dictionaries. Raw bytes cannot authenticate safety before the
original safety walk. Probe source and strict logs remain under
`build/test-evidence/digest-cache-audit/unsafe-serialization.*`; the production
cache retains the safety checks and its regression refuses the warmed collision.

## Remaining Certification

The 26-scene integration save regression is running separately. Frozen old
485-scene and 750-case jobs retain their original sources and reports. Their
results cannot certify this focused revision. An untouched frozen native probe,
sustained rendered recording, final clean full-suite/export certification,
UI completion and all 20 human playtests remain pending.
