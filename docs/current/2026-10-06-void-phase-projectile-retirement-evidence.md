# Void Phase Projectile Retirement Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Void Boss phase boundaries in native hostile payload preparation and retained native cases 619/513
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

## Original Refusals and Source Boundaries

The original matrix remains in the untouched `git archive` extraction of
`be580300a80888882d70dff5ac0863c3ed7359d6` at
`build/retained-checkout/p15-native-full-be58030-20261006`. Its runtime/runner
aggregate SHA-256 is
`4d105df812e13cfbc95209f6a95a4d13891932a4ebfb0e604385f8d33f2d2db7`,
recomputed with the runner's exact source-snapshot algorithm. Its final combined
report is still pending while shard 000 runs; the four other shards have already
failed. Neither the archive nor any original report was overlaid with fixes.

| Original case | Last accepted frame / HP | Refused runtime frame | Refusal |
| --- | --- | --- | --- |
| 619, `time_lord\|sword\|rewind+rift\|void_throne`, seed 20261624 | 2555 / 1764.4799999999982 | 2556 | `effects_commit`, `HOSTILE_EFFECT_INVALID`, `void_damage_receipt` |
| 513, `primordial_knight\|gun\|stop+rewind\|forge_colossus`, seed 20261518 | 4191 / 283.1875 | 4192 | `effects_can_commit`; actor can commit, payload effects cannot |

The original case reports are, respectively:

- `build/retained-checkout/p15-native-full-be58030-20261006/build/test-evidence/p15-native-full/native-600-150/report.json`.
- `build/retained-checkout/p15-native-full-be58030-20261006/build/test-evidence/p15-native-full/native-450-150/report.json`.

Each directory retains separate `stdout.log` and `godot.log`. The original
failures remain failures, including their missing terminal receipts. The
distinction between last accepted frame and refused runtime frame is intentional.

The separate pure `4735176` archive at
`build/retained-checkout/p15-case338-scalar4735176-20261006` has aggregate
`40f975cdee2ae8dd0cfb47402fa0fb28f54de333733f59f2c7c96fc2957d5553`.
Its `build/p15-case619-before.json` reproduces the same refusal, frame and HP
after the scalar-distance correction. This establishes that the Void lifecycle
failure is independently outstanding at that source.

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

## Companion Case 513 Scalar Recovery

Case 513 is a Forge scalar-distance refusal, separate from Void cast retirement.
The [scalar-distance evidence](2026-10-06-projectile-scalar-distance-evidence.md)
records its correction in `4735176`. An additional independent one-case run
in the pure `4735176` archive passes before the Void fix is present:

```sh
python3 tools/run_p15_hostile_matrix.py \
  --output build/p15-case513-scalar-after.json \
  --logs build/test-evidence/p15-case513-scalar-after \
  --start 513 --count 1 --jobs 1 --timeout 900
```

The pure-scalar report is
`build/retained-checkout/p15-case338-scalar4735176-20261006/build/p15-case513-scalar-after.json`.
The independently passing combined `cdea629` report is
`build/retained-checkout/p15-case619-after-cdea629-20261006/build/p15-case513-after.json`.
Both retain the identical observations below, with `source.instrumented=false`,
one requested/observed production case, runner `errors=[]`, case `failures=[]`
and no original rejection or refused-frame diagnostic:

| Criterion | Both Sources |
| --- | --- |
| Terminal result | Frame 4574, final HP 0 |
| Three authored phase losses | 1141.1875 / 968.75 / 690.0625 |
| Equipped paid time casts | Stop frame 64, Rewind frame 139 |
| Positive time interaction | `boss_stop_conversion` |
| Physical checkpoint and exact continuation | `b9d0a2a09fbe4b87dfa46ca7281e35083bb0ebec99090199497eecf41cf35f37` |
| Canonical death receipt | Exactly one `hostile_defeat:0782953934678101e0ac731c02269e3f123e2464` |

The two report directories retain separate stdout/engine logs. Both pairs
independently pass `python3 -m tools.runtime_log_validation` with no allowed
negative-test scope. The pure-scalar run exits 0 and prints `native shard513:1
PASS` and `actual native cases1/1; errors0`. This confirms case 513 recovery
without attributing it to the unrelated Void change.

This certifies the focused regression and its original native case. It does
not upgrade the failed original 750-case matrix or certify gameplay completion.
Every one-case report intentionally has `native_complete=false` and
`p15_complete=false`; a new untouched unified source must independently pass
the complete 750-case gate. Human playtests, unassisted victory, rendering/FPS,
statement coverage and full-package completion remain outside this evidence.
