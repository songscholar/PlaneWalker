# Native Recording Snapshot Validation Plan

- Status: Approved
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: Player-owned native recording capture and automatic recorder
- Owner: Project owner
- Depends On: Approved full-product completion contract
- Last Verified: 2026-10-06

## Observed Cost

Later actual Main recordings carry 1,246,548 bytes of weapon replay history per
observation. The immutable journal can authenticate unchanged history in
0.011 ms, but the automatic recorder still obtains a complete detached public
snapshot, traverses that history again, and deep-copies the full observation
into its private latest slot. Public snapshots must remain caller-owned.

## Executable Completion Criteria

1. Retain an API-guard RED against a frozen checkout before adding the two
   Player-owned native capture and validation APIs.
2. Compare real Main public and native capture snapshots byte-for-byte through
   actual accepted weapon frames. Share history only behind a read-only array
   containing exact journal-owned deeply sealed event references.
3. Keep the original complete snapshot validator for every other field. Foreign
   same-count histories, mutable wrappers and Packed descendants take the
   original cold path. Unsafe history/other fields and forged clocks retain
   identical refusal results.
4. Keep public full snapshots and latest observations deeply detached and
   mutable. Caller modifications cannot affect Player history, recorder buffers,
   background workers or physical replay reads.
5. Verify a late whole-frame refusal restores Player and native state, adds no
   tape observation, and retries the same frame exactly once. Flush and reload
   the physical last observation from a fresh store with exact typed bytes.
6. Run focused native capture, existing recorder, stream/codec, backpressure and
   relevant cold checkpoint/replay contracts under strict Godot script-error and
   object/RID-leak validation. Freeze the implemented source before new late
   performance evidence. Do not certify FPS or human playtesting from fixtures.

## Ownership

The parent lane owns the two Player APIs and immutable journal. The gameplay
performance lane owns the automatic recorder integration and dedicated real
Main contract scene. They coordinate a single final source boundary for evidence.
