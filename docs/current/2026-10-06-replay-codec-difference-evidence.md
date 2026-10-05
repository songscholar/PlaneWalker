# Replay Codec Difference Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Whole-run replay chunk codec root difference comparison
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-replay-codec-difference-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Production Change

The encoder validates each observation's integer sequence against the admitted
first sequence plus its index before calculating differences. Adjacent admitted
observations therefore cannot have equal typed bytes: their sequence fields are
different. The encoder now skips that one root equality comparison. Every
recursive child call still compares complete typed bytes, and all safety,
dictionary type/order checks, patch construction, snapshot SHA-256, schema and
compression behavior remain unchanged.

The change is confined to the encoder call, its orienting comment, and the
optional root comparison argument in `run_replay_chunk_codec.gd`. There is no
production safety shortcut, historical data removal, or replay format change.

## Actual Physical Corpus

The isolated diagnostic is retained at
`build/retained-checkout/replay-codec-diagnostic-4735176-20261006`. Its source is
the third physical chunk in the uninstrumented actual Main P3 tape retained at
`projectile-scalar-after-4735176-20261006/build/floor4-phase2-late-600/`.
It contains 120 actual observations, sequences 240 through 359, player frames
2741 through 2860. The driver validates and decodes the complete physical chunk
before reencoding. It compares every typed envelope field individually and the
compressed bytes, because the metadata JSON dictionary's insertion order is not
an envelope-byte contract.

The original and both candidate outputs retain raw SHA-256
`98eab2dcf87b89fba466d7f360297d5a97a6984d9d1701e64dfb870a61245b03`
and compressed SHA-256
`38e5385d4d1334fc22145ad3ed269b871a179addb16afc46b42256dbc76d178d`.

| Isolated Stage | Baseline ms | Root Comparison Skip ms |
| --- | ---: | ---: |
| Complete encode | 9803.733 | 8700.941 |
| Safety traversal | 3896.555 | 3917.738 |
| Difference traversal | 4711.738 | 3526.443 |
| Snapshot digest | 1161.044 | 1221.715 |
| Keyframe copy | 3.326 | 3.521 |
| Payload encode | 16.213 | 15.418 |
| Compression | 1.248 | 1.250 |
| Output digests | 8.709 | 9.645 |

These are one before/after diagnostic pair on a shared host. The observed total
falls 11.2% and difference cost 25.2%, with unchanged physical bytes. They are
neither a sustained-performance certificate nor a frame-rate claim. The records
are `build/stages-before.json` and `build/stages-distinct-after.json`; their stdout
and Godot logs pass the strict runtime error/leak validator.

An earlier isolated scalar dispatch candidate has no meaningful safety gain
(3896.555 to 3887.786 ms; total encode 9962.241 ms). Its evidence is retained in
`stages-scalar-after.json`, and it is not present in production.

## Focused Contracts and Review

The existing codec contract passes before the change in
`build/replay-codec-difference-before-20261006`. After the change, all three
focused scenes pass strict stdout/Godot script-error and object/RID-leak checks:

- Codec: `build/replay-codec-difference-after-20261006`.
- Physical stream store: `build/replay-codec-difference-stream-20261006`.
- Actual native recorder: `build/replay-codec-difference-recorder-20261006`.

The scenes cover actual typed Player snapshots, integer versus float and
StringName distinctions, typed arrays/dictionaries, caller mutation isolation,
unsafe and nonfinite rejection, malformed/overlapping paths, corruption, chunk
budgets, sequence limits, physical readback, and real recording boundaries.
Godot is `4.6.1.stable.official.14d19694e`; line coverage is unsupported.

The independent progress-validation lane's read-only review finds no actionable
issue. Its sequence proof confirms that only the necessarily different root is
skipped, and every recursive equality/type/order decision remains in place.

## Readonly Sharing Feasibility

`build/readonly-sharing.json` and its strict logs retain a separate isolated
Godot experiment. A 216-byte typed fixture includes nested dictionaries/arrays,
StringName keys, typed Vector2 arrays and packed bytes. Recursive freeze leaves
typed bytes unchanged. Deep duplicate produces mutable detached descendants;
caller mutations of nested, typed and packed values preserve the private source.
Two private observations share frozen history. Worker encoding exactly matches
encoding detached observations, and decoded caller mutation is also isolated.

This establishes detached-copy and worker encoding mechanics for this fixture,
not a completed native recorder optimization. Dictionary/Array read-only flags
do not seal Packed-array descendants: a directly retained Packed alias can
still be mutated without changing the containing Dictionary reference. The
production journal therefore needs a cold fallback for Packed descendants until
leaf ownership is separately proven. It must also seal every supported event
installation, append and replacement path, preserve run/frame identity, and keep
public snapshots detached. Native recorder changes belong to the parent lane.

`build/packed-history-scan.json` recursively scans every value in the actual
physical frame-2741 history. It finds zero Packed types/paths among its 116 events
and 1,246,548 bytes. Counts are Array 2055, Dictionary 8976, String 7302,
StringName 971, Vector2 580, bool 1813, float 3648 and int 10522. History typed-byte
SHA-256 is
`cc6dbd42df03c4ac1e8fbd499a55017fa9c1a3d4e68c8c2e1839d8f289999fec`.
The physical chunk hashes are validated before extraction, source bytes remain
unchanged after scanning, and strict runtime error/leak checks pass. This only
describes that measured history, not every supported event payload.

## Prefix Cache Microbenchmark

The parent lane's then-current Recorder source is copied into the isolated
diagnostic, with source SHA-256
`4347869f62ef7ee2df48a2bd400fa7565a24b1db095ac36ea4e5264766d6ab90`.
`build/prefix-cache.json` uses the physical frame-2741 keyframe's 116 events,
1,246,548 typed bytes. Each case has ten measurements of current and copied
legacy prefix functions. Cold clears both caches; warm primes the same history;
append and replacement prime the original then modify a detached candidate.
Every canonical root matches the legacy result and the physical source is
unchanged. Baseline root is
`bfc13fa2ae535a46e49f85df6c8c442e7570d6b72a37fdafcab38b5dd8a8ddd3`.

| Case | Current Median ms | Legacy Median ms |
| --- | ---: | ---: |
| Cold | 254.813 | 168.199 |
| Warm | 45.305 | 163.046 |
| Append | 137.638 | 165.074 |
| Same-slot replacement | 132.093 | 160.893 |

Warm prefix cache hits once; append reuses 116 captured event digests and
replacement reuses 115. The tested budgets are prefix 128 entries / 16 MiB and
capture 4096 entries / 16 MiB. Strict logs pass. Repeated history benefits, but
the warm 45.305 ms path and slower cold path show why the remaining journal
copy/safety/canonical work still blocks the 16.667 ms runtime frame budget.
