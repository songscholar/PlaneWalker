# P22C Streamed Run Replay

- Status: Approved / Current
- Document Role: Current focused implementation specification
- Authority Level: Whole-run recording and isolated presentation boundary
- Applies To: Bounded chunk codec, automatic native capture, durable recording and seek
- Owner: Project integration lead
- Depends On: `2026-10-05-p22b-replay-library-design.md`, `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

## Design

Retain a complete Launch run as a versioned manifest and immutable compressed
chunks. Each chunk begins with a complete keyframe; subsequent entries contain
deterministic dictionary differences. Arrays retain their exact Variant type.
Chunk encoding preserves integer/float and String/StringName distinctions,
vectors and typed arrays. Objects, nonfinite numbers, excessive depth, duplicate
sequence, malformed deltas and unauthenticated bytes refuse before publication.

The recording clock is the sequence of accepted capture observations, separate
from Player frames and Run revisions. Automatic capture observes committed
Player frames and actual room/route/reward/economy transitions. Rejected gameplay
frames produce no entries. Recording never writes gameplay state; unavailable
storage reports a recording failure without blocking the game. Native encounter
snapshots use the existing authoritative driver. A transition whose native state
has not flushed waits for that actual boundary; it cannot invent hostile state.

One chunk admits at most 120 observations, 32 MiB of decompressed data and 8 MiB
of compressed data. A retained run admits at most 162000 combat frames (45
minutes at 60 Hz), plus bounded transition observations, and 64 MiB of compressed
chunks. Its manifest binds game/content/save-domain identity and every chunk's
sequence range, lengths and SHA-256. Physical compare-exchange prevents stale
writers. A failed partial recording remains explicitly incomplete and cannot
appear as a certified complete run.

Whole-run viewing reconstructs a new private world at the requested keyframe,
then applies validated recorded state. Enemy/room/economy presentation shares
the private World2D and event bus; it cannot publish progression or interact
with live actors. Exact snapshot playback and input-simulation verification
remain distinct claims. Existing P22B Player packages retain compatibility.

## Completion Criteria

Codec tests cover actual Player snapshots, bit-exact Variant types, insert/delete
and nested changes, random seek, corrupt and rehashed malformed deltas, expansion
limits and defensive copies. Physical tests cover multi-chunk reload, CAS faults,
crash recovery, incompatible identity, missing/corrupt chunks and bounded storage.
Automatic native integration tests observe actual committed frames, native
actors, room rewards, economy and terminal state with no fixture-authored tape.
The library exposes retained complete/incomplete runs and actual native viewing.
Long-storage simulation is clearly synthetic; complete gameplay certification
must use actual production combat. Every layer requires clean logs and local
retention before its following integration stage.
