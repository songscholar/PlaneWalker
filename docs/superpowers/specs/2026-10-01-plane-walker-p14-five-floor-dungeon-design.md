# Plane Walker P14 Five-Floor Dungeon, Route, Economy, and Event Design

- Status: Approved / Current
- Document Role: Current P14 specification
- Authority Level: Five-floor route, room-template, floor-rule, economy, merchant, event, map UI, Save, and Replay authority below the Full Product Completion Design
- Applies To: Five Launch floors, deterministic route graphs, thirty room templates, streamed room scenes, five floor rules, one Launch economy profile, five merchant identities, fifteen regular events, three special events, map/shop/event/rest UI, Save migration, Replay, simulations, and local certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/3.5_地牢生成与关卡设计.md`, `docs/current/2026-10-01-p13b-launch-content-evidence.md`, `docs/contracts/content-pack-v2.md`
- Supersedes: The continuous `200 x 200` BSP world and corridor-instantiation proposal in `docs/3.5_地牢生成与关卡设计.md`; its floor themes, room intentions, event catalog, and economy targets remain product references
- Last Verified: 2026-10-01

## 1. Decision

P14 implements delivery step 7 of the Full Product Completion Design as a deterministic route graph whose nodes stream hand-authored Godot room scenes. It does not build one continuous BSP dungeon. A route graph preserves meaningful branch choices, seed reproducibility, Save/Replay stability, and map readability; hand-authored scenes preserve combat framing, telegraph space, pixel composition, and controller navigation.

The Launch program exposes exactly:

```text
5 floors
30 room templates
  10 combat
   5 elite
   3 treasure
   2 shop
   3 event
   5 boss-room
   2 rest
15 regular events
 3 special events
 5 merchant identities
 1 Launch economy profile
```

The five floor identities are exact and ordered:

```text
floor_ruins_of_remnant
floor_void_forest
floor_time_rift
floor_plane_forge
floor_throne_of_void
```

M1 keeps its frozen five-room linear adapter. Launch and Expansion use `FloorPlan` and the streamed room host. P14 does not claim the twenty-two Launch enemy behaviors, elite affixes, or five Boss behavior kits owned by P15. Boss-room scenes, encounter references, doors, presentation, and lifecycle integration are P14 scope; Boss combat behavior is not.

## 2. Product goals

P14 must make a five-floor run feel like a sequence of readable commitments rather than a shuffled list:

- every floor presents at least two consequential route choices before its Boss;
- the chosen path contains six to nine actionable rooms, including the Boss and excluding the zero-cost floor-entry staging node;
- every floor has a distinct visible and mechanical rule, not only a palette swap;
- combat, economy, recovery, event, and reward opportunities are budgeted before room scenes load;
- the full route, room content channels, merchant inventory, and event outcome are reproducible from the run seed;
- Save and Replay persist stable IDs and authoritative snapshots, never live Node references or scene-tree order;
- map, shop, event, treasure, and rest interactions are complete controller-first UI flows;
- offline play remains complete and no online provider is required.

Run-duration tuning targets the Full Product Completion Design's `30-45 minute` successful run. Automated simulation may validate room, economy, and route budgets but is not human pacing or feel evidence.

## 3. Exact content authority

P14 definitions are registered specialized Content Pack v2 domains rather than extensions of the generic `content-entry-v2` row. Their exact category discriminators are:

```text
floor_definition
room_template
dungeon_event
merchant_definition
economy_profile
```

`ContentRegistry` dispatches those five categories to their domain parsers before generic-entry validation. All other categories continue through the frozen generic v2 contract. Specialized definitions still participate in pack integrity, pack-level ID uniqueness, candidate-pack atomic activation, dependency isolation, recursive localization validation, and cross-reference closure. The Base Pack exposes exactly `152` generic definitions plus `59` P14 specialized definitions across `15` content-manifest files.

### 3.1 Floor definitions

Each floor definition contains:

```text
category
id
schema_version
name_key
description_key
availability
order
route_room_min
route_room_max
graph_node_min
graph_node_max
allowed_room_types
required_room_budgets
environment_rule_id
encounter_profile_id
economy_profile_id
merchant_ids
event_ids
palette_id
music_cue_id
boss_room_template_id
boss_encounter_id
```

Exact floor budgets are:

| Floor | Actionable route rooms | Graph nodes | Required route guarantees | Floor rule |
|---|---:|---:|---|---|
| `floor_ruins_of_remnant` | 6 | 9 | shop-or-treasure, event, rest, Boss | `rule_crumbling_ground` |
| `floor_void_forest` | 7 | 10 | shop-or-treasure, event, rest, Boss | `rule_void_spores` |
| `floor_time_rift` | 8 | 12 | shop-or-treasure, two event opportunities, rest, Boss | `rule_temporal_distortion` |
| `floor_plane_forge` | 9 | 14 | shop, treasure, event, rest, Boss | `rule_forge_vents` |
| `floor_throne_of_void` | 7 | 9 | shop-or-treasure, event, no rest, Boss | `rule_collapsing_plane` |

`graph_node_min` and `graph_node_max` count the entry node and every mutually exclusive branch node. The actionable route count measures only rooms the player enters. The generator may add branch alternatives but may not lengthen the selected route outside the table.

The floor list API is `get_floor_definitions(availability)` and orders rows by the authoritative `order` field; generic category lookup order is not floor order. Until P15 installs real encounter catalogs, floor references use this exact P14 adapter taxonomy:

```text
encounter_profile_ruins_adapter_v1
encounter_profile_forest_adapter_v1
encounter_profile_rift_adapter_v1
encounter_profile_forge_adapter_v1
encounter_profile_throne_adapter_v1

