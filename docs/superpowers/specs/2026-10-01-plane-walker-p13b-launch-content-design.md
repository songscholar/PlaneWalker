# Plane Walker P13B Complete Launch Pools and Effect Certification Design

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: P13B content-count, effect-runtime, reward-transaction, active-item, talent, UI, Replay, and certification authority below the Full Product Completion Design
- Applies To: Exactly 50 Launch items, 28 blessings, 18 curses, 15 character run talents, eight archetypes, reward drafting, runtime effect application, one active-item slot, HUD/input/feedback, Replay, simulations, and local evidence
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/current/2026-10-01-p13a-launch-archetype-authority-evidence.md`, `docs/contracts/content-pack-v2.md`
- Supersedes: Legacy content-count and generic-stat recommendations in `docs/3.3_道具系统设计.md` and `docs/3.4_祝福与诅咒系统设计.md` where they conflict with this exact Launch pool
- Last Verified: 2026-10-01
- Implementation Status: Locally certified at implementation commit `9a04639`; exact Launch pools, typed effects, atomic rewards, eight active items, fifteen talents, Replay schema 6, SaveEnvelope schema 2, deterministic formation, 150 loadouts, and the `168 / 168` repository gate are recorded in `docs/current/2026-10-01-p13b-launch-content-evidence.md`
- Contract References: `data/schemas/content_entry_v2.schema.json`, `data/content/effect_catalog.json`, P13A archetype profiles, P12 character runtime profiles

## 1. Decision

P13B completes delivery step 6 of the Full Product Completion Design without widening or redefining the P13A archetype taxonomy. The Launch Base Pack exposes exactly:

```text
50 items = 42 passive + 8 active
28 blessings
18 curses
15 character run talents
```

Every Launch item, blessing, and route curse belongs to one of the eight authoritative archetypes or is explicitly marked `generalist + utility`. The fifteen talents remain the approved five-character × three-choice character routes from P12. Character talents are orthogonal to the eight build archetypes: they may reinforce several archetypes but may not create a ninth top-level identity.

M1/CURRENT/NEXT definitions and deterministic reward behavior remain compatible. Launch additions use Launch/Expansion availability and cannot appear in earlier milestones unless an existing definition already has an approved earlier availability.

## 2. Product goals

P13B must make each archetype recognizable from actual player choices rather than labels alone:

- three or more starter options establish the route;
- two or more payoff options convert setup into a visible reward;
- one or more risk options create a readable cost or execution burden;
- one active item gives the route a deliberate, player-triggered peak moment;
- every effect has a typed bounded runtime path, UI summary, deterministic snapshot behavior, and regression test;
- every reward selection is atomic across authoritative run state and player runtime.

Content count alone is not completion. Entries with empty effects, unreachable handlers, backend-only state, missing localization, or no player-facing feedback fail the gate.

## 3. Exact Launch catalog

### 3.1 Items: 42 passive and 8 active

`P` means passive and `A` means active. Every route contains exactly one active item.

| Archetype | Exact item IDs |
|---|---|
| `freeze_burst` | `frozen_burst` P starter; `stasis_lens` P starter; `brittle_clock` P starter; `weakpoint_prism` P payoff; `frozen_afterimage` P payoff; `absolute_zero_device` A risk |
| `rewind_echo` | `rewind_echo` P starter; `anchor_thread` P starter; `history_blade` P starter; `echo_reservoir` P payoff; `pathbreaker_lens` P payoff; `paradox_beacon` A risk |
| `rift_trap` | `rift_engine` P starter; `rift_anchor` P starter; `folded_corridor` P starter; `rift_conductor` P payoff; `rift_snare` P payoff; `gravity_snare_device` A risk |
| `accelerated_combo` | `accelerated_combo` P starter; `cadence_core` P starter; `overdrive_heart` P starter; `accelerant_window` P payoff; `efficient_overdrive` P payoff; `redline_injector` A risk |
| `low_hp_void` | `void_brink` P starter; `void_contract` P starter; `hunger_edge` P payoff; `abyssal_siphon` P payoff; `blood_price_relic` A risk |
| `perfect_guard` | `cleaving_moment` P starter; `evasive_guard_route` P starter; `counter_battery` P payoff; `warded_edge` P payoff; `aegis_reversal` A risk |
| `piercing_barrage` | `piercing_draw` P starter; `tempo_barrage` P starter; `focused_draw` P payoff; `ricochet_matrix` P payoff; `railshot_module` A risk |
| `echo_legion` | `mirror_seed` P starter; `phantom_lens` P starter; `legion_core` P payoff; `decoy_crown` P payoff; `army_of_yesterday` A risk |
| General utility | `chronal_battery`, `quickened_blade`, `rewind_salve`, `rift_current`, `sword_edge`, `tempered_guard` — all P utility with `generalist` and `utility` tags |

Existing M1/NEXT item IDs retain their earlier milestone availability and add Launch/Expansion only after their effects pass the same certification as new entries.

### 3.2 Blessings: 28

| Archetype | Exact blessing IDs |
|---|---|
| `freeze_burst` | `bls_stop_weakpoint`, `bls_stasis_shatter`, `bls_cold_execution` |
| `rewind_echo` | `bls_rewind_path`, `bls_anchor_memory`, `bls_echo_harvest` |
| `rift_trap` | `bls_folded_ground`, `bls_projectile_slow`, `bls_rift_bloom` |
| `accelerated_combo` | `bls_sword_tempo`, `bls_cadence_chain`, `bls_overdrive_refund` |
| `low_hp_void` | `bls_void_threshold`, `bls_hunger_conversion`, `bls_bloodless_focus` |
| `perfect_guard` | `bls_counter_window`, `bls_guard_reserve`, `bls_aegis_tempo` |
| `piercing_barrage` | `bls_piercing_line`, `bls_weakpoint_refund`, `bls_ballistic_clock` |
| `echo_legion` | `bls_mirror_action`, `bls_legion_focus`, `bls_decoy_stride` |
| General utility | `bls_survive_thread`, `bls_chronal_reserve`, `bls_wayfinder_mercy`, `bls_adaptive_arsenal` |

For each route, the first new route entry is a starter and the remaining route entries are payoffs unless an existing blessing already supplies the starter. Blessings are persistent positive modifiers; they never hide a negative cost.

### 3.3 Curses: 18

| Archetype | Exact curse IDs |
|---|---|
| `freeze_burst` | `curse_stasis_fracture`, `curse_thaw_debt` |
| `rewind_echo` | `curse_blood_memory`, `curse_erased_present` |
| `rift_trap` | `curse_starved_horizon`, `curse_folded_hunger` |
| `accelerated_combo` | `curse_glass_cadence`, `curse_burnout_clock` |
| `low_hp_void` | `curse_brittle_pact`, `curse_empty_veins` |
| `perfect_guard` | `curse_narrow_counter`, `curse_shattered_aegis` |
| `piercing_barrage` | `curse_recoil_tax`, `curse_empty_magazine` |
| `echo_legion` | `curse_divided_self`, `curse_phantom_attention` |
| General utility contracts | `curse_fickle_time`, `curse_brittle_fortune` |

Route curses use role `risk` and contain both a bounded upside and a bounded downside. The two general contracts use an empty archetype plus `generalist + utility` and still expose their tradeoff in localized text and effect summaries.

The six existing M1/NEXT curses — `blood_rewind`, `glass_tempo`, `overclocked_stasis`, `brittle_vitality`, `narrow_escape`, and `starving_clock` — keep their current availability, empty archetype, role, and effects. They are not counted in the eighteen Launch curses. Reusing them as Launch route risks would change frozen M1 BuildState scoring or make NEXT content invalid under the three-route domain.

### 3.4 Character run talents: 15

The exact P12 identities remain:

| Character | Exact talent IDs |
|---|---|
| `wanderer` | `tal_eternity_reserve`, `tal_ruin_execute`, `tal_steel_recover` |
| `time_guardian` | `widened_guard`, `fortress_core`, `temporal_rebuke` |
| `void_walker` | `deep_debt`, `bounded_devour`, `risk_step` |
| `primordial_knight` | `resonant_plate`, `echo_forge`, `realm_collapse` |
| `time_lord` | `codex_margin`, `efficient_inscription`, `dominion_cadence` |

Talent scalar values move into their versioned content definitions. `CharacterTalentState` retains canonical order and base values but consumes selected definition effects instead of duplicating selected values in code. A talent offer is filtered to the active character, and installing a newly selected talent updates the live character runtime transactionally.

## 4. Content schema and effect authority

### 4.1 Item mode and active definitions

Item entries add these category-specific fields:

```text
item_mode: passive | active
active_handler_id: one of eight closed handler IDs, active items only
cooldown_frames: integer 1..3600, active items only
active_parameters: closed scalar dictionary validated by handler, active items only
```

Passive items reject active-only fields. Active items require role `risk`, one authoritative archetype, the `active` tag, non-empty parameters, a localized cooldown summary, and exactly one handler:

```text
absolute_zero
paradox_beacon
gravity_snare
redline_injector
blood_price
aegis_reversal
railshot
army_of_yesterday
```

No content definition may contain a script path, method name, Callable, scene path, or arbitrary nested executable payload.

The exact active parameter contracts are:

| Handler | Exact parameters and inclusive bounds |
|---|---|
| `absolute_zero` | `radius` number `32..512`; `duration_frames` integer `1..600`; `weakpoint_bonus` number `0..3`; `energy_cost` number `0..100` |
| `paradox_beacon` | `rewind_frames` integer `1..600`; `echo_damage_multiplier` number `0..3`; `energy_cost` number `0..100` |
| `gravity_snare` | `radius` number `32..512`; `duration_frames` integer `1..600`; `slow_ratio` number `0..0.9`; `energy_cost` number `0..100` |
| `redline_injector` | `duration_frames` integer `1..600`; `speed_multiplier` number `1..3`; `health_cost_ratio` number `0..0.5` |
| `blood_price` | `duration_frames` integer `1..600`; `damage_multiplier` number `1..5`; `health_cost_ratio` number `0..0.5` |
| `aegis_reversal` | `duration_frames` integer `1..600`; `counter_multiplier` number `0..5`; `energy_cost` number `0..100` |
| `railshot` | `pierce_bonus` integer `1..20`; `damage_multiplier` number `1..5`; `ammo_refund` integer `0..20` |
| `army_of_yesterday` | `echo_count` integer `1..8`; `duration_frames` integer `1..600`; `echo_damage_multiplier` number `0..2`; `energy_cost` number `0..100` |

Each handler requires exactly its listed keys. Missing, additional, wrong-type, non-finite, or out-of-range values fail before pack activation.

### 4.2 Passive effects

`EffectHandlerCatalog` remains the closed scalar-effect authority. Every catalog row specifies value type, bounds, stack rule, allowed categories, and optional weapon capability routes. P13B adds route-specific effect IDs only when a live runtime consumer and a focused execution test are added in the same task.

`PlayerRewardEffectRuntime` stages effects into four domains:

1. Stats and Health.
2. TimeManager modifiers.
3. Weapon capability modifiers.
4. Character talent or route-hook modifiers.

The runtime produces an immutable plan, validates every target and bound, commits all domains, and rolls back all committed domains if any later domain rejects. Trigger effects such as healing or energy restore run only after persistent domains commit.

### 4.3 Reward selection transaction

The current commit-then-void-apply sequence is replaced with a two-phase transaction:

```text
DraftService resolves canonical definition
→ PlayerRewardEffectRuntime prepares isolated plan
→ RunRuntimeFacade reserves the selection revision
→ player runtime commits the effect plan
→ RunOrchestrator commits BuildState and consumes the offer
→ UI closes and publishes reward_selected exactly once
```

If preparation, player commit, authoritative commit, or transition fails, the offer remains open and player/run snapshots return to their exact pre-selection values. Active item replacement uses the same transaction and never silently discards an equipped item.

## 5. Active item runtime and UI

The Launch run has one active-item slot. Selecting an active item while the slot is occupied opens a native replacement confirmation; declining leaves both reward and current slot unchanged.

`ActiveItemRuntime` owns stable content ID, handler ID, cooldown, activation token, generation, and handler-specific bounded state. It exposes:

```gdscript
configure(definition: Dictionary) -> bool
plan_activate(context: Dictionary) -> Dictionary
commit_activate(plan: Dictionary, token: int) -> Dictionary
advance_frame(context: Dictionary) -> Array[Dictionary]
snapshot() -> Dictionary
can_restore_snapshot(value: Dictionary) -> bool
restore_snapshot(value: Dictionary) -> bool
reset_runtime_state(reason: StringName) -> void
```

Input action `active_item` is keyboard/controller remappable and follows the existing semantic-intent and focus rules. The HUD shows localized item name, icon, ready/cooldown state, and accessible text. Feedback uses Pixel Proxy/VFX/audio/subtitle channels with reduced-motion, flash, shake, and contrast budgets.

## 6. Drafting and build formation

Launch drafting continues to show exactly three options. Candidate filters additionally enforce:

- character compatibility for talents;
- weapon/time compatibility for route content;
- no duplicate unique item or already selected talent;
- active replacement availability before presenting an active item;
- exact Launch pool identity and count contract.

Thirty canonical seeds must expose all eight routes without starving starter, payoff, risk, utility, curse, talent, or active-item categories. A larger deterministic formation matrix verifies that every route reaches at least one valid `3 starter / 2 payoff / 1 risk` build without requiring an incompatible character, weapon, or time pair.

## 7. Replay, save, and presentation

Replay and snapshots include:

- selected reward definition IDs and normalized effect digest;
- passive effect-domain snapshot;
- equipped active item, cooldown, token, generation, and handler state;
- selected live character talents and modifier digest;
- BuildState archetype scores and dominant identity.

Restore rejects unknown effect IDs, changed bounds, content fingerprint mismatch, missing active handler, invalid cooldown, stale token/generation, incompatible talent, or reward-prefix drift. Save compatibility keeps prior M1/P11/P12 snapshots valid through explicit defaults and migration tests.

ChoicePanel and Combat HUD always render localized names, role, archetype, rarity, effect summaries, active cooldown, and replacement state. Stable IDs never appear as player-facing fallback text.

## 8. Verification gate

P13B is locally complete only when all of the following pass:

- exact `50 / 28 / 18 / 15` Launch counts and `42 passive / 8 active` item split;
- exact catalog IDs, no duplicates, localization coverage, icons, availability, compatibility, roles, and archetype references;
- every non-empty effect catalog entry has at least one runtime consumer test;
- all fifteen talent definitions match live character modifiers and all forty canonical subsets;
- all eight active handlers pass boundary, cooldown, rollback, Replay, reset, and feedback tests;
- atomic reward selection passes injected failure at every transaction phase;
- 30-seed Launch draft determinism and route exposure;
- deterministic build-formation simulation for all eight archetypes;
- 150 loadout smoke remains green with representative pool application;
- controller-only active-item and replacement flow passes;
- full project validation and documentation governance pass with only registered warnings.

Formal M1 remains `M1 Candidate — External Validation Pending`; authentic external human playtests remain `0 / 20`. Automated content and balance simulations are not human feel evidence. Line coverage, installed export templates, distributable startup, signing, remote push, store configuration, and publication remain honest external or environment-dependent boundaries.

## 9. Rollback and sequencing

P13B is implemented in focused commits: schema/contract, passive effect transaction, item pool, blessing pool, curse pool, talent data authority, active items, draft/UI/Replay, simulation, and certification. Each commit preserves M1 tests and Base Pack integrity. A category that is not yet complete remains unavailable at Launch rather than exposing partial or unexecutable definitions.
