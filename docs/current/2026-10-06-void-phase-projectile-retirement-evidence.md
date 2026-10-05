# Void Phase Projectile Retirement Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Void Boss phase boundaries in native hostile payload preparation
- Owner: Native matrix validation lane
- Depends On: `docs/current/2026-10-06-void-phase-projectile-retirement-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No full matrix, human playtest, unassisted victory, FPS or coverage certification

## Root Cause

Canonical native case 619 is
`time_lord|sword|rewind+rift|void_throne`, seed `20261624`. Both the frozen
`be58030` full matrix and an independent `4735176` single-case reproduction
refuse frame 2556 at `effects_commit`, with `HOSTILE_EFFECT_INVALID` and
field `void_damage_receipt`. Void Bolt generation 27 was released at frame
2550. Phase 1 begins at frame 2553 and retires its auxiliary cast. The native
payload authority only retires Boss aftershock zones at phase boundaries,
so the committed projectile remains active and later reaches the Player.
Its receipt cannot settle against the already retired cast.

`cdea629` exposes complete source retirement for Void phase transitions and
applies it to the native payload preview. Domain projectiles, physical bodies,
and their threats now retire with the auxiliary cast. Before-snapshot native
contact seals remain intact for commit validation and rollback. The strict
retired-cast receipt validator and public snapshot schemas are unchanged.

## Executable Regression

The new `_phase_projectile_retirement()` native test releases an actual bolt,
enters the next phase before impact, refuses and restores the phase boundary,
then accepts it and advances through frame 80. It checks the exact projectile
domain, reconstructed physical body, owner snapshot, physical SaveService and
typed Replay readback, and absence of delayed damage or status.

The isolated RED run fails five behavioral assertions and refuses frame 61
after the retired projectile loses 22 Player HP. The fixed lifecycle suite
passes with no unexpected engine errors or leaks. Its ten adjacent suites
also pass, covering Void domain/native receipt behavior, Player frame
atomicity, identity, validation caches, Boss terminal retirement, native
projectile contacts, and independent Moth payload preservation. All eleven
GREEN logs pass `tools.runtime_log_validation`; existing negative tests use
only their exact completed TestSuite refusal scopes.

- RED: `build/test-evidence/void-phase-projectile-red-isolated/godot.log`
- GREEN: `build/test-evidence/void-phase-projectile-green/godot.log`
- Adjacent logs: `build/test-evidence/void-phase-regression/`
- Pinned requirement audit: `build/test-evidence/void-phase-regression/pip-audit.json`

The pinned requirement audit reports no known vulnerabilities. No dependency
manifest changes are part of this fix. The first exploratory RED invocation
used an existing save directory and also refused existing profiles; the
retained isolated RED rerun removes those unrelated save diagnostics.

## Frozen Original Case

The after checkout is a new `git archive cdea629` extraction, containing its
committed replay cache and codec changes but no uncommitted journal changes:
`build/retained-checkout/p15-case619-after-cdea629-20261006`.

Fresh import follows the approved bootstrap translation classification.
Remaining bootstrap errors are zero, and pass 2 is strictly clean. The native
runner uses the production 60 Hz clock and fixed source snapshot, with
`source.instrumented=false` and aggregate SHA-256
`a607203bb93092bca649ab1379ec1f3b9ca78077f7f2a0ae02d7d8809e50cdbb`.

| Criterion | Observed Result |
| --- | --- |
| Native range | Case 619 only, 1/1 PASS, runner errors 0 |
| Completion | Frame 6142, final Boss HP 0 |
| Three authored phases | Actual weapon loss 1235.52 / 1179.36 / 585.12 |
| Equipped time receipts | Rewind frame 78, Rift frame 157 |
| Positive time interaction | `boss_rift_slow` |
| Physical checkpoint and exact continuation | `60b31027edfd20f5846b8fa63e42b4f307724f7422b03f90ad116e4631876ecd` |
| Canonical death receipt | Exactly one `hostile_defeat:d96b2bd04e23178edc894dbceab6127e5494a02c` |
| Original failure | No retained `original_frame_rejection` or refused-frame diagnostic |
| Strict stdout and Godot logs | PASS, no errors, leaks, or allowed-error scopes |

After report:
`build/retained-checkout/p15-case619-after-cdea629-20261006/build/p15-case619-after.json`.
The old failure remains at
`build/retained-checkout/p15-native-full-be58030-20261006/build/test-evidence/p15-native-full/native-600-150/report.json`.
The independent pre-fix reproduction remains at
`build/retained-checkout/p15-case338-scalar4735176-20261006/build/p15-case619-before.json`.

This certifies the focused regression and its original native case. It does
not upgrade the failed original 750-case matrix or certify gameplay completion.