boss_encounter_ruin_king_adapter_v1
boss_encounter_forest_heart_adapter_v1
boss_encounter_time_sovereign_adapter_v1
boss_encounter_forge_colossus_adapter_v1
boss_encounter_void_throne_adapter_v1
```

P14 validates these as closed adapter IDs. P15 replaces their implementation behind the stable references; P14 does not claim the final enemy or Boss behavior definitions.

### 3.2 Exact room-template catalog

Every room template is a versioned content definition with a stable scene path, floor eligibility, door anchors, camera bounds, spawn anchors, interaction anchors, supported environment rules, accessibility-safe hazard zones, and thumbnail/icon references. Launch room scenes live under `res://data/content_packs/base/assets/rooms/launch/` and are declared in the Base Pack `asset_manifest` with SHA-256 integrity entries when P14D authors them. P14A validates the closed path prefix and `.tscn` suffix without claiming that the not-yet-authored scenes already exist.

| Category | Exact template IDs |
|---|---|
| Combat | `room_combat_pillared_hall`, `room_combat_split_chambers`, `room_combat_open_field`, `room_combat_l_corner`, `room_combat_crossroads`, `room_combat_high_ground`, `room_combat_void_grove`, `room_combat_ring`, `room_combat_bridge`, `room_combat_clockwork` |
| Elite | `room_elite_arena`, `room_elite_guard_corridor`, `room_elite_altar_defense`, `room_elite_trap_arena`, `room_elite_twin_hall` |
| Treasure | `room_treasure_vault`, `room_treasure_wishing_pool`, `room_treasure_chronovault` |
| Shop | `room_shop_wayfarer_tent`, `room_shop_chrono_emporium` |
| Event | `room_event_shrine`, `room_event_crossroads`, `room_event_mirror_hall` |
| Boss room | `room_boss_ruin_king`, `room_boss_forest_heart`, `room_boss_time_sovereign`, `room_boss_forge_colossus`, `room_boss_void_throne` |
| Rest | `room_rest_campfire`, `room_rest_sanctuary` |

These thirty identities are exact. A floor-specific visual variant is selected through floor palette and environment-rule data; it does not create an uncounted room-template identity.

### 3.3 Exact event catalog

Regular events:

```text
event_chronal_altar
event_trapped_traveler
event_cursed_pool
event_smiths_legacy
event_memory_mirror
event_planar_merchant
event_void_rift
event_sleeping_guardian
event_twisted_well
event_soul_contract
event_time_paradox
event_sacrificial_altar
event_lost_journal
event_rift_garden
event_final_choice
```

