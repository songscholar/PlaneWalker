# P15 Synthetic Domain Matrix Evidence

- Status: Verified Locally
- Document Role: Current focused domain certification evidence
- Authority Level: Retained P15 synthetic execution record
- Applies To: Thirty seeded matrices of five characters, five weapons, six time pairs, and five Bosses
- Owner: Project owner
- Last Verified: 2026-10-05
- Depends On: [Synthetic matrix plan](../superpowers/plans/2026-10-05-p15-synthetic-domain-matrix.md); [native Boss matrix evidence](2026-10-05-native-boss-matrix-evidence.md); authoritative Base Launch profiles and hostile runtimes
- Exit Gate: Exactly 22,500 unique cases, 52 executed authored moves, deterministic repeats, typed warning continuation, bounded payloads, clean logs, and authenticated source

## Retained Source

Implementation commits are `20dc837` (independent probe, driver, contracts and plan) and `40d09f2` (explicit retained-commit authentication). The completed run used an archive of exact commit `40d09f211b311a4e2bc766067656d4e9b59a5aab` at `build/test-source/p15-synthetic-retention`. Source archive `build/test-source/p15-synthetic-retention-source.tar` has SHA-256 `a2c80f67b403748e8a59e0cd867190ab95acd9aeeff2945cf071ba355fef8ac2`.

The driver verifies every domain file against the requested commit's Git blob and rechecks source hashes after all shards finish. The 441 script, Base data, driver and probe inputs have aggregate SHA-256 `354d4a3e9ce0afbd3f1f64f6f33a533c5a274a76fa1ad42efc4ec5c94db20197`. Later workspace edits cannot silently change this evidence. Base pack fingerprint is `083658d9d4f7af04b6f980f341f948fb75da26b4815a55fbb5b00c7fea8fcdd7`; runtime content aggregate is `838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`.

## Completed Matrix

The executable command was:

```sh
python3 build/test-source/p15-synthetic-retention/tools/run_p15_synthetic_matrix.py \
  --project-root build/test-source/p15-synthetic-retention \
  --source-commit 40d09f211b311a4e2bc766067656d4e9b59a5aab \
  --workers 4 --shard-size 750 --timeout-seconds 600 \
  --output build/p15-synthetic-matrix.json
```

The report is `build/test-source/p15-synthetic-retention/build/p15-synthetic-matrix.json`, SHA-256 `d482570eebf98ca73260a4002e7342284516e5ad7866ba10646e3c7c34889ae6`. It records `status=pass`, `complete=true`, and no errors. All 30 shards exited zero, and both stdout and engine logs were scanned for generic errors, script/parse failures and resource/object leaks with no matches. A second standalone `validate_report(..., require_complete=True)` invocation also passed against the retained source.

| Executed Criterion | Result |
| --- | --- |
| Unique seed/loadout/Boss identities | 22,500 / 22,500 |
| Canonical seed count | 30 (`2026100500` through `2026100529`) |
| Distinct parsed character/weapon/time-pair combinations | 150 |
| Boss identities | 5 |
| Authored primary moves plus paid Time Sovereign responses | 48 + 4, all executed; minimum 30 cases per move |
| Full authored enrage thresholds, advanced frame by frame | 150, one per seed/Boss |
| Accepted frame totals | 6,182,980 per pass, with each case run twice |
| Full trace repeat comparison | 22,500 byte-identical pairs |
| Typed JSON cold restore from an actual WARNING phase, exact next motion/batch/state | 22,500 |
| Malformed HP snapshot refused without mutation | 22,500 |
| Phase monotonicity, damage deduplication, and terminal cleanup | 22,500 |
| Seeded elite recipe observations | 17 authored recipes; `chaining` and `frenzy` references resolved |
| Distinct canonical profile-input digests | 150 |
| Elapsed wall time | 554.770 seconds, four workers, concurrent repository test activity |

Character attack and movement statistics and each weapon's actual primary payload and windup influence damage receipts and target context. Both equipped abilities contribute actual Boss Stop/Rift control conversion, authenticated Time Sovereign paid receipts, or explicit profile-derived synthetic attack observations. The report validator compares those structured inputs back to the authoritative content definitions and checks both equipped input identities and observations.

## Supplemental Checks

Each shard separately runs a repeated eight-case Time Sovereign positive-response probe across both phases: Stop's 40 admitted watch damage cancels its pulse and grants 60 frames of exposure; one Rewind echo grants 30 frames once; six distinct accelerated hits shatter the finite field once and grant 90 frames; the Rift pulse grants 45 extra recovery frames. All 240 supplemental cases passed repeat equality, typed warning continuation, paid-receipt deduplication, and terminal retirement. They are not included in the 22,500 count.

Thirty dedicated budget probes passed: 32 live projectiles with 224 pending reservations, 256 total reservations, the 257th refusal without mutation, 12 reserved zones with the 13th pending, a maximum simultaneous 12-zone damage pulse, exact typed payload next-frame continuation, eventual projectile/zone expiry, a four-entry response queue under ten paid receipts, and terminal response cleanup.

Seven Python contract tests passed both in the workspace and retained archive. They reject aliased identities, unsupported indices, partial reports claiming completion, missing cases, non-finite damage, stale report reuse after a failed process, unauthenticated source commits, and semantic mutations to runtime classification, profiles, time observations, action ownership, enrage, cold continuation, budgets, counterplay, coverage and reported errors. The initial two missing-tool contracts and later scope/metadata fixtures were observed failing before implementation.

The archive's bootstrap import emitted only the known absent generated translation derivatives; its second import log `build/p15-synthetic-retained-import-clean.log` was clean. One initial import invocation used a relative log path before its parent existed and triggered Godot's logger crash; it produced no matrix result and was replaced with the explicit absolute log path. The completed matrix uses absolute per-shard log/output paths.

## Limits

This certification instantiates authoritative Boss and payload domains, not a physical Player. It rotates one committed action per matrix case, supplies admitted synthetic phase/damage facts, observes seeded elite recipe data without simulating those elite enemies, and retires cases explicitly. Character passive/skill nodes, physical weapon collision, five-floor victory, native frame scheduling, controller interaction and visual presentation are covered by their separate suites and cannot be inferred from this report.

Classification remains `synthetic=true`, `production_case_count=0`, `human_playtests=0`, `unassisted_victory=false`. The 240 response supplements and 30 budget probes are separate evidence, not extra loadout or human cases. The measured execution duration under concurrent local work is throughput evidence only, not a gameplay frame-time benchmark or a player-experience tuning result.
