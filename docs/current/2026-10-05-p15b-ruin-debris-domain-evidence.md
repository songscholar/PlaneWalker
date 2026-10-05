# P15B Ruin Debris Domain Foundation

- Status: Domain Verified Locally; native projectile landing integration pending
- Document Role: Current implementation and verification evidence
- Authority Level: Retained milestone evidence below the approved P15 Boss specification
- Applies To: Explicit Ruin debris reservations, geometry, HP, accepted lifetime and cold state
- Owner: Plane Walker native Boss implementation lead
- Depends On: `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05

## Accepted Domain Contract

`RuinDebrisRuntime` is a pure state owner for accepted projectile landing events. Its recipe binds the authored20HP,480-frame lifetime and four-body cap. A12px circle fits the debris footprint. The explicit snapshot retains each landing identity, candidate position, activation frame, current HP, accepted damage claims and terminal source retirement.

Each distinct source/generation/hit index reserves exactly one row. At most four rows become active, and foreign arena bodies consume the shared eight-construct budget. Full budgets preserve pending rows without spending their480-frame lifetime. Breaking or expiring an active row admits the next eligible reservation in stable order. Final owner retirement cancels active and pending rows.

Candidate positions use the room's16px grid and stable distance/Y/X ordering around the actual landing point. The conservative candidate grid preserves at least48px perimeter and central crossing corridors. Active debris pairs retain48px spacing between their circular surfaces. External occupancy descriptors may require their own clearance. Original landing coordinates remain in the event and cannot silently turn into saved obstacle coordinates.

Damage facts settle at most the remaining20HP once per fact identity. Candidate frames allow next-frame facts for enclosing transactions; accepted-boundary snapshot validation can reject those facts before publication. Cold validation reconstructs HP losses, exact age, active/pending/expired/broken/retired phases and each permitted grid point. It rejects altered HP, age, unknown fields, central-corridor placement, overlapping active rows and excess active bodies.

## Verification

- Missing runtime RED: `planewalker-tests.VLwUMK`,1 failing scene with the expected missing-resource assertion.
- Domain GREEN: `planewalker-tests.XuOc23`,1/1.
- Final geometry validation GREEN: `planewalker-tests.2cxbiM`,1/1; strict active overlap refusal supplements the initial mutation matrix.
- Tests cover six distinct landing reservations, four active/two pending rows, admitted rather than pending lifetime, HP20 destruction, duplicate rejection, exact rollback, expiry at481 after activation at1, queued admission at481, shared-budget admission and terminal source retirement.
- Final logs contain no script errors or known leaks. Ordinary tests report `godot_line_coverage_unsupported`; no line-coverage percentage is claimed.

## Remaining Gate

This is a domain foundation, not a playable debris delivery. Actual projectile blocking, target hits and trajectory expiry still need to emit authenticated landing events. Native StaticBody2D/Hurtbox projection, real weapon contact, shared Wall admission, accepted whole-Player rollback, current/historical physical Host checkpoints and screenshots remain open. The debris checkbox in the arena plan remains unchecked.

No content fingerprint, dependency, public artifact or remote repository changed. Source, focused test and evidence are retained in a precise local commit for recovery while the native implementation continues.