Special events:

```text
event_void_whispers
event_perfect_rewind
event_old_reunion
```

Every event has exact availability, floor bounds, weight, repeat policy, trigger predicate ID, localized prompt, two or three options, typed requirements, typed consequences, outcome visibility policy, and a deterministic outcome channel. Content cannot contain script paths, Callables, method names, arbitrary nested executable payloads, or non-scalar operation arguments.

The closed repeat policies are `once_per_run`, `once_per_floor`, and `repeatable`. The closed trigger predicates are `always`, `low_health`, `has_curse`, `no_curse`, `rich`, `poor`, `perfect_rewind_available`, and `old_reunion_eligible`. Outcome visibility is exactly `preview_exact`, `preview_category`, or `hidden_until_commit`.

Requirement operations are closed to:

```text
resource_min
health_min
health_max_ratio
gold_min
has_reward_tag
lacks_curse
narrative_flag
floor_index_min
```

Consequence operations are closed to:

```text
resource_delta
health_delta
reward_draft
curse_add
curse_remove
temporary_modifier
map_reveal
encounter_start
route_skip
narrative_flag
```

### 3.4 Merchant and economy catalog

Exact merchant identities:

```text
merchant_wayfarer
merchant_chronomancer
merchant_forgekeeper
merchant_void_broker
merchant_echo_archivist
```

The two shop-room scenes are presentation shells. A merchant identity controls inventory rules, copy, portrait/pixel proxy, services, accepted costs, and floor availability. Multiple merchants can use the same shell without becoming duplicate room templates.

`launch_economy_v1` is the single P14 economy profile. It defines floor income budgets, base prices, rarity multipliers, floor multipliers, reroll surcharge, sell ratio, curse-cleanse cost, healing cost, gold cap, overflow decay, pity bounds, and deterministic inventory sizes. Gold is run-local and is lost on run termination. Meta currencies remain outside P14.

## 4. Deterministic FloorPlan

`FloorPlan` is pure data. It contains:

```text
schema_version
generator_version
run_seed
floor_id
floor_index
entry_node_id
boss_node_id
current_node_id
nodes
edges
selected_edge_ids
visited_node_ids
abandoned_node_ids
generation_digest
```

Each node contains stable IDs only: node ID, layer, room type, template ID, encounter/event/merchant reference, reward policy, seed-channel suffix, and revealed/visited/cleared flags. Each directed edge contains source, destination, choice order, lock state, and localized route-summary facts.

Generation rules:

1. Use `SeedService` channel `floor_plan_v1:<floor_id>` and never global RNG.
2. Create one entry node and one terminal Boss node.
3. Build a layered directed acyclic graph. Edges move exactly one layer forward; no backtracking or cycles are legal.
4. Every entry-to-Boss path has the exact actionable length for the floor.
5. Generate two or three choices at branch layers and merge branches before the next mandatory gate.
6. Enforce route budgets before selecting templates. No valid path may contain more than three consecutive combat-or-elite rooms.
7. Floors one through four place one rest room two actionable rooms before the Boss on every valid path. Floor five rejects rest nodes.
8. Every valid path exposes at least one event opportunity and at least one shop-or-treasure opportunity. Floor three exposes two event opportunities; floor four exposes both shop and treasure.
9. Select room templates without immediate repetition and with floor/environment compatibility.
10. Validate all nodes, edges, references, route budgets, reachability, and digests before the plan becomes authoritative. Generation failure is fail-closed and reports the seed and violated invariant.

Selecting an edge is an authoritative transaction. It marks exactly one outgoing edge selected, abandons sibling subgraphs that can no longer be reached, advances the current node, increments revision, and publishes one typed route-selection fact after commit. Repeated or stale selection is rejected without state change.

## 5. Scene streaming and room lifecycle

`RoomSceneHost` owns one active room scene and one staged room scene. It resolves only scene paths validated by the ContentRegistry. The successful transition order is:

```text
resolve authoritative target node
-> load PackedScene
-> instantiate under a detached staging root
-> validate RoomSceneContract and required anchors
-> bind floor palette, environment rule, encounter/interaction authority
-> atomically attach staged scene and activate camera bounds
-> retire the previous scene
-> publish room-entered fact exactly once
```

