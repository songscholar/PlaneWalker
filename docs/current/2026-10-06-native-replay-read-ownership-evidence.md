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

## Full Native Measurement Remains Required

The integrated `0843272` 600-frame probe predates this Store change and samples
2,242,150,400 bytes of complete-process RSS. FPS and memory gates still fail at
that source. A new complete uninstrumented native recording and physical
endpoint readback must measure this slice's actual integrated benefit. No
isolated copy count, static peak or point RSS substitutes for that measurement,
rendered acceptance, sustained recording, the 45-minute soak or human testing.
