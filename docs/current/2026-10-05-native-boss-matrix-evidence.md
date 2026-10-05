# Native Boss Matrix Evidence

- Status: Partial / Current
- Document Role: Current executable P15 Task12 native matrix retention evidence
- Authority Level: Approved P15 specification and project standing authorization
- Applies To: Five Characters, five production weapons, six time pairs and five native Bosses
- Owner: Native hostile integration team
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
Domain frames remain60Hz while the test accelerates wall-clock scheduling.

The regular scene suite defaults to one case. Explicit CLI ranges are partial;
only exactly750 passing canonical cases can set `native_complete` true:

```sh
python3 tools/run_p15_hostile_matrix.py \
  --output build/p15-native-full.json \
  --logs build/test-evidence/p15-native-full \
  --jobs 5 --timeout 28800
```

The CLI validates identity coverage, all HP phases, finite actual damage,
canonical time/death receipts and the closed authoritative Base Pack content
fingerprint. It confines reports/logs to the workspace and rejects engine,
script and leak diagnostics. Report-contract tests are GREEN6/6.

## Retained Partial Results

These repaired actual cases passed with typed cold reconstruction, exact
continuation and authenticated terminal cleanup:

| Case | Character/Weapon/Pair/Boss | Frames | Report |
| --- | --- | ---: | --- |
| 33 | Wanderer/Bow/Stop+Rewind/Forge | 2210 | `build/p15-native-forge-cleanup.json` |
| 34 | Wanderer/Bow/Stop+Rewind/Void | 3760 | `build/p15-native-void-bow-recoil-fixed.json` |
| 64 | Wanderer/Gun/Stop+Rewind/Void | 8048 | `build/p15-native-void-gun-recoil-fixed.json` |
| 121 | Wanderer/Gauntlets/Stop+Rewind/Forest | 2073 | `build/p15-native-forest-gauntlets-fractional-fixed.json` |
| 124 | Wanderer/Gauntlets/Stop+Rewind/Void | 6077 | `build/p15-native-void-gauntlets-recoil-fixed.json` |

The resource-aware Staff input policy charges45frames when its real runtime
mana can pay20, then uses ordinary free arcane taps. Actual Staff cases90,
91 and93 passed at1681,2918 and5838frames; their isolated reports are under
`build/test-evidence/native-boss-matrix-staff-resource-aware-five`.
Staff92 exposed unsafe automatically selected summon prepublication retirement;
its focused RED/GREEN evidence is retained separately. Staff92/94 reruns are
in progress and are not counted as complete here.

## Remaining Gate

The all750 matrix is not complete. Earlier failure reports are retained as
defect evidence and are not combined into a passing full report. The CLI keeps
`p15_complete: false`, synthetic coverage0/22500 and human playtests0.

P15 also still requires its separate22500 seeded domain traces, all48 primary
and four response moves, arena interactions, publication rollback boundaries,
natural five-floor Host flow, native visual/interaction QA, clean exports and
human sessions. This executable matrix and its partial evidence cannot close
those gates.