If loading, validation, binding, or activation fails, the previous room and authoritative node remain intact. No partially loaded room publishes lifecycle facts. Room nodes never mutate RunState directly.

`RoomRuntime` gains room-type handlers:

- combat and elite delegate to EncounterRunner;
- treasure delegates to TreasureRuntime and completes after one authoritative choice;
- shop delegates to MerchantRuntime and completes when the player leaves;
- event delegates to EventRuntime and completes after its committed outcome or encounter handoff;
- rest delegates to RestRuntime and completes after rest/upgrade selection;
- Boss room delegates to the P15 encounter ID and preserves the current compatibility Boss adapter until P15 replaces it.

## 6. Run lifecycle, Save, and Replay

Launch RunState owns:

```text
current_floor_index
floor_plan
completed_floor_ids
run_economy
seen_event_ids
merchant_state
floor_rule_state
```

The M1 five-room fields remain readable through a compatibility adapter and are not reinterpreted as a Launch FloorPlan. P14 introduces an explicit Save migration from schema v2 to the next schema. The migration adds empty P14 run fields only when no active Launch run exists; an older active Launch run without a FloorPlan cannot be invented and fails closed with a player-facing recovery path.

Save snapshots include the complete authoritative FloorPlan, selected/visited/abandoned nodes, current floor, economy ledger, merchant purchase/reroll state, seen events, pending event/shop transaction, floor-rule state, and content fingerprint. Load validates every stable reference against the current pack before scene instantiation.

Replay records route selections, room entry/clear facts, economy transactions, merchant inventory/purchases, event options/outcomes, rest choices, floor transitions, and floor-rule state. Replays seal generator version and content fingerprint. Unknown generators, changed room definitions, invalid route prefixes, changed event consequences, or economy-ledger drift fail closed.

## 7. Floor rules and presentation

Each floor rule is deterministic, bounded, telegraphed, and independently suppressible by reduced-motion/flash settings without removing gameplay information:

| Rule | Mechanical contract | Presentation contract |
|---|---|---|
| `rule_crumbling_ground` | bounded marked zones become unsafe after a fixed warning and recover after a fixed duration | crack overlay, outline, subtitle cue, low-frequency warning sound |
| `rule_void_spores` | bounded zones cycle inactive/warning/active and apply a capped damage or slow effect | purple pixel fog, high-contrast boundary, subtitle cue |
| `rule_temporal_distortion` | deterministic zones modify movement/time costs within capped ratios | blue-white scanline, clock cue, reduced-motion static alternative |
| `rule_forge_vents` | fixed vents warn, activate, and cool down on a room seed schedule | red prelight, steam proxy, impact sound and controller rumble budget |
| `rule_collapsing_plane` | predeclared zones lock after warning; the playable safe area never becomes invalid | black-white fracture telegraph, edge outline, no surprise instant death |

P14 hazards use Player/World payload authorities and typed damage or modifier facts. They do not bypass HealthComponent, time authority, invulnerability, accessibility settings, or Replay.

## 8. Economy, merchants, events, treasure, and rest

`RunEconomyState` is the sole gold and shop-ledger writer. Every transaction follows prepare, reserve, commit, publish ordering and includes a monotonic transaction ID. Negative balances, duplicate purchase IDs, stale inventories, repeated event options, and reroll replay are rejected atomically.

Launch economy targets retain the original directional model while fitting the six-to-nine-room floors:

| Floor | Target earned gold | Target spend | Post-floor target remainder |
|---|---:|---:|---:|
| 1 | 140-220 | 100-180 | 20-80 |
| 2 | 180-280 | 150-240 | 20-90 |
| 3 | 240-380 | 210-340 | 20-110 |
| 4 | 300-460 | 270-420 | 20-120 |
| 5 | 280-430 | 250-400 | 0-100 |

These are simulation bands, not guaranteed payouts. Prices use floor and rarity multipliers, rerolls increase monotonically, and one floor cannot guarantee enough currency to buy every premium offer. Floor transitions apply the profile's gold cap and overflow decay deterministically.

