# Plane Walker P16 Hub, Meta Progression, Tutorials, and Narrative

- Status: Approved / Current
- Document Role: Current P16 implementation specification under standing project authorization
- Authority Level: Hub/profile/narrative authority below the Full Product Completion Design
- Applies To: Three-district Hub, profile progression, settlement, forging, training, onboarding, NPC arcs, endings, Save, Replay, and offline certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/0_深度收敛与系统职责设计.md`, `docs/8.1_局外枢纽与死亡结算设计.md`, `docs/8.2_货币养成与天赋树设计.md`, `docs/8.4_锻造强化与新手教学设计.md`, `docs/2_世界观与叙事进度设计.md`
- Last Verified: 2026-10-04
- Implementation Status: Design and execution boundaries defined; P16 implementation and certification pending
- Exit Gate: All three streamed districts, nine functions, complete progression and narrative content, native controller flows, migration, and reproducible offline build pass

## 1. Decision and sequencing

Use small RefCounted authorities for profile progression, settlement, forging, narrative, and onboarding, with native streamed Godot district scenes as projections. Existing `GameState.persistent` fields remain compatibility inputs; scene nodes do not own currencies or story flags. The content pack remains the one authored source. Domain foundations can be implemented beside P15; activation in Main waits for isolated contracts and the current P14/P15 integration gate.

A single giant Hub scene would couple scene lifetime to profile ownership. Independent NPC scripts that directly write GameState would bypass settlement idempotence and Save rollback. The selected streamed districts share one profile authority and revision-checked commands, following the existing Facade/panel separation.

P16 includes first-run story, five floor arcs and Boss resolutions, eight NPC relationship arcs, ten narrative artifacts, twenty-one environmental records, three hidden storylines, four ordinary endings and one hidden ending, the legacy forty-two-node Meta tree reconciled below, five-weapon forging, proficiency, training, ten onboarding lessons and fifteen contextual hints. Replay, modes, rankings, cosmetics, and content-pack gateways expose their available local providers in the Rift district; their later milestones retain ownership of unavailable Expansion capability implementations.

## 2. Canonical identities and reconciliations

Playable IDs remain `wanderer`, `time_guardian`, `void_walker`, `primordial_knight`, `time_lord`; weapon IDs remain `sword`, `bow`, `gun`, `staff`, `gauntlets`. Old Ash Ranger/Forge Adept/Void Chanter/Chrono Walker names become NPC history or archived flavor, never additional playable definitions. Old hammer rewards become forge/primordial-knight cosmetics or gauntlets variants. Neither Meta nor forging adds a third time slot, a new active character slot, weapon switching, or another combat ability.

P15 Boss IDs remain `ruin_king`, `forest_heart`, `time_sovereign`, `forge_colossus`, `void_throne`. Older Aurelian/Selene/Chronos/Ignis/Void Incarnate lore is displayed as historic aliases; narrative receipts use canonical Boss/floor IDs.

Meta single-stat totals are at most 5%, Meta direct combat benefit is at most 15%, and combined permanent benefit is at most 30%. Raw legacy +30% HP, +20% attack speed, per-floor revival, unconditional time/telegraph access gates, and +25% forging plus unbounded enchants are superseded. Accessibility and readable hostile warnings are available from a fresh profile. Every spent node keeps its stable legacy ID, authored cost, and revised useful behavior. `P-04` requires `P-01` and `L-09`, correcting the nonexistent `F-09`. Sum costs from the authored JSON rather than copying contradictory legacy totals.

## 3. Hub districts and functions

| District | Function IDs | Complete native interactions |
|---|---|---|
| `hub_council` | `council`, `archive`, `gateway` | NPC/mission journal and faction choices; lore/item/enemy archive; Launch loadout, difficulty, accessibility and tutorial recall |
| `hub_craft` | `training`, `forge`, `meditation` | Free legal loadout/Boss drills; weapon progression/enchantment inspection and transactions; Meta tree, character selection, 32-entry build library |
| `hub_rift` | `merchant`, `gallery`, `mirror` | Shard/imprint exchange and deterministic offline stock; owned cosmetics/endings collection; local replay/challenge providers and content-pack status |

One district is loaded at a time. Arrival points and interactables are data-defined and reachable with movement or controller focus; a compact destination selector is an equivalent accessible route. Travel preserves Player loadout, profile authority, camera/accessibility settings, and focused destination. Hub repairs have four visual stages driven by completed canonical milestones, not wall-clock time. No combat permanent reward can be farmed from scene reload or repeat dialogue. Returning from death/victory opens the settlement view before normal NPC interactions. Run launch remains accessible within three native commands from an unlocked Hub arrival.

Scene visuals use pixel raster tiles/sprites, the established palette families and integer scaling; NPCs and destinations have identifiable silhouettes. UI uses existing native focus/localization/safe-area helpers. All profile transactions show cost, current balance, prerequisite reasons, and final effect before submission; duplicate retired buttons cannot resubmit.

## 4. Profile state, transactions, and settlement

`MetaProfileState` is a strict schema-1 nested `meta_profile_state` payload, containing revision, currencies, sorted unlock IDs, proficiency, forging, NPC affinity, faction standing, narrative flags/records, tutorial progress, build library, repair stage, launch sequence, active launch receipt, and last settlement receipt. Every nested object has exact fields, bounded numeric values, stable IDs, and duplicate-free lists. Snapshot/restore is atomic and defensively copied. Unknown content references fail without mutating state.

Existing top-level `chronos_shards`, `existential_imprints`, `unlocked_nodes`, `discovered_items`, `unlocked_characters`, `unlocked_weapons`, `weapon_proficiency`, `npc_affinity`, `unlocked_achievements`, and `cosmetics` remain readable mirrors produced from the authority. A migration from v3 captures them once; contradictory mirror/nested values are rejected. Fresh profiles own Wanderer, Sword, Bow, and the full four time abilities; the six legal time pairs remain selectable. Progression unlocks characters/weapons through authenticated floor/quest facts without deleting existing legacy unlocks. A separate complete sandbox loadout remains available for training and formal 150-loadout verification.

All domain command results use `{ok, code, context}`. Commands validate expected profile revision, authored cost/prerequisites, command-specific bounds, and source receipt. A successful prepared candidate is written through SaveService as one profile envelope before becoming the live state; a failed write leaves authority and projection unchanged. A duplicate or stale command cannot spend twice. No network service participates in core settlement or purchase.

Launch creates a persisted monotonic profile run sequence and immutable launch receipt before entering the dungeon. Settlement accepts only the matching terminal RunState and authenticated room/Boss/material/narrative facts for that receipt. The profile persists the last completed sequence with the settlement result; replaying an old terminal result cannot mint currency. A terminal Save with an uncommitted settlement retries safely after restart. Abandoning a run records its launch sequence without granting a death guarantee. Legacy terminal summaries without a launch receipt import statistics only.

Ordinary settlement awards 3 guarantee shards only for a genuine played death, `5 * floor_number` per newly completed floor, `15 + 5 * floor_number` per canonical Boss resolution, and 10 for full Launch completion. Material drops add only authenticated unique receipts; summons/support actors never create separate currency. Difficulty multiplies earned shards by normal 1, hard 1.5, nightmare 2.5, rounded down once at settlement. First canonical Boss resolution grants two imprints once per profile. Gold is discarded. Soul reserve carries floor(remaining soul * 0.30/0.50/0.70) according to W-07/W-08 and is spent on the next run's authored soul service; Hub reload cannot increase it. Statistics count one finished run per committed settlement. This exact formula supersedes contradictory legacy example totals.

## 5. Forty-two Meta nodes

Costs and prerequisite IDs below are complete. All purchases are one-time; additive values denote cumulative branch totals. Information and option effects affect projected choices, never secret combat rolls. Permanent effects are frozen into a `MetaRunProjection` at run launch, authenticated in Save/Replay, and reapplied exactly once before the Player run-start reward baseline is captured.

| ID | Cost | Prerequisites | Revised effect |
|---|---:|---|---|
| W-01 | 5 | none | Max HP +2% |
| W-02 | 10 | W-01 | Max HP +1% (3% total) |
| W-03 | 20 | W-02 | Max HP +2% (5% total) |
| W-04 | 8 | W-01 | Floor entrance recovery +2% max HP, once per entrance |
| W-05 | 15 | W-04 | Void incoming damage -2% |
| W-06 | 30 | W-03 | One optional safe training reset and death analysis per Hub visit; no live revival |
| W-07 | 10 | none | Soul reserve retention 50% |
| W-08 | 20 | W-07 | Soul reserve retention 70% |
| W-09 | 5 | W-05 | Hub rest recovers health without currency |
| W-10 | 25 | W-06 | Deterministic next-room content preview |
| C-01 | 5 | none | Attack +2% |
| C-02 | 12 | C-01 | Attack +1% (3% total) |
| C-03 | 25 | C-02 | Three pre-run archetype shortlist presets |
| C-04 | 8 | none | Attack speed +1% |
| C-05 | 15 | C-04 | Attack speed +1% (2% total) |
| C-06 | 20 | C-04 | Dedicated dodge/parry timing drill |
| C-07 | 15 | C-05 | Archived hostile move timing comparison; warnings remain always available |
| C-08 | 50 | C-03,C-06 | Advanced complete Boss drill sequences |
| L-01 | 5 | none | Ruins basic rune interpretations |
| L-02 | 10 | L-01 | Complete Ruins and basic Rift interpretations |
| L-03 | 20 | L-02 | Complete authored rune interpretations; no random permanent lockout |
| L-04 | 8 | L-01 | Next-room hostile-role preview |
| L-05 | 12 | L-02 | Rift narrative landmark hints |
| L-06 | 18 | L-03 | Floor-rule safety annotations |
| L-07 | 3 | none | Full cross-linked collection archive; collected records remain readable earlier |
| L-08 | 10 | L-07 | Two additional saved build presets; run inventory caps unchanged |
| L-09 | 12 | L-08 | Hub merchant shard prices -10%, floored with minimum one |
| L-10 | 40 + 5 imprints | L-06,L-09 | Complete room-content preview at floor entrance |
| F-01 | 5 | none | Five-weapon forging |
| F-02 | 10 | F-01 | First enchantment selection |
| F-03 | 20 | F-02 | Second enchantment selection |
| F-04 | 25 | F-02 | Void temper option preview and acquisition |
| F-05 | 12 | F-01 | Forge undo preview and saved weapon preference recall |
| F-06 | 30 | F-03,F-05 | Enchantment comparison and craft recipe library |
| F-07 | 5 | none | Base recovery service recipe shortlist |
| F-08 | 15 | F-07 | Advanced recovery/void-safety service shortlist |
| P-01 | 3 | none | Council missions |
| P-02 | 8 | P-01,L-01 | Phia's first-floor narrative/rune guidance |
| P-03 | 15 | P-01 | Character-specific advanced drills |
| P-04 | 12 | P-01,L-09 | Three extra Hub merchant options, one gift every five committed runs |
| P-05 | 25 | P-03 | One NPC narrative companion; information/dialogue only |
| P-06 | 40 | P-05 | Two NPC narrative companions |

## 6. Forge, proficiency, and training

Each canonical weapon has forge levels 0-5 costing 5/10/20/35/50 shards and gaining +1% attack per level, at most +5%. Acquisition is deterministic, succeeds once, and cannot delete a weapon. The old paid retry/failure/level-loss loop is superseded. Proficiency has five experience thresholds 0/100/300/700/1500 and unlocks drills, cosmetic variants, and preview detail, with no additional damage multiplier.

The fifteen existing enchant IDs EN-01 through EN-15 remain authored options. P16 treats them as named pre-run reward preferences and training demonstrations using current launch combat hooks, not free permanent proc damage. Two equipped preferences select eligible archetype/reward preview emphasis, with no extra inventory slot, item generation, weighted guarantee, or new run effect. Fire/ice/lightning preferences are mutually exclusive; time/void preferences are mutually exclusive; EN-14 unlock costs five imprints, while EN-15 represents build-transition guidance without adding live weapon switching. Void temper changes presentation and preference eligibility, costs 30 shards or three imprints, and grants no uncapped combat multiplier. This preserves forge identity while keeping Launch build power in the run reward system.

Training uses real configured Player weapon/time/character runtimes and reusable P15 Boss actions, with refill/reset and deterministic drill seeds. No practice death consumes an active launch receipt, adds run statistics, or grants settlement. Six legacy tasks T-01..T-06 are first-completion rewards only (3/5/5/8/15/20 shards); native action receipts certify objectives. Timed/combination exercises can be replayed without reward. The production loadout selector enforces unlocks; training provides sandbox access to every launch loadout.

## 7. Narrative content and evaluation

The eight stable NPC IDs are `odysseus`, `elara`, `sibyl`, `hermes`, `phia`, `morpheus`, `nemesis`, `vera`. Affinity is an integer 0-100, with depth thresholds 20/40/60/80/100. Each has introduction, first death, five floor/Boss reactions, five depth conversations, and an authored resolution. A consumed dialogue choice grants affinity/flags once per source; repeat reads do not farm reputation. Four factions are `council`, `void_cult`, `merchants`, `shardborn`, with standing -100..100 and choices that change only explicitly authored flags/standing.

Artifact IDs are `wardens_badge`, `primordial_child_drawing`, `void_eroded_saber`, `loom_thread`, `forgekeeper_mask`, `stonekeeper_memory`, `void_baptism_flask`, `amplification_core_shard`, `walker_demise_letter`, `unfinished_weaving`. Environment record IDs preserve E1-1..E1-5 and E2-1..E5-4, giving exactly twenty-one. The five floor arcs retain the themes grief, coexistence, causal truth, creation/repair, and final choice; authored interactions and P15 Boss receipts unlock records instead of string searches in UI text. The ten artifacts are separate from the certified fifty-item P13B Launch combat pool and cannot consume reward slots.

Hidden storylines `primordial_whispers`, `walkers_song`, `voice_of_void` each have the five authored steps from the legacy narrative, explicit prerequisites, and localized journal text. All cumulative progress is stored as facts and integer gameplay frames. Void exposure excludes menu/pause/Hub time. Nemesis has five narrative encounters with spare/attack choices; these are controlled event encounters and do not introduce another floor Boss. Vera has five optional conversations costing five temporary maximum HP each; costs apply atomically to the active run, cannot kill a Player with invalid capacity, cannot repeat after reload, and reset at run end. Permanent affinity can reach 80 through the fifth conversation; inability to pay leaves that step available in a later run.

| Ending ID | Final choice | Exact eligibility after canonical Void Throne victory |
|---|---|---|
| `return_of_order` | Reassemble | Elara affinity >=80; five unique collected heart fragments; Sibyl depth sequence incomplete |
| `embrace_of_void` | Accept | Sibyl affinity >=80; all five Nemesis encounters spared; void-understanding dialogue flag |
| `balance_of_ashes` | Coexist | Elara and Sibyl affinity >=60; three heart fragments; explicit balance flag from at least three different key choices |
| `shattered_freedom` | Release | Always available fallback after victory |
| `echo_of_primordial` | Ask | All three hidden lines complete; all eight NPC affinities >=80; all ten artifacts and twenty-one environmental records; all five Vera conversations |

Every eligible choice is visible without selecting a hidden default; locked choices show missing prerequisites without spoilers. A victory remains recorded while the final choice is pending; it does not pay settlement twice. Ending choice and credits completion are distinct durable facts, so interrupted/skipped credits return safely to Hub. All five endings remain replayable in the gallery after discovery. Main scenes/subtitles, endpoint choices, ending text, and credits are complete in Chinese/English; voiced audio is optional but dialogue sound/music/subtitle support is mandatory.

## 8. Onboarding and accessibility

Ten lessons cover movement/dodge, weapon basics, time use, treasure/reward choice, merchant, Boss warnings/conversion, build inspection, blessing/curse events, Hub/forge, and alternative loadouts. Fifteen context hints retain the legacy topics but use actual InputMap/controller bindings and implemented services; obsolete enhancement-failure and hidden-door instructions are replaced with forge preview and route discovery. Lessons observe semantic action receipts, not key names, and support replay, skip, suppression, locale changes, and controller input.

Three optional guided runs have explicit protection recorded in the launch projection: incoming damage multipliers 0.80/0.90/1.0, warning scales 1.25/1.10/1.0. They exclude ranked/challenge eligibility and show their assisted status in results. Normal mode remains available immediately; skipping instruction neither spends currency nor silently enables assistance. Focus, 1.0-1.5 text scale, safe area, subtitles, high-contrast markers, and reduced motion work in all nine functions and every ending. Settings are stored independently from profile progression.

## 9. Save, Replay, and certification

P16 adds strict optional nested state to the existing profile only through a declared v3-to-v4 envelope migration. Settings schema remains unchanged. Domain schema changes are independently versioned. Authentication happens before migration, raw source Save remains recoverable, caller input is unchanged, and unknown newer schemas fail closed. Migrated legacy currency, unlocks, proficiency, affinity, cosmetics, statistics, and active runs are preserved; legacy names map only through an explicit validated ID table. In-flight Launch snapshots lacking a MetaRunProjection receive an empty no-benefit projection, not the profile's later unlocks.

Player/Run Replay preserves immutable launch meta effects and narrative external facts with real source receipts. Hub purchases and real-profile settlement never execute during replay playback; replay simulations use an isolated profile. All 150 loadouts test default and maximum allowed permanent projection. Tests prove semantic equivalence between live, physical JSON restored, and replayed run projections.

Certification requires domain malformed/stale/duplicate/rollback tests, exact content/prerequisite/localization validation, fresh/legacy/corrupt/terminal Save tests, settlement crash/retry tests, all five endings including deliberately unavailable cases, three guided runs, native return-to-Hub and relaunch, all nine functions at 640x360/1280x720/1920x1080/3440x1440 in Chinese/English with controller and mouse, nonblank raster assets, representative Hub load/performance checks, and a clean offline import/export/launch. Human playtest evidence remains a separate real-world boundary. Documentation/design completion does not count as implemented P16 content.
