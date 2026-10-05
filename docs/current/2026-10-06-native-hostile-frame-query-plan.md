# Native Hostile Frame Query Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Actual native Boss preparation and publication
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-recording-snapshot-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The committed `54866d4` real fifth-floor phase-2 diagnostic measures 59.845 ms
per Player frame. Hostile preparation consumes 34.770 ms inclusively. Complete
Boss snapshots run about 29.7 times per frame and consume 4.792 ms; two complete
preview configurations consume 3.577 ms. Repeated restore validation remains
the admission authority. See the native recording snapshot evidence for exact
source, frame interval, physical readback and timing limits.

## Narrow Change

Use runtime-owned current-frame, terminal and detached action queries for
internal callers needing only those observations. Primitive queries always
read current state, so mutations and rollback do not require a shadow cache.
Public complete snapshots keep their original schema and detached descendants.

Retain separate private body and arena preview runtimes. Reuse a preview only
when the complete configured definition, identity and real arena origin/trunk
context have exactly equal typed bytes. Every use still restores and validates
the complete requested snapshot. A changed or forged configuration rebuilds or
refuses, and the preview never owns live actor state. Preserve physical shape
preflight, body contacts, authenticated receipts and full-frame compensation.

## Executable Acceptance

First run the new five-Boss scene against the old production code and retain
its missing-query/preview assertion as RED. GREEN must prove exact query/action
types, mutable public descendant isolation, real mutation and historical
rollback, preserved cold verdicts for foreign numeric types, separate preview ownership,
mandatory restoration before reuse, changed-origin rebuild and exact typed
configuration refusal. Then run existing Boss runtime/cache/native transaction
and recording regressions and the real phase-2 120-frame reproduction.

This is one focused performance slice. Record the complete-frame delta before
another slice, and only certify sustained recording after the combined committed
source passes the uninstrumented 600-frame tape/readback gate. No frame, content,
capacity, damage or gameplay budget changes are authorized by this plan.
