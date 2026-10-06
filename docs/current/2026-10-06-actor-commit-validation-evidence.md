# Actor Commit Validation Evidence

- Status: Focused Verified / Sustained 60 FPS gate pending
- Document Role: Actual Actor transaction and same-workload measurement evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Public and native Launch Hostile/Boss Actor commits
- Owner: Plane Walker performance lane
- Depends On: `2026-10-06-boss-native-validation-pass-evidence.md`
- Last Verified: 2026-10-06

## Retained Behavior

`_commit_owned_launch_frame()` runs the complete original public commit guard.
The exact production Actor, status, and optional affix implementations can
install that validated Actor candidate without repeating the full Actor guard.
The original runtime, status, and affix restore methods still run their own
validators. Custom Actor, status, or affix scripts retain the original complete
Actor revalidation immediately before installation. There is no public trusted
flag, accepted external candidate, or test-only bypass.

Boss presentation refresh now belongs to `_install_validated_actor_state()` so
both commit and rollback preserve arena collision/control synchronization. The
first candidate skipped this hook and failed forest rollback; that rejected
run remains under `build/performance-actor-commit/green/`.

A custom status validator can change an earlier validated runtime after its own
check. A separate RED under `red-custom-status/` exposed that regression, and
the exact production-script guard retains the original refusal for this case.
Public validation, exact typed installation, historical compensation,
publication gates, save/replay formats, and checksums are preserved.

## Executable Evidence

`tests/integration/combat/actor_commit_validation_pass_test.tscn` instantiates
all five authored Boss scenes and physical rooms. Its counted runtime delegates
to the production validator through `super`. It measures real public commits
and real Bridge native commits, then verifies complete typed installation,
exact rollback, deterministic retry, publication, and custom validator refusal.

| Boss snapshot/context validations per actual commit | Original | Candidate |
| --- | ---: | ---: |
| Public Actor commit | 3 | 2 |
| Actual Bridge native Actor commit | 3 | 2 |

Final original RED is retained under
`build/performance-actor-commit/red-original-final/`. Both paired logs contain
exactly ten expected call-count failures, one public and one native assertion
for each Boss; no script/leak failure or behavioral assertion fails. Candidate
GREEN is 1/1 under `green-authorities-final/`, with strict paired stdout and
Godot engine log validation.

Final source neighboring regressions pass under `final-neighbors/`:
native owned frame token, Hostile Frame Bridge, and Boss control visual
observation. Native save checkpoint and Boss exposure replay checkpoint also
passed the preceding equivalent production path under `native-save/` and
`replay/`. The final refinement only restores revalidation for custom scripts.

| Executed source | Original SHA-256 | Candidate SHA-256 |
| --- | --- | --- |
| `launch_hostile_actor.gd` | `e5551e17a653fb7f848c39a27403be88e7ca27cab1c1b7533fe660db6eea6060` | `c2ed85d5f1099992d00b3b88c4bb1e733eb650fc41b4c50e32ec045757c714d2` |
| `launch_boss_actor.gd` | `c0810d55d13a62c6620e9d85e115376dac2591a8d2ad17a1038e859075acc34e` | `2f732d4d482d1340cd4c44349aec2844284c50a9d7e9cc2a7a91baa4f13d5a64` |

The identical focused test `.gd` SHA-256 is
`2fd04a82556ee64f8441edcf1d3cc49e1aaf1e5969637e49c418f1df5dde5200`;
its scene SHA-256 is
`7d7ffa4d6b0392a11c7af79804f786f58fa04ed630c0525a3cdd86f26773f62c`.

## Same Rendered Workload

Two frozen executed projects under
`build/performance-native-validation/same-load-before/` and
`same-load-after/` isolate concurrent artwork/UI work. Their retained
`source-manifest.json` files contain 415 runtime `.gd` sources and differ only
in the two Actor files above. The report records the executed project identity,
not its containing Git checkout's revision.

Both commands use `--frames 600 --hub-frames 120 --boss-floor 4 --phase 0
--rendered --timeout 900`. The reports are
`same-load-before/build/rendered-600-before/report.json` and
`same-load-after/build/rendered-600-after-authorities/report.json`.
Both accepted 600/600 actual native frames, frames 1 through 600, with unit time
scale, rendering, original 60 Hz scheduling, clean paired logs, stable runtime
source, stable identical Godot binary, and physically exact recording endpoints.

| Metric | Original mean / p95 ms | Candidate mean / p95 ms |
| --- | ---: | ---: |
| Player advance | 22.063 / 34.506 | 22.102 / 34.444 |
| Same-frame work | 23.622 / 37.063 | 23.684 / 36.694 |
| Same-frame wall | 27.123 / 41.981 | 27.370 / 41.675 |
| Observed process RSS peak, bytes | 771031040 | 706134016 |

The small timing differences do not demonstrate a stable FPS improvement, and
RSS differs between two processes on a shared host. The workload's observed
peaks are identical: one Actor, one projectile, two threats, one zone, and no
constructs/summons. This phase-zero encounter is not the larger stress workload.
The native interval is ten seconds; neither a 45-minute soak nor sustained
60 FPS is certified. Both tapes remain honestly `INTERRUPTED`, with 601 total
observations.

Both reports retain content aggregate
`39a346d5367c10553562fe08b6b8871457e7a5e3d7b4c176841827e89aa5edb6`,
base pack fingerprint
`c099e9be0d3e5d7ce4020012c08e1b0a9b63ae8c48f0156c570d5a23cd44163d`,
first sample
`8c2005f043725dcfc54169c4fb6abf0ef8c6ccdab1ffe7073a1bb9d26e460608`,
and last sample
`5f75a9c982540d08af01a6e249e061f0c67553a4434c48112da05d19e6aa35ad`.
Runtime source aggregates are
`b804d1aed0d25de850468f3b9ad985471b4a19b4b5b9097a5a74c252df018562`
and `790bd92818207eafbf1d4fc28b282424113328f578c9c0ef0625155cc37f3eeb`.
Report SHA-256 values are
`64270478b8681039cadfadb4f1a89a07f5988f35f5f69e51e23110f7c7800847`
and `f1c57a38ffce05d46eb5b5fd28d4bb5ab4ee5a068ba9c0116d2fc21361e94830`.

## Rejected Context Comparison Experiment

The build-only `context_compare_probe.gd` compares native `var_to_bytes` with a
recursive typed comparison against a detached context, using actual authored
Boss definitions and full contexts for 250 interleaved repetitions. Its clean
paired logs are `context-compare.stdout.log` and `context-compare.godot.log`.

| Boss full context | Native encoding mean us | Typed comparison mean us |
| --- | ---: | ---: |
| Ruin | 52.992 | 277.756 |
| Forest | 68.976 | 362.368 |
| Time | 61.212 | 309.784 |
| Forge | 140.424 | 718.116 |
| Void | 227.252 | 1148.208 |

This roughly five-times slower prototype was not adopted. It does not claim
complete Variant/IEEE comparator certification. The actual unchanged fixtures
already make its proposed performance approach unsuitable. Its SHA-256 is
`de6e7ee5337e2b803c5f7fd9c0fb81a3ee20c8cd9c29165d9d0cab6a984c4fff`;
the measured production Boss runtime SHA-256 is
`f0bad83364cc0107b6b1c3e70c35c8c32022ea4c45c7ecdf5e403a1aba8c1f97`.

Live private-definition changes, including integer-to-equal-float edits, still
require exact typed context invalidation. Further performance work must retain
that contract and measure the actual later-phase workload.
