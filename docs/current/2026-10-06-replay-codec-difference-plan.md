# Replay Codec Difference Validation Plan

- Status: Approved
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: Whole-run replay chunk codec root difference comparison
- Owner: Project owner
- Depends On: Approved full-product completion contract
- Last Verified: 2026-10-06

## Observed Cost

An isolated encode of the physically retained actual Main observations 2741
through 2860 takes 9.804 seconds. Safety traversal contributes 3.897 seconds,
typed-byte difference calculation 4.712 seconds, and snapshot digest generation
1.161 seconds. The encoded compressed bytes and every typed envelope field match
the original physical chunk exactly. This shared-host diagnostic identifies work
to reduce; it does not certify runtime frame rate.

## Executable Completion Criteria

1. Preserve actual physical corpus compressed bytes, raw and compressed SHA-256,
   typed envelope fields, and every reconstructed observation exactly.
2. Run existing codec, stream-store, and native-recorder contracts for typed
   snapshots, nonfinite rejection, patch path rejection, sequence bounds, and
   caller-owned snapshot isolation before and after the production change.
3. Skip only the root equality comparison after the encoder has admitted a
   distinct contiguous integer sequence. Keep all recursive typed-byte equality,
   dictionary ordering/type checks, patches, and safety validation unchanged.
4. Compare isolated stage timings on the same physical corpus before and after,
   and retain strict Godot script-error and object/RID-leak checks.
5. Run focused codec, stream store, native recorder, and replay regressions before
   retaining the production change. Do not discard history or modify replay
   schema, admission rules, compression, patch shape, or public snapshots.

## Related Readonly Experiment

A separate isolated feasibility experiment recursively freezes privately owned
history, verifies unchanged typed bytes, duplicates a mutable detached public
snapshot, mutates its nested and packed values, and compares worker encoding with
a deep-copy baseline. This does not authorize a codec cache or an assumption that
every read-only container has read-only descendants. Native recorder production
ownership remains with the parent implementation lane.

## Rejected Scalar Experiment

An isolated ordinary-scalar dispatch before composite type checks retains exact
physical chunk bytes but does not improve measured safety cost: 3.897 seconds
before, 3.888 seconds after. Total encoding moves from 9.804 to 9.962 seconds.
That candidate is not retained in production. The revised plan targets root
serialization that is provably redundant because its sequence field differs.
