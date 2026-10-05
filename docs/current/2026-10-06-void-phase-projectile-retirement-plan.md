# Void Phase Projectile Retirement

- Status: Implemented; fixed-source native case verification pending
- Scope: Void Boss phase boundaries in native hostile payload preparation
- Baseline reproduction: native matrix case 619, seed 20261624

## Confirmed Failure

The case `time_lord|sword|rewind+rift|void_throne` refuses frame 2556
at `effects_commit`, with `HOSTILE_EFFECT_INVALID` and field
`void_damage_receipt`, on both the original `be58030` matrix snapshot and
an independent `4735176` snapshot. Void Bolt generation 27 was released at
frame 2550. The phase change at frame 2553 retires its auxiliary cast, but
the native payload authority retains its projectile. Its later contact
cannot settle against the retired cast.

## Completion Criteria

1. An actual in-flight Void Bolt and its native body retire at the first
   accepted phase boundary, together with the auxiliary cast authority.
2. Refusing that boundary restores the exact projectile domain, native
   body, owner snapshot, and threat ownership.
3. Physical save and typed replay reconstruct the accepted phase boundary.
4. A retired cast cannot publish delayed damage or a new status, and later
   physical frames continue without a receipt refusal.
5. Existing strict retired-cast receipt refusal remains unchanged.
6. Other Boss phase policies, terminal retirement, independent enemy
   payloads, and normal payload identity remain covered by adjacent tests.
7. The original complete case passes on a new, stable source snapshot with
   all authored HP phases, exact checkpoint continuation, and one death
   receipt. The failed original matrix remains retained as failed evidence.

## Narrow Implementation

`LaunchBossActor.prepared_launch_payloads_retired()` exposes full source
retirement for terminal Bosses and Void phase transitions. The payload
authority applies this policy to its preview before resolving contacts.
Original native contact seals remain attached to the before snapshot for
commit validation and rollback. Void auxiliary receipt validation and
public snapshot schemas are unchanged.

## Regression Evidence

The added `_phase_projectile_retirement()` case in
`tests/integration/combat/void_auxiliary_lifecycle_test.gd` uses a real
projectile and phase change, then checks rollback, save/replay, and accepted
continuation through frame 80. Before the fix, the isolated suite fails
five behavioral assertions: the projectile remains after phase retirement,
frame 61 refuses, and the retired projectile loses 22 Player HP. The fixed
suite passes with no unexpected engine errors or leaks.

Logs:

- RED: `build/test-evidence/void-phase-projectile-red-isolated/godot.log`
- GREEN: `build/test-evidence/void-phase-projectile-green/godot.log`
- Adjacent suites: `build/test-evidence/void-phase-regression/`

Ten adjacent suites pass: Void auxiliary domain, Boss integration, validation
cache, native auxiliary settlement, Player frame atomicity, payload identity,
Boss payload retirement, terminal projectile contact, Moth independent
payloads, and normal Boss payloads. Every log passes
`tools.runtime_log_validation`, including only exact declared TestSuite
refusal scopes where present. The pinned Python requirement audit reports
no known vulnerabilities; this change adds no dependencies.

The final fixed-source native case result will be recorded separately after
the code commit is frozen. This document does not certify the full 750-case
matrix or gameplay completion.
