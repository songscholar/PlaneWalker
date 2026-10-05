# Native Boss Matrix Evidence

- Status: Partial / Current
- Document Role: Current executable P15 Task12 native matrix retention evidence
- Authority Level: Approved P15 specification and project standing authorization
- Applies To: Five Characters, five production weapons, six time pairs and five native Bosses
- Owner: Native hostile integration team
- Depends On: `docs/superpowers/plans/2026-10-05-native-boss-loadout-matrix.md`
- Last Verified: 2026-10-05

## Executable Path

`tests/smoke/p15_hostile_loadout_matrix_test.tscn` loads the authoritative Launch
Base Pack and production Boss Rush catalog/arena builder. Every case uses the
real Player, canonical weapon/time loadout, native Boss room, Effects and
frame bridge. Semantic primary/release/reload input produces physical damage;
no substitute damage records or Boss HP/stat writes drive victory.

Each case requires positive weapon damage in every authored HP phase, both
actual TimeManager receipts, a positive time benefit, and one authenticated
terminal death receipt. An active checkpoint is encoded with typed Replay,
written/recovered by physical SaveService, reconstructed in fresh native
actors/effects and compared against the exact original next frame. Terminal
cleanup checks work, summons, threat facts, controls and construct collisions.
Named Player descendant bindings preserve charged Staff burn ownership during
cold reconstruction. Failure diagnostics are bounded, and prepare-only probes
compensate their actor/effect candidates before returning.

Player survival uses the declared `p15_matrix_survival_fixture` invulnerability
source. This establishes interaction compatibility, not unassisted balance.
Certification uses Engine physics60Hz and time scale1.0. The CLI invokes
Godot's `--fixed-fps 60`, which removes real-time synchronization while keeping
the production physical frame clock. Paced/unpaced case20 retained exactly
equal complete case data and typed checkpoint digest, with671frames and a
real accelerated physical hit.

The regular scene suite defaults to one case. Explicit CLI ranges are partial;
only exactly750 passing canonical cases can set `native_complete` true:

```sh
python3 tools/run_p15_hostile_matrix.py \
  --output build/p15-native-full.json \
  --logs build/test-evidence/p15-native-full \
  --jobs 5 --timeout 28800
```

The version2 CLI validates identity coverage, all HP phases, finite actual
damage and exact per-phase trace totals, source/frame/hit identity, native
authentication and explicit raw legacy aliases, legal content-defined actions,
canonical time/death receipts and the closed authoritative Base Pack content
fingerprint. It confines reports/logs to the workspace and scans both stdout
and the independent engine log for errors/leaks. The strengthened checks
first rejected23 previously accepted missing/forged evidence variants.
All12 report-contract tests now pass. Source hashes are captured before the
run and compared afterward; a changed runtime/runner fails certification.
Full certification runs use an immutable checkout snapshot.

## Retained Partial Results

The canonical-clock Sword0--29 measuring run has completed24 actual cases so
far, with53848frames, no native assertion failures and all completed rows
accepted by the final strict version2 validator. Its initial CLI process
loaded an earlier validator, and production source changed during execution;
this measuring run is diagnostic evidence only. Its final aggregate must
retain those original validation/source failures. Stable-source certification
will rerun from a retained immutable Git archive including the current-target
native shape-query repair.

The following earlier repaired cases passed their then-current harness with
typed cold reconstruction, exact continuation and terminal cleanup. They are
historical defect evidence, not certification results: that harness used
Engine1000ticks with scale1000/60, which left physical delta at1/60 but changed
Controller/Sword/Health second-to-frame conversions. In particular TIME_CAST
expanded from11 to180frames and consumed the entire Accelerate window.
Version2 standard-clock cases must be rerun before certification.

| Case | Character/Weapon/Pair/Boss | Frames | Report |
| --- | --- | ---: | --- |
| 33 | Wanderer/Bow/Stop+Rewind/Forge | 2210 | `build/p15-native-forge-cleanup.json` |
| 34 | Wanderer/Bow/Stop+Rewind/Void | 3760 | `build/p15-native-void-bow-recoil-fixed.json` |
| 64 | Wanderer/Gun/Stop+Rewind/Void | 8048 | `build/p15-native-void-gun-recoil-fixed.json` |
| 92 | Wanderer/Staff/Stop+Rewind/Time Sovereign | 4482 | `build/p15-native-staff-time-admission-fixed.json` |
| 121 | Wanderer/Gauntlets/Stop+Rewind/Forest | 2073 | `build/p15-native-forest-gauntlets-fractional-fixed.json` |
| 124 | Wanderer/Gauntlets/Stop+Rewind/Void | 6077 | `build/p15-native-void-gauntlets-recoil-fixed.json` |

The resource-aware Staff input policy charges45frames when its real runtime
mana can pay20, then uses ordinary free arcane taps. Actual Staff cases90,
91 and93 passed at1681,2918 and5838frames; their isolated reports are under
`build/test-evidence/native-boss-matrix-staff-resource-aware-five`.
Staff92 exposed unsafe automatically selected summon prepublication retirement;
its focused RED/GREEN evidence and successful actual rerun are retained
separately. Staff94 also passed9757frames in that historical harness. Both
are retained for diagnosis and excluded from production-clock certification.

## Remaining Gate

The all750 matrix is not complete. Earlier failure reports are retained as
defect evidence and are not combined into a passing full report. The CLI keeps
`p15_complete: false`, synthetic coverage0/22500 and human playtests0.

P15 also still requires its separate22500 seeded domain traces, all48 primary
and four response moves, arena interactions, publication rollback boundaries,
natural five-floor Host flow, native visual/interaction QA, clean exports and
human sessions. This executable matrix and its partial evidence cannot close
those gates.