Merchant inventories contain stable offer IDs and are generated once per merchant node. Re-entering or loading never rerolls inventory. Purchased offers remain visibly sold. Optional services such as healing, curse cleanse, reroll, weapon upgrade, health trade, or route reveal use typed handlers and expose exact costs before confirmation.

Event options are committed once. Random outcomes are resolved from `event_outcome_v1:<event_id>:<node_id>` and stored, so UI reopen, Save load, and Replay never reroll. Combat outcomes reserve the event resolution, run the encounter, then commit the consequence exactly once on success or the defined failure path.

Treasure rooms present one deterministic reward interaction. Rest rooms present recovery plus one bounded upgrade/service choice. Declining or leaving preserves authoritative state according to the room definition; no interaction silently grants a fallback reward.

## 9. Player-facing UI

P14 adds native views backed by strict ViewState contracts:

- route map: revealed nodes, current node, selected/abandoned paths, route summaries, floor identity, and Boss distance;
- route choice: two or three controller-focusable destinations with room-type icon, known cost/risk, and hold-to-confirm only where accessibility policy requires it;
- shop: merchant identity, gold, deterministic inventory, sold state, exact cost, compatibility, effect summary, reroll, and leave flow;
- event: localized narrative prompt, requirements, visible/hidden outcome policy, disabled-reason text, confirm/back focus, and result state;
- treasure/rest: choice, comparison, replacement warning, recovery/upgrade result, and leave flow;
- floor transition: floor title, rule explanation, accessible cue summary, and next-floor confirmation.

Stable IDs never appear as player-facing fallback text. All flows work at `640 x 360`, `1280 x 720`, `1920 x 1080`, ultrawide safe framing, keyboard/mouse, and controller. Reduced motion, hit flash, screen shake, subtitle, contrast, and rumble settings apply to room hazards and transitions.

## 10. Verification gate

P14 is locally complete only when all of the following pass:

- exact five floor IDs and exact `10 / 5 / 3 / 2 / 3 / 5 / 2` room-template split;
- all thirty scenes instantiate, satisfy RoomSceneContract, fit the supported viewport, and expose required anchors;
- exact fifteen regular events, three special events, five merchants, and one economy profile validate and localize;
- every canonical seed produces a valid deterministic FloorPlan with byte-identical repeated output;
- all entry-to-Boss paths satisfy actionable room count, route budgets, reachability, no-cycle, no-overlong-combat, rest, event, and economy invariants;
- stale/duplicate route, purchase, event, treasure, rest, and floor-transition commands are atomic and publish no facts;
- room streaming rollback preserves the previous room and authority under load, contract, bind, and activation failures;
- all five floor rules pass warning, activation, cleanup, damage/modifier authority, accessibility, Save, and Replay tests;
- economy simulation remains within approved bands without negative balances, duplicate rewards, free rerolls, or guaranteed all-buy paths;
- M1 five-room behavior and P13B reward/draft compatibility remain green;
- Save migration, corruption recovery, FloorPlan round-trip, Replay divergence, controller-only flows, visual QA, 150-loadout smoke, and full repository validation pass;
- only registered warnings remain.

Formal M1 remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`. P14 simulation is synthetic and cannot certify pacing, exploration satisfaction, shop comprehension, or perceived fairness. Line coverage, installed export templates, distributable startup, signing, remote push, store configuration, and publication remain honest environment or external boundaries.

## 11. Sequencing and handoff

P14 is implemented in eight focused slices:

```text
P14A content authority and schemas
P14B FloorPlan and deterministic generator
P14C RunState, lifecycle, Save, and Replay
P14D thirty streamed room scenes and five floor rules
P14E economy and five merchants
P14F fifteen regular plus three special events
P14G map, shop, event, treasure, rest, and transition UI
P14H simulation, visual QA, 150-loadout regression, and certification
```

P15 begins only after P14H certification and owns twenty-two Launch enemies, elite affixes, encounter composition depth, and five complete Boss behavior kits. P14 may use existing enemy/Boss adapters to exercise lifecycle paths, but its evidence must label those adapters honestly.
