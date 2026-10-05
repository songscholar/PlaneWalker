# Native Legacy Action Digest Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Boss restoration current-versus-historical Action classification
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-action-validation-template-evidence.md`
- Last Verified: 2026-10-06

## Observed Redundant Configuration

After a complete accepted Boss snapshot restores an independent mutable Action,
Void and Time each create another fresh current-regime Action solely to read its
definition digest for a legacy flag. The existing private immutable template
already contains that exact normalized digest, keyed by the complete typed
configured authority and current regime. No mutable instance is needed for
this comparison.

## Narrow Change

Replace only the two legacy flag digest expressions in Boss restoration with
the current-regime `_action_validation_template` digest. Preserve the existing
current/historical mutable Action selection, `Action.restore_snapshot`, complete
Boss/auxiliary/receipt validation, public Action configuration and all template
shape, ownership, capacity, eviction and oversized fallback contracts. The
current-regime template must use the same phase, enrage and exact typed Boss
context as cold configuration. Do not introduce a mutable-from-template API.

## Executable Acceptance

The focused RED fixture counts `_make_action` calls only during warm complete
Boss restoration. Every current regime must create exactly one independent
mutable Action; historical Void and Time must retain their original two-step
current-then-historical selection. Before this change, Void and Time each add
one unnecessary current construction for the legacy digest. RED must fail
only these count assertions, while actual restoration, typed state, current
and historical legacy flags, immutable templates and next-frame outputs pass.

The fixture covers all five authored Bosses at warning, active, recovery and
ended boundaries, plus historical Void geometry and Time response regimes.
Repeated restoration must create different mutable objects without altering
the private immutable template. Typed forged snapshots and foreign owner or
digest must refuse without state mutation. Reconfiguration must clear cached
templates and reject the prior owner. Existing complete Action configuration,
template capacity/concurrency, Boss, Void, Time, native transaction and replay
neighbors remain required.

This removes configuration work only. It does not certify frame throughput,
rendering, sustained recording, the 45-minute soak, UI or human playtesting.
