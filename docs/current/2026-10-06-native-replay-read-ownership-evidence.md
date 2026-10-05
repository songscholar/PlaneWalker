# Native Replay Read Ownership Evidence

- Status: Implemented / Current
- Document Role: Current focused physical replay read ownership and memory evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Private whole-run replay decoded chunk caching
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-replay-read-ownership-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No FPS, complete RSS, rendered, soak, coverage or human certification

## Verified Cause And Change

Codec success results already transfer owned reconstructed data. Its production
code is unchanged. The two redundant full-chunk copies are in the Store: its
cold cache reception and its warm generic success projection. The Store now
adopts the decoded array directly and returns a private borrowed wrapper on a
cache hit. Only public `read` and `transition_rows` consume this helper, and
neither mutates borrowed data. Public results retain their detached copies.

Every cache hit still reads physical bytes and checks their exact length and
compressed hash before borrowing. Typed delta reconstruction, raw hash checks,
independent mutable frames, storage limits, manifest validation, recovery,
failure codes, reload and public outputs retain their original behavior.

## Real Native Diagnostic

The diagnostic reads the immutable `546779f` measured 601-observation tape at
`build/retained-checkout/native-unified-546779f-20261006/build/floor4-phase2-compared-late-600/isolated-files/plane_walker/run_replays/`.
Its primary manifest SHA-256 is
`3ed08d5546ae1068f96acb523de2546c06f1778996ed28f1a1da9d3536c816fa`.
The original Store source at `1c576ef` has SHA-256
`9ca6d59c9f3e2502abe0a7af842fc7f679e01f055f0a65325123f60c32d79f76`;
unchanged Codec SHA-256 is
`93fb3b27b95b9c385a2cb41982fc63ece03a3fe79c08fd8929a9ca133daea459`.

`build/replay-read-ownership-diagnostic/read_probe.gd` compares the original
Store with an isolated private-ownership prototype in separate Godot processes.
Both retain the full original `_read_chunk`, Codec and public single-frame
projection. Its SHA-256 is
`e58812975cd84c881e503b7591262e635eedfc2de59817bb0dd70f48f3a82e58`.
No diagnostic writes the frozen tape or changes production code before the
comparison. Existing native certification/matrix processes remain concurrent;
there is one diagnostic process at a time and no competing new heavy probe.

The exact late full chunk spans sequence 480 through 599, has 92,224 compressed
bytes, 3,851,564 raw delta bytes and compressed SHA-256
`091a2b8598ff4e12c5884353457e29303d782d3813edce0b0f9ba22df7f00f54`.
Its 120 reconstructed typed observations sum to 192,343,488 encoded bytes.
The selected public frame has 1,597,836 bytes and SHA-256
`605e44284f8a4fcb2989ee51cc63f2c45398a18b83638f4c58c735dc6083a683`
in both processes, including rereads after deliberate public caller mutation.

| Isolated Observation | Original Store | Private Ownership Prototype |
| --- | ---: | ---: |
| Cold single-frame read | 5,753.362 ms | 5,133.762 ms |
| Warm read 1 | 696.472 ms | 5.741 ms |
| Warm read 2 | 531.916 ms | 5.251 ms |
| Warm read 3 | 548.942 ms | 4.105 ms |
| Godot static allocation peak | 1,740,014,035 bytes | 944,345,699 bytes |
| Godot static allocation after cold read | 921,226,779 bytes | 921,227,251 bytes |
| Instantaneous macOS RSS after cold read | 2,232,254,464 bytes | 1,021,313,024 bytes |

Static allocation peak includes that diagnostic process's startup and reads.
RSS comes from `/bin/ps -o rss= -p <exact PID>` only at explicit observation
points, not a continuous sampler or absolute peak. Startup RSS differs between
processes; these isolated results do not prove the full game's RSS acceptance.
Raw paired logs pass strict runtime validation. Original stdout SHA-256 is
`abcf256088551bf2b5c52a59a1e9eb6cb66a52fb90b75cf75dd9ca6ecd6827a4`;
prototype stdout SHA-256 is
`009f720efb2882a519b958af9acba1947d0340a1c5b3557ab323636cbc316dd1`.

## Executable Ownership Contracts

`build/native-replay-read-ownership-red-2` fails only the cold and warm private
array-ownership assertions. Every other typed output, public isolation,
cross-frame independence, physical hash, cross-chunk, reload, corruption and
missing-file assertion passes. The earlier `-red` fixture wrongly accesses
`ContentValidationReport.ok`; its script failure was corrected to the actual
`has_blocking_errors()` API before the valid RED, and the invalid run is retained.

