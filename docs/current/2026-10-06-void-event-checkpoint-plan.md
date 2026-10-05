# Void Event Replay Checkpoint Plan

- Status: Approved / Current
- Document Role: Current focused native performance repair plan
- Authority Level: Below approved full-product completion contract
- Applies To: Void auxiliary historical validation across consecutive frames
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-native-hostile-frame-query-evidence.md`, `2026-10-06-auxiliary-snapshot-cache-evidence.md`
- Exit Gate: Deterministic event-call RED/GREEN, authority regressions and complete-frame remeasurement

The actual unified native profile measures 3.752 ms/frame in Void auxiliary
validation. The complete-snapshot cache misses when only runtime_frame changes;
each miss reconstructs the same event history from the initial state. A counting
subclass will confirm this repeated work before production changes.

Retain one privately owned replay checkpoint per authority for an exactly equal
typed-byte event history and full configured definition/initial-state context.
It represents the state immediately after the final event, before the requested
frame's final expiry refresh. Reuse only for frames at or after that event.
Staged next-frame events must use complete replay. Unsafe serializable values
cannot obtain or use a checkpoint. Each candidate still compares its complete
derived state against the reconstructed result, retaining existing JSON numeric
compatibility and strict accepted-boundary rules.

Bound event bytes and retained replay bytes, protect the checkpoint with an
instance mutex, and return independent copies. Configuration, origin, event
content, event types, initial-state changes and frame regression must invalidate
reuse by exact context/typed-byte mismatch or use complete replay. No wire
format, public verdict, authoritative state, event count or schema changes.

Verification includes complete history/frame equivalence with a fresh authority,
expiry boundaries, forged derived state, changed event content/type, next-frame
staging, phase/terminal events, rollback to earlier frames, configured-origin
and initial-state changes, alias isolation, thread safety and bounded retention.
The deterministic work gate limits repeated _apply calls to the event count
when identical history is validated across new accepted frames. This local work
gate does not certify FPS. Full native measurements remain separate.
