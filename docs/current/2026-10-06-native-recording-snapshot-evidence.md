# Native Recording Snapshot Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Player-owned native recording capture and automatic recorder
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-recording-snapshot-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Ownership and Validation

The ordinary `full_player_replay_snapshot()` still produces a fully detached
mutable snapshot with its original schema, field order and Variant types. The
new Player-owned `native_replay_recording_snapshot()` uses that same builder. It
shares event dictionaries only after its own immutable journal has authenticated
and deeply sealed them, behind a read-only shallow array. Unsupported histories,
including Packed descendants, retain the original detached cold capture.

`validate_native_replay_recording_snapshot()` requires the read-only wrapper's
exact array type and every exact journal-owned event reference. It only removes
the already authenticated history from a private shallow validation projection;
the original full snapshot validator checks every other field, identity, schema,
clock and state contract. Foreign references or mutable wrappers take the full
original validator. No caller-provided boolean certificate is accepted.

The automatic recorder now uses these two Player APIs and retains one private
observation for both its buffer and latest slot. Its public latest method still
deeply duplicates that observation. Store append passes the private batch's
references into the codec without duplicating all history. The codec continues
its full safety, schema, patch and digest checks before physical persistence.
No replay format, compressed bytes, admission rule or gameplay value changes.

## RED Boundary

The complete new test scene is overlaid on the clean committed `141f4c5` archive
at `build/retained-checkout/native-recording-snapshot-red-141f4c5-20261006`.
The archive's verified editor import passes strict runtime error/leak scanning.
`build/guard-red` produces exactly the missing-native-API assertion in actual
Main, with normal scene disposal and no script parsing or object/RID-leak error.
The earlier root RED is retained at `build/native-recording-snapshot-red-20261006`.

## Actual Main Contract

The parent lane executes the final new scene against the implemented Player and
recorder in `build/native-recording-player-api-green`. Strict stdout/Godot logs
pass, including the exactly scoped intentional late World-transaction refusal.
The scene uses actual Main, a normal seeded Launch run, its native combat room,
actual Sword input, native hostiles and the real automatic recorder.

It verifies:

- Twelve accepted native weapon/movement frames have complete Player capture
  bytes identical to the ordinary public snapshot and identical cold-validator
  verdicts.
- Actual event history is nonempty, uses a read-only capture wrapper, and every
  event Dictionary/Array descendant is sealed. Public full snapshots remain
  mutable and detached, including their nested event payloads.
- Same-count foreign read-only histories retain cold acceptance; unsafe foreign
  history, unsafe other state, forged clocks and a wrong expected run identity
  retain the original refusal verdicts.
- Packed descendants produce exactly the detached public bytes, take the
  original validator, and remain isolated from caller Packed mutations.
- A public latest observation's nested payload and health mutations cannot
  change the private buffer or its latest boundary.
- Late whole-frame refusal restores complete typed Player and native hostile
  state, appends no tape observation and preserves the prior recorded boundary.
  The identical frame retries successfully and records exactly once.
- Flush and fresh physical Store random seek reproduce the complete final
  observation's exact typed bytes.

The survival source is explicitly a test fixture. This is not unassisted victory
or a human playtest.

## Focused Regressions

The gameplay performance lane's additional strict scenes all pass:

| Scene | Retained Logs |
| --- | --- |
| Existing automatic recorder, 125 actual frames and slow background writer | `build/native-recording-recorder-green-20261006` |
| Native recording backpressure | `build/native-recording-backpressure-green-20261006` |
| Full typed chunk codec | `build/native-recording-codec-green-20261006` |
| Physical stream store | `build/native-recording-stream-green-20261006` |
| Full Player replay | `build/native-recording-fullplayer-green-20261006` |

The existing recorder contract includes actual native actor observations,
independent physical readback, rejected input adding no observation, asynchronous
write ownership, explicit storage failure and continued gameplay after failure.
The parent lane also retains its 26-scene save regression run. Final combined
clean-source certification remains separate from these focused results.

Two independent read-only reviews of Player and recorder find no actionable
issue in exact-reference authority, Packed fallback, remaining validation,
public mutation isolation or private observation ownership. Godot is
`4.6.1.stable.official.14d19694e`. Line coverage is unsupported. Documentation
governance and diff whitespace checks pass, and no dependency is added.

## Remaining Measurement

The frame-2741 immutable journal microbenchmark reduces unchanged-prefix work
to 0.011 ms, but that is one operation. It does not establish the complete
gameplay frame's performance. The next gate is an uninstrumented clean committed
source archive measuring actual P3 frames with independent physical tape
readback, followed by rendered and sustained workload checks as warranted.
