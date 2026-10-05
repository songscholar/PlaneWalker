# Immutable Replay Journal Evidence

- Status: Focused Verified / Native recording performance pending
- Document Role: Current verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Player owned event prefix certification and private rollback
- Owner: Plane Walker verification lane
- Depends On: `2026-10-06-immutable-replay-journal-plan.md`
- Last Verified: 2026-10-06

## Correctness and Ownership

A clean archive of `33abaa6`, with only the corrected new test overlaid,
establishes the missing-journal RED. Its second import is strictly clean and
the test fails only because the journal is absent. Logs are under
`build/retained-checkout/immutable-journal-red-33abaa6/build/journal-red`.
Earlier local attempts with inferred-Variant test warnings are retained and
are not the behavioral RED.

The new journal suite is strict GREEN, and the full 30-scene replay suite passes
in `build/immutable-replay-full-regressions`. The native fixed-frame authority
suite also passes in `build/immutable-fixedframe-regression`. These cover full
Player replay, weapon external facts and Gun completion, observable restore
atomicity, native automatic tape/backpressure, codec and physical stream seek.
All stdout and engine logs pass the normal strict error/leak scanner.

The private Player-owned journal authenticates a detached event and recursively
freezes its Dictionary/Array graph. It reuses a certificate only for exact
references it previously sealed. Changed slots authenticate before any slots
or certificate state are published. Append, replacement, restore, reorder,
gaps and discarded-history retirement retain the existing canonical prefix.
Duplicate sequences, unsafe values and unsupported immutable graphs take the
original cold path. Failed refresh revokes shortcut eligibility.

Packed arrays remain mutable through aliases even under readonly container
ancestry in Godot 4.6.1. Such descendants are deliberately excluded from
certificates; they retain complete cold validation and detached copying. The
freed-Object / safe-null typed-byte collision is also explicitly refused.
No raw serialization hash is accepted as a safety certificate.

The Player now obtains its prefix from this journal, retaining Recorder fallback
for uncertified history. Private fixed-frame rollback uses a shallow array copy
only after every event matches the current certificate. Public weapon events,
gameplay rewind state and full Player snapshots retain complete mutable deep
copies and unchanged typed bytes. This helper is owned by one Player on the
main thread; worker recording never refreshes it.

Independent ownership reviews identified the packed-alias and duplicate-sequence
boundaries before retention; both are covered by conservative fallback. The
integration save regression is running separately and final clean whole-project
certification remains pending.

## Actual Late-History Diagnosis

The actual physical frame-2741 history contains 116 events and 1,246,548 typed
bytes. A recursive scan finds zero packed descendants. The source digest is
`cc6dbd42df03c4ac1e8fbd499a55017fa9c1a3d4e68c8c2e1839d8f289999fec`.

Ten trials per case retain the original source bytes, match the old canonical
root, recursively verify readonly containers, and confirm public deep copies
remain mutable and detached. Strict logs and reports are retained under
`build/retained-checkout/replay-codec-diagnostic-4735176/build/journal-cache.json`
and `packed-history-scan.json`.

| Case | Existing median | Journal median |
| --- | ---: | ---: |
| Cold journal | 158.706 ms | 250.071 ms |
| Unchanged exact references | 160.226 ms | 0.011 ms |
| Appended event | 166.202 ms | 10.132 ms |
| Replaced event | 158.778 ms | 6.591 ms |

Warm calls perform no new event certification or root construction. Append and
replacement each authenticate one event and build one root. Cold restoration
is more expensive and remains explicit. These are isolated shared-host
diagnostics, not rendered FPS or complete native-frame certification.

## Remaining Work

The native recorder still builds and validates a detached full historical copy
for each observation. Its internal snapshot/validation path must reuse only
certified immutable history, preserve all other cold checks, and retain exact
physical tape bytes and detached public latest observations. That work follows
as a separate focused change before sustained native performance certification.
UI implementation and all 20 human playtests remain pending.