`build/native-replay-read-ownership-green` passes the complete focused scene.
It physically persists a complete 120-observation chunk plus a partial chunk
under a genuine admitted Player identity. Cold/warm private results share only
the retained array. Public mutation of nested dictionaries, typed arrays,
typed dictionaries, StringName keys and packed values cannot poison the cache,
adjacent decoded frames, future reads, transition rows or fresh Codec results.
Every observed cache hit performs an actual disk read. Corrupt and missing
physical bytes retain their original refusal codes, and restoration recovers
the original exact hash without changing the manifest.

| Contract | Retained Logs | Scenes |
| --- | --- | ---: |
| Focused private ownership and physical/public isolation | `build/native-replay-read-ownership-green` | 1 |
| Full replay, Codec, stream store, native recorder and library regression | `build/native-replay-read-ownership-replay-regression` | 34 |
| Actual package export/import and platform stream sharing | `build/native-replay-read-ownership-platform-stream` | 1 |

Verified paired stdout/Godot logs pass strict scoped validation without
unexpected script/parse errors or object/RID leaks. Godot is
`4.6.1.stable.official.14d19694e`; line coverage is unsupported. Independent
root review of production, all private consumers and the fixture finds no
actionable production issue.

## Integrated Native Recording Measurement

A clean detached clone at
`build/retained-checkout/native-unified-26a5d98-20261006/` freezes commit
`26a5d98129461b19ed87e40fdb837224bcc47441`. Its 410 production runtime files
retain aggregate SHA-256
`122604a98b824db92cb5078616f1b231715a139cdd6758ac06a0a6ec9b4070cd`
before and after the uninstrumented v2 probe. The report is retained at
`build/floor4-phase2-ownership-late-600/report.json`, SHA-256
`6362e6a60d8a7406939095244a9460bd1e1575074aaf60b633dcabaea49a6938`.
The runtime exits zero, does not time out, passes report validation and strict
paired log validation, and leaves the clone clean. Both stdout and Godot logs
have SHA-256
`8099b660d1fd97a405dff7e275d13fa8a0b433049d190737805cfae3bd0b8747`.

The first clean-checkout import exits zero but fails strict log validation:
configured generated `.translation` files do not exist before CSV import.
Those bootstrap errors are retained in `build/import-first.*.log`. A second
import exits zero and passes strict paired validation. Runtime log acceptance
does not erase this first-import limitation.

The actual twelve-frame Hub probe visits all nine functions. Sword reaches
floor-four phase two after 2,501 actual frames. All 600 consecutive measured
frames, 2,502-3,101, accept and retain 601 physical observations with honest
`INTERRUPTED` status and no recorder failure. Fresh physical endpoint reads
match the complete typed measured bytes. First SHA-256 is
`8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11`;
last SHA-256 is
`fd46d302787af37d90f09747b52e8faa08395e00b0505fc087edbc6c45ec105a`.
Both match `0843272` and `546779f`; this compares endpoints, not every
intervening observation.

| Actual v2 Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advance | 55.982 ms | 84.495 ms | 120.002 ms |
| Same-frame Player and Host work | 57.742 ms | 87.345 ms | 121.430 ms |
| Same-frame wall interval, including waits and observer | 67.887 ms | 101.707 ms | 144.314 ms |

The measured interval takes 40.733 wall seconds for ten native seconds;
physical retention takes 8.645 seconds. Observed peaks remain one actor, six
threats and three zones. Peak native static allocation is 705,691,240 bytes.
The exact macOS Godot PID 94712 has 1,691 valid 100-ms RSS samples and one
unavailable sample. Its sampled peak is 1,287,323,648 bytes across announced
startup, admission, recording and physical retention. The unavailable sample
is disclosed as `native process RSS sample is unavailable`.

The earlier integrated `0843272` source samples 2,242,150,400 bytes; this
combined frozen source samples 42.6% less and is below decimal 2 GB and binary
2 GiB in this scenario. Boss Actor control observation optimization is also
present, and existing matrix/certification workers remain concurrent, so this
pair does not isolate the Store change's individual timing or memory benefit.
The 16.667-ms frame budget still fails. Sampling does not prove an absolute
memory maximum or certify rendered FPS, sustained recording, saturation,
the 45-minute soak, complete UI or human testing.
