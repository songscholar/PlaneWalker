# Native Action Validation Template Evidence

- Status: Implemented / Current
- Document Role: Current focused immutable Action validation authority evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Complete Boss current and historical Action snapshot validation
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-action-validation-template-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No FPS, rendered, soak, coverage or human certification

## Verified Boundary

The original live Action validator delegates to one pure static implementation
of the same checks. Boss validation uses detached, recursively read-only action
definitions, identity, actor kind and digest from a successfully configured
fresh Action. Actual Boss restoration and action-regime changes continue to
construct independent mutable Action coordinators.

The template key reuses the already computed exact typed Boss configuration
bytes and compares phase, enrage, current/historical Void geometry and
current/historical Time responses separately. Direct definition and origin
changes invalidate prior templates, including numerically equal changes with
different Variant types. Negative configurations do not populate the cache.
There are at most four retained templates, at most 262,144 encoded bytes per
context/template pair and at most 1,048,576 aggregate encoded bytes. Oversized
sources configure and validate independently without retention. Full Boss,
auxiliary, receipt and strict native validation remain executable.

## Focused Contracts

`build/native-action-template-red` records eight fresh mutable Action
constructions for eight repeated full uncached validations of each authored
Boss. The final focused fixture in `build/native-action-template-green-5`
records zero repeated validation-only constructions after legitimate warm-up.
It leaves all typed Boss state bytes unchanged.

The fixture covers five authored Bosses, every phase/enrage and historical flag
combination, exact normalized authority, deep read-only ownership with no
Objects, typed integer guards, identity/digest/action/geometry corruption,
missing and unknown fields, direct authority mutation, negative configuration,
cache bounds/eviction, oversized fallback, concurrent read-only validation and
independent mutable restoration. Actual Action clocks cross the final warning,
first/final active, first/final recovery and ended boundaries. Independent
restored coordinators produce exact next hit/effect/retirement batches.

Complete current Boss snapshots for all five Bosses and historical Action
regimes for Void and Time pass strict native validation and independent complete
Boss restoration through warning, active, recovery and ended boundaries. Typed
Boss/auxiliary bytes and actual next-frame outputs remain exact. Existing Void
and Time migration and receipt guards also pass the enemy unit regression.

An intermediate expanded fixture in `build/native-action-template-green-2`
incorrectly expected a different valid target identifier to fail pure Action
validation. The original validator accepts any nonempty stable target String;
higher authorities bind target ownership. That expectation was corrected
without changing production validation. GREEN-3, GREEN-4 and final GREEN-5 pass.

| Contract | Retained Logs | Scenes |
| --- | --- | ---: |
| Final template, current/historical clock and complete Boss boundaries | `build/native-action-template-green-5` | 1 |
| Complete enemy units, direct-mutation caches, original Boss and receipt/migration contracts | `build/native-action-template-enemy-units` | 44 |
| Native actor/Boss/payload/Time/Void transactions and replay neighbors | `build/native-action-template-<scene_name>` | 13 |
| Complete physical native combat checkpoint suite, including historical and paid Time Boss cases | `build/native-validation-input-checkpoint` | 1 / 25 cases |

The thirteen exact native/replay scene names for the retained log convention are
`launch_actor_transaction_test`, `launch_boss_actor_test`,
`launch_boss_payload_test`, `time_response_native_test`,
`void_half_arena_native_test`, `void_auxiliary_native_test`,
`void_payload_identity_test`, `native_boss_payload_retirement_test`,
`boss_temporal_native_test`, `boss_exposure_checkpoint_test`,
`native_run_replay_terminal_test`, `native_run_replay_recorder_test` and
`native_run_replay_backpressure_test`. Each passes its paired strict logs. The
root lane's complete checkpoint scene loads both current Action production
changes and passes all 25 physical save/restore cases with paired strict logs.

The 44-scene enemy run executes the earlier GREEN-4 fixture; final GREEN-5 adds
the explicit complete historical Void/Time Boss boundaries and is verified
separately. Verified paired stdout/Godot logs pass strict scoped runtime
validation without unexpected warnings, script/parse failures or object/RID
leaks. Godot is `4.6.1.stable.official.14d19694e`; line coverage is unsupported.

## Remaining Measurement

Counted configuration work proves eliminated constructions, not complete-frame
throughput. Uninstrumented native timing, rendered performance, the 45-minute
soak, UI visual acceptance and human playtesting remain separate open gates.
