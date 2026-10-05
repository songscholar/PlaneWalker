# Immutable Replay Journal Validation Plan

- Status: Approved
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: Player private weapon event history and rollback preimages
- Owner: Project owner
- Depends On: Approved full-product completion contract
- Last Verified: 2026-10-06

## Observed Failure

Exact-source positive caching preserves replay authentication but still spends
45.305 ms on an unchanged physical frame-2741 history. Deep copying and repeated
safety/serialization walks remain over the 16.667 ms frame budget. Raw typed
serialization cannot replace safety validation: Godot encodes a freed Object
identically to safe null. Full public snapshots and cold validators must retain
their existing contracts.

## Executable Completion Criteria

1. Establish a missing-journal RED. A helper must privately copy, fully validate
   safety, authenticate the existing capture digest, and recursively freeze
   every Dictionary/Array reachable from a managed event before certification.
2. Use exact reference equality only for events previously sealed by this same
   helper. Same-count replacements, direct test injection, append, truncation,
   restore and reordering must rebuild the affected certificates and preserve
   the existing capture-order canonical prefix root.
3. Compute and install new certificates atomically. Unsafe input must leave
   caller history and previous certificates untouched, taking the old cold
   prefix path. Cover the warmed safe-null / freed-Object byte collision.
4. Keep the complete public history and its typed bytes unchanged. Deep public
   copies must remain mutable and detached; packed-array descendants must retain
   their value ownership. Packed descendants are mutable despite readonly
   Dictionary/Array ancestry in Godot 4.6.1; decline certificates for any such
   event and preserve the full cold fallback. Retire discarded references.
5. Let fixed-frame rollback copy the event array shallowly only when every slot
   matches a current owned immutable certificate. Preserve the full deep-copy
   fallback for uncertified history, including packed descendants. Gun
   completion must replace a slot with a
   fresh certificate, never mutate an existing sealed event.
6. Run native Player rollback, weapon external fact/Gun, full Player, physical
   recorder and checkpoint regressions with strict logs. Independently review
   ownership and all mutation/restore sites before retaining a focused commit.
7. Measure the unchanged physical late-history prefix before repeating native
   performance certification. Internal recorder sharing may follow separately
   only with exact typed physical tape evidence and public caller isolation.

## Completion Boundaries

This is a gameplay performance repair. UI implementation remains behind the
native gameplay gate. Synthetic certification counters and microbenchmarks do
not certify FPS, unassisted victory or human playtesting.
