# Plane Walker P15A Hostile Content Evidence

- Status: Implemented / Current
- Document Role: Current partial-milestone evidence
- Authority Level: Closed hostile authoring and pure definition contracts
- Owner: Project integration lead
- Applies To: Inactive enemy, Boss, affix, summon catalogs, runtime projections, schemas, and localization preparation
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-04-plane-walker-p15-enemies-bosses.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Pure content boundary only; complete native behavior, content activation, and whole-repository certification pending

## Delivered Boundary

Implementation commit `c405ad1` contains twenty-two ordinary enemy definitions with forty-five base actions and twenty-two species elite actions, five Boss definitions with forty-eight primary moves and four Time Sovereign responses, ten elite affix definitions, and nine nonrecursive summon definitions. All four catalogs remain outside the active Base Pack content manifest and have no newly activated actor or asset references.

Five closed JSON schemas validate the shared fifteen-handler action vocabulary and four definition categories. `EnemyDefinition`, `BossDefinition`, `EliteAffixDefinition`, and `SummonDefinition` reject unknown fields, unsupported identities, invalid numeric types, incompatible actor/floor references, and malformed mechanisms. Failed configuration clears previous state. Returned definitions, snapshots, and runtime projections are deeply isolated.

Enemy native projections contain exactly eight fields: `id`, `actor_kind`, `runtime_kind`, `max_hp`, `defense`, `move_speed`, `actions`, and `mechanisms`. Keeping mechanisms in this projection prevents the native implementation from silently ignoring authored tuning. Elite projection preserves base action order, appends the species action, applies twice base HP, and multiplies each scheduled damage by 1.25 once. Runtime integration must consume these values; this record does not certify all native species.

Boss projections contain twelve fields: the same identity/stats/action fields plus `phases`, `enrage`, `arena`, `mechanisms`, and `time_responses`. The parser verifies the complete primary action identity order, canonical phase sets and thresholds, enrage clocks, twenty-frame idle, selection weights, consecutive-use budgets, declared constructs, and phase damage overrides. Arena metadata declares a safe corridor of at least forty-eight pixels; actual reachability under combined hazards remains a native integration gate.

Every summon has explicit spawn and damaging-warning floors, finite lifetime, empty capabilities, and no independent reward. `elite_mirror` binds a valid ordinary parent, uses its declared twenty-percent HP and fifty-percent damage ratios, and must execute only that parent's first damaging action. Its absolute scalar placeholders are not a usable native actor definition. Parent resolution, disabled recursive behavior, and physical summon retirement require native tests before activation.

The specification's response-wide forty-five-frame warning floor conflicts with the thirty-frame entry for `traitor.counter_accelerate`. Authoring uses forty-five frames, preserving the stronger declared response floor and avoiding a shortened hostile warning. No Player time source is removed by this content decision.

## Verification

Missing-parser RED evidence is retained under `build/test-logs/p15-enemy-definition-red`, `p15-boss-definition-red`, and `p15-support-definition-red`. Missing-content/schema RED was recorded before authoring under `build/p16-review/p15-content-red.log`.

`python3 -m unittest tests.contract.content_schema.test_p15_hostile_schemas` passes seven tests. It verifies exact counts/identity sets, every authored schema, phase/action and scheduled-hit boundaries, required/unknown nested fields, symmetric exclusions, nonrecursive summons, and complete draft localization.

`TEST_LOG_DIR=build/test-logs/p15-content-native-final-green ./tools/run_tests.sh --filter definition --timeout 20` passes all three native definition scenes. The cases parse real catalogs and reject missing fields, Boolean-as-number, nonfinite values, unknown same-species actions, arbitrary script fields, malformed mechanisms/constructs, invalid references, warning-floor violations, unsupported response IDs, and recursive/rewarding summons. No script errors or leaks occur in these GREEN logs. Godot line coverage remains unavailable and no percentage is inferred from scene counts.

The two shared translation CSVs now include all 221 authored name, description, action-cue, and affix-cue keys from `data/localization/drafts/p15_hostiles.csv`. Only the existing localization integrity hash is refreshed in `pack.json`; no hostile catalog or scene is activated. `tools/validate_localization.py` passes, its eight Python contracts pass, and the headless editor import completes without errors or leaks. Native content-registry and content-pack regressions each pass one scene under `build/test-logs/p15-content-registry-green` and `p15-content-pack-green`.

## Remaining Scope

This boundary does not implement or certify all species/Boss/affix/summon behaviors, semantic effect handlers, actor scenes, encounter composition/activation, attack geometry ownership, Save/Replay seals, complete raster/audio assets, controller/visual QA, the 750 production Boss-loadout matrix, full dungeon routing, balance, or exported builds. These remain explicit P15 completion gates. Native mechanism and integration work continues independently against the tracked projections.
