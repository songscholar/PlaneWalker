# P22C Run Replay Chunk Codec Evidence

- Status: Focused Verified / Partial milestone
- Document Role: Current bounded replay codec evidence
- Authority Level: Below the P22C streamed run replay specification
- Applies To: Exact keyframes, structured dictionary deltas and bounded compressed bytes
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22c-streamed-run-replay-design.md`
- Last Verified: 2026-10-05

The codec retains at most 120 observations in one Zstandard-compressed chunk.
Every chunk declares exact sequence bounds, raw/compressed lengths and byte
SHA-256. Decompression is limited to 32 MiB; compressed input is limited to
8 MiB. Objects and object-typed containers, excessive depth and nonfinite
numeric values refuse before encoding. Decoding never enables Object creation.

A complete keyframe precedes deterministic dictionary differences. Ordered
key changes and typed-dictionary changes use complete subtree replacement.
Arrays and packed arrays retain their exact types. Delta admission rejects
duplicate/overlapping paths, absent deletions, missing ancestors, noncontiguous
sequences and mismatching reconstructed byte digests. Returned observations
are independent from encoded storage and callers' native snapshots.

Clean missing-codec RED: `planewalker-tests.klR2tG`. Final actual native Player
codec GREEN: `planewalker-tests.PL4izw`. The scene exercises precise integers
and floats, String/StringName, typed arrays/dictionaries, vectors, nested
insertions/deletions, corrupted bytes and correctly rehashed malformed deltas.
Logs contain no script/resource/invalid-call or ObjectDB/RID leak diagnostics.

Independent review found malformed deltas could target typed dictionaries with
an incompatible key or value, and the last sequence could exceed the encoder's
integer limit. Checked destination admission and the decode upper bound now
refuse before Godot lookup or assignment. Typed key ordering compares equivalent
untyped key lists without losing the actual encoded dictionary type. The added
regressions pass in `planewalker-tests.0gknL8` with clean runtime logs.

This is a codec boundary, not whole-run completion. Physical manifests,
automatic native capture, hostile/room/economy tape, long-run storage and
isolated whole-world presentation remain required by the following P22C tasks.
The test uses actual recorded Player snapshots; it does not certify 45 minutes
of production combat or final line coverage.
