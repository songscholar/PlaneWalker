# Plane Walker P15 Launch Enemies, Elite Affixes, and Five Boss Kits

- Status: Approved / Current
- Document Role: Current P15 specification
- Authority Level: Launch hostile-content and behavior authority below the Full Product Completion Design
- Applies To: Twenty-two Launch enemy definitions, ten elite affixes, bounded summons, five floor Boss kits, encounter composition, fixed-frame hostile execution, hostile presentation, Save, Replay, simulations, and local certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/3.6_敌人系统设计.md`, `docs/3.7_Boss设计.md`, `docs/contracts/content-pack-v2.md`, `docs/contracts/save-service-v3.md`
- Supersedes: The Unity/C# implementation proposals, ambiguous enemy counts, untelegraphed hostile effects, blanket time immunity, unavoidable enrage attacks, and obsolete independent reward payouts in the original enemy/Boss references; their identities, tactical roles, named moves, and narrative intentions remain inputs
- Last Verified: 2026-10-04
- Implementation Status: Isolated action and encounter domain foundations verified; native actors, authoritative hostile content, production integration, and P15 certification pending
- Exit Gate: Exact content counts, every authored hostile action and elite mechanism, production five-floor encounters, deterministic Save/Replay, all loadouts, accessibility/visual QA, and complete local validation pass with preserved M1 behavior

## 1. Decision and scope

P15 replaces P14's Launch encounter adapters with real authored enemy and Boss behavior. An enemy ID, a palette, or a numeric multiplier applied to the M1 chaser/shooter/tank is insufficient: each definition must execute the tactical mechanism specified here. Every Boss has its own phase progression, arena interaction, move selection, readable punishment window, and time conversion.

The selected architecture is a closed declarative action catalog with native Godot adapters and small domain runtimes. Per-species scene scripts would duplicate clocks, cleanup, and Replay logic; one generic M1 behavior with different IDs would fail the product scope. A shared action coordinator plus closed species/arena handlers preserves mechanical depth while allowing one deterministic transaction and one snapshot contract. Handlers are code shipped with the game, never expressions or arbitrary scripts loaded from content packs.

P14H certification is the implementation prerequisite. Design work may run alongside P14G/H, but activating P15 content waits for the P14 exit Gate. P15 includes all twenty-two Launch species and their elite moves, ten affixes, nine support/summon definitions, forty-eight primary Boss moves plus four explicit time responses, five encounter profiles, five Boss encounters, localized presentation assets, tests, and an offline build path. Boss Rush, difficult-mode variants, five additional Expansion species, Hub progression, narrative scenes, endings UI, and platform services retain their later full-program milestones. P15 publishes the facts and reusable Boss APIs those milestones consume.

### Count reconciliation

The original GDD's `27 = L1 x 4 + L2 x 6 + L3 x 6 + L4 x 6 + general 5` does not match the detailed enemy document, which contains `5 + 6 + 6 + 6 = 23` species. The approved completion authority requires exactly twenty-two Launch definitions and at least five additional Expansion enemies. P15 adopts `5 + 6 + 6 + 5 = 22`; `forge_spirit` retains its repair/shield/burning support kit in the first Expansion pack. This preserves the original species without inventing a Launch count exception. The Expansion milestone must deliver `forge_spirit` and at least four additional complete species. Summons and arena constructs do not inflate either ordinary/elite count.

## 2. Stable identities and compatibility

The following floor, room, and encounter references remain unchanged, including the historical `adapter_v1` spelling. Their implementations become real P15 definitions; the spelling is not permission to use compatibility behavior.

| Floor | Existing encounter profile | Existing Boss encounter | Existing Boss room | Boss definition / display identity |
|---|---|---|---|---|
| `floor_ruins_of_remnant` | `encounter_profile_ruins_adapter_v1` | `boss_encounter_ruin_king_adapter_v1` | `room_boss_ruin_king` | `ruin_king` / Guardian of the Ruins / 遗迹守护者 |
| `floor_void_forest` | `encounter_profile_forest_adapter_v1` | `boss_encounter_forest_heart_adapter_v1` | `room_boss_forest_heart` | `forest_heart` / Void Tree Matriarch / 虚空树母 |
| `floor_time_rift` | `encounter_profile_rift_adapter_v1` | `boss_encounter_time_sovereign_adapter_v1` | `room_boss_time_sovereign` | `time_sovereign` / Traitor of Time / 时之叛徒 |
| `floor_plane_forge` | `encounter_profile_forge_adapter_v1` | `boss_encounter_forge_colossus_adapter_v1` | `room_boss_forge_colossus` | `forge_colossus` / Forge Lord / 熔炉领主 |
| `floor_throne_of_void` | `encounter_profile_throne_adapter_v1` | `boss_encounter_void_throne_adapter_v1` | `room_boss_void_throne` | `void_throne` / King of the Void / 虚无之王 |

M1 retains `data/encounters/m1_encounters.json`, the five-room plan, chaser/shooter/tank, `overload_pulse`, Chrono Warden, their timing tables, and existing regression contracts. `EncounterCatalog` resolves known M1 references using that catalog; known Launch references resolve through ContentRegistry and a new Launch catalog. Unknown references fail closed. Once all Launch references pass production tests, `_launch_adapter_source` is removed from the Launch resolution path. No failure falls back to a Warden encounter.

The authority shares interfaces, not M1 clocks. Launch actors inherit reusable damage/control endpoints where practical but override `_physics_process` so `EnemyBase`'s delta-driven attack, AI, timer, and elemental advancement cannot also execute. M1 enemies and Warden continue their current path. No `Node` instance ID, absolute scene path, wall-clock timestamp, or global RNG state appears in a persisted hostile identity.

## 3. Content contract and module boundaries

Use ContentRegistry v2 and the Base Pack as the sole Launch content source. Add closed specialized categories `enemy_definition`, `boss_definition`, `elite_affix_definition`, `summon_definition`, and `launch_encounter_profile`. Each entry has `category`, `id`, `schema_version: 1`, `name_key`, `description_key`, `availability`, `tags`, `compatibility`, and `references`. Specialized parsers validate exact fields and types before registration. Enemies, Bosses, affixes, summons, encounter profiles, cues, arena recipes, scenes, and textures are referenced by stable IDs or validated pack-relative paths; dangling references reject pack activation.

Required content files under `data/content_packs/base/content/` are `enemies.json`, `bosses.json`, `elite_affixes.json`, `summons.json`, and `launch_encounters.json`. Add each to `pack.json.content_manifest`, all scenes/textures/audio to `asset_manifest`, and exact SHA-256 hashes to `integrity_hashes`. Extend the five corresponding Draft 2020-12 schemas, runtime parsers, Python schema suite, GDScript contract suite, localization CSV, and document governance in the same slices as their content. The pack loader already has a specialized-category dispatch; extend it without widening ordinary item/weapon/character schemas.

| Module | Responsibility |
|---|---|
| `EnemyDefinition`, `BossDefinition`, `EliteAffixDefinition`, `SummonDefinition`, `LaunchEncounterProfile` | Exact content normalization, canonical ID/count closure, action/handler/arena reference validation |
| `LaunchEncounterCatalog` | Resolves the ten existing floor/Boss encounter IDs, deterministic composition and spawn positions from registry definitions |
| `HostileActionContract`, `HostileActionCoordinator` | Pure 60 Hz warning/active/recovery/idle phases, committed geometry, hit schedule, cooldowns, monotonic generations, strict snapshots |
| `LaunchEnemyRuntime`, `LaunchBossRuntime`, `EliteAffixRuntime` | Pure species state, phase selection, bounded support behavior, nonterminal revival, arena state, conversion claims |
| `LaunchEncounterRuntime` | Owns room-scoped hostile roster, pending waves/spawns, payloads, reward/death claims, cleanup, and sorted frame batches |
| `HostileFrameBridge` | Optional participant in the Player fixed-frame transaction; coordinates prepare, effect commit, snapshot compensation, and publication |
| `LaunchHostileEffectAuthority` | Validates batches, applies HealthComponent damage/heal/modifiers, deterministic movement, bounded summons/constructs, and threat registration |
| `LaunchHostileActor`, `LaunchBossActor`, `LaunchHostilePayload` | Native scene adapters and existing public weapon/time endpoints; presentation projection from authoritative snapshots |
| `LaunchHostilePresentation` | Frame-bound raster animation, geometry projection, localized subtitles, sound/rumble, reduced-motion alternatives |
| `HostileReplaySeal` | Strict content/roster/action/payload/claim snapshots and digests; authorized atomic world restore |

These units use existing `SeedService`, `DamageInfo.from_plan`, `HostileTelegraphFact.create`, `HostileThreatRegistry`, `HealthComponent`, `ElementalStatusRuntime`, room lifecycle, and `ReplaySafeValue`. Motion routes use Godot `AStarGrid2D` over a validated 16 px collision grid; do not implement a second pathfinding engine. Domain positions are finite pixels quantized to `1 / 256` px; scene transforms project them. Presentation cannot alter geometry, cooldown, target selection, damage, or claims.

### Closed action record

An action contains exactly `id`, `handler_id`, `warning_frames`, `active_frames`, `recovery_frames`, `idle_frames`, `cooldown_frames`, `weight`, `max_consecutive`, `distance_min_px`, `distance_max_px`, `geometry`, `hit_schedule`, `parameters`, and `cue_id`. `hit_schedule` rows contain `offset_frame`, `hit_index`, `damage`, and `damage_type`. The listed handler parses its own exact parameter keys. Accepted handlers are `melee`, `charge`, `projectile_volley`, `zone`, `heal`, `shield`, `summon`, `blink`, `wall`, `link`, `portal`, `self_rewind`, `phase_transition`, `pull_zone`, and `arena_core`. Rejected/unsupported handlers never become inert successful actions.

Geometry is an ordered array of standard threat primitives; every primitive has a distinct generation allocated from its owner's monotonic generation floor. One source/generation key cannot register multiple shapes. A volley may share one generation and use unique hit indices only when it has one authoritative envelope; independently positioned shots/areas use separate generations. All geometry is fixed at commitment. Blink landing and follow-up strike have separate commitments. A moving payload has a finite swept envelope fixed at warning; its current shape moves within that envelope. New geometry is a new generation with a complete warning.

The current `ring` threat shape is treated as a filled circle by the registry. P15 does not use it for an annulus or promise a safe center. Cages/walls are destructible line segments with a declared gap; 180-degree sweeps are two supported cones. A cone uses the registry's widening-triangle definition, not a mismatched angular sector. Exact endpoints/half-widths define both collision and telegraph projection.

## 4. Frame, transaction, damage, and lifetime rules

Launch hostile gameplay uses `runtime_frame` from `Player.advance_action_frame`; accepted frames are exactly previous frame plus one. There is no fallback to `Engine.get_physics_frames()` in Launch. Duplicate, skipped, regressed, or post-terminal frames fail without mutation or emitted facts. Pausing and presentation changes do not advance domain state. `1 design unit = 16 px`; old spatial ranges convert by sixteen. Movement speeds are authored explicitly in px/sec below; old Unity speed values are not silently reused.

The Player already commits TimeManager, weapons, characters, world payloads, intents, and movement inside a fixed-frame transaction. Add an optional `HostileFrameBridge` participant after movement and before `_commit_fixed_frame_event_buffers`. The bridge prepares using the committed Player position, health and time-source observations, computes a stable-source-sorted hostile batch, prevalidates every effect and future roster change, commits with compensation snapshots, then joins frame publication. Player rejection restores the bridge, target health/modifiers/transforms, registry, roster and staged payloads before observable facts. A failed compensation freezes input and enters the existing typed integrity-failure path. A separate Host physics callback must never advance the same hostile frame.

Within an accepted frame: expire unscaled sources and status lifetimes; resolve Player damage already staged; determine any nonterminal life/phase transitions; advance existing hostile actions and payloads; collect new action decisions; reserve bounded summons/constructs; preflight the complete batch; commit health/state/geometry; publish exactly once. Same-frame target ties sort by stable source ID. Action selection uses an isolated seeded channel and an explicit decision index; retries/rollback never consume RNG permanently.

Warning covers `[commit_frame, commit_frame + warning_frames - 1]`; first active frame is `commit_frame + warning_frames`. `HostileTelegraphFact.active_from_frame` includes warning because existing character threat queries inspect forthcoming danger; damage occurs only at declared active hit offsets. The fact remains through active/recovery or its explicit payload lifetime. Time effects may extend the expiry of an unchanged fact via a narrowly scoped `extend_fact_through(source_id, generation, expected_through_frame, new_through_frame)` operation; origin/aim/radius/length cannot change and generation stays stable. M1 does not call this API. Registration/extension failure rejects the whole action transaction.

Minimum continuous warnings are 30 frames for floor-one enemies, 23 for later normal/elite attacks, 40 for floor-one Boss, 30 for Bosses two through four, and 25 for the final Boss. Every independent delayed explosion, spawn, teleport landing, arena collapse, and follow-up has its own warning or was fully included in a committed multi-hit schedule with geometry visible from the initial warning. Recovery is at least 15 frames for damaging normal/elite actions and at least 20 for damaging Boss actions. Faster enrage/affix schedules never reduce these floors. Multi-hit actions expose all hit times and directions before the first hit; no post-commit tracking.

Hostile damage uses the real Player `HealthComponent.resolve_and_apply_damage`, stable `run_id`, target ID, hostile source ID, attack generation, and hit index. It participates in sword defense, Character defense, invulnerability, accessibility assists, typed damage observations, and Replay verification. Every target can accept each hit identity at most once, including repeated overlap frames. Enemy-owned DOT/status ticks have distinct hit indices and finite tick counts. Slow stacks use the strongest source and movement floor `0.40`; hostile attacks do not modify player action duration or prevent time input. A root is represented by that bounded slow for at most 90 frames, retaining dodge/guard/time actions. A hostile pull is capped at 32 px/sec and cannot cross collision or reserved safety boundaries.

Support healing clamps to maximum HP, cannot target dead/finalized actors, and cannot reset revival/phase/claim counters. Each supporting actor can restore at most 40% of its own maximum HP to any one recipient per encounter. Multiple support sources share a recipient cap of 80% maximum HP per encounter. Regeneration affix has a separate total heal cap of 30% maximum HP. No support targets itself, a Boss, arena constructs, or another support-only actor; target ties use lowest HP ratio then stable ID. Shields never stack above 30% recipient maximum HP.

Room budgets are at most eight counted ordinary/elite bodies, eight summons, thirty-two hostile projectiles, twelve damaging zones, eight destructible constructs, three links, and one portal pair. Boss phases obey the same payload budgets; warning overlap is at most three damaging actions (four in the final Boss's third phase). Budget reservation occurs before publication. Full budgets delay an eligible spawn/action with its decision index retained; malformed references fail closed. Delayed deaths, explosions, split children, and revival sigils remain authoritative pending work, so `alive_count == 0` cannot clear a room prematurely. Boss terminal death cancels its owned nonreward summons and hazards before room completion.

Only final death calls `RoomRuntime.report_entity_died`. Chrono Guard and Eternal Hound use a narrow pre-publication lethal transition hook in HealthComponent; the default branch is unchanged for M1/Player. `prepare_hostile_lethal_transition` is observation-only; an authenticated commit atomically selects final death or an authored nonterminal state before `damaged`, `died`, and typed kill observations. Nonterminal Guard recovery and Hound dormancy keep their encounter token counted. The Hound's dormant state holds HP at 1, is nonattacking, and exposes one destructible sigil; the sigil is a construct rather than a second enemy or a reward source. Destroying it finalizes its parent; otherwise 300 unscaled frames later the Hound reforms at 50% HP with its once-only revival consumed. Gameplay Rewind never restores these counters, enemy HP, final deaths, drops, or arena rewards.

Each final counted death submits one authenticated defeat receipt. Existing room reward and P14 economy policies remain the gold/reward writers. P15 adds no per-node Gold mutation, old direct `150/220/300/400/600` Boss gold, random equipment loot, extra Launch pool IDs, or duplicated floor reward. Meta-material drop facts may be sealed for the later progression milestone, but have no live currency sink yet. Summons/illusions/split children yield no independent currency/reward or kill-loop proc; ordinary damage/weapon hit interactions still work.

## 5. Twenty-two enemy kits

IDs below are canonical; runtime kind equals the species ID. `HP / speed / threat` means base maximum HP, px/sec, and encounter budget cost. Damage values and cooldowns are authored baseline tuning inputs, not evidence of human-balanced play. `W/A/R/CD` means warning, active, recovery, and cooldown in 60 Hz frames. Each move ID is `<species_id>.<suffix>`. Unless specified, idle is 15 frames, weight is 10 for the first move and 6 for the second, and maximum consecutive use is one. Ranged actor projectiles have TTL 120 and maximum range 240 px; burst active frames schedule every listed hit independently. Elite adds the listed move to the entire ordinary kit.

| Floor / ID | HP / speed / threat | Base moves: suffix, W/A/R/CD, damage and geometry | Distinct state and elite move |
|---|---|---|---|
| 1 `shattered_sentinel` | 80 / 64 / 1 | `shield_sweep` 30/8/25/150, 12, paired cones at -45/+45 degrees, length 29 half-width 29 | Pursue then retreat 19 px over 48 frames; seeded staggered first attack. Elite `boulder_slam` 45/12/35/480, 24, target circle r40, knockback24 |
| 1 `corrosive_moth` | 35 / 96 / 1 | `corrosive_spit` 30/6/20/120, 8, line half-width5 length80, speed192 | Kite 56-80 px; impact pool r13 TTL120, 3 damage per60f; death pool warns30f before5 damage r16. Elite `corrosive_barrage` 35/18/25/360, three6-damage lanes, each committed, no tracking after launch |
| 1 `stone_shell_strider` | 120 / 72 / 2 | `shell_charge` 30/12/25/180, 15, line half-width8 length48; `bite` 30/5/20/120,10, cone24x12 | Post-hit shell120f gives damage multiplier0.30 without restarting on more hits; open30f multiplier1.30. Elite `shell_shock` 40/10/30/300,18, circle r40, only once per shell cycle |
| 1 `ruins_wraith` | 50 / 80 / 2 | `spirit_detonation` 60/6/20/0,20,circle r32, consumes actor after active | Cross internal obstacles, never outer room bounds; cumulative windup damage>=15 interrupts into30f stagger; final pre-active kill cancels explosion. Elite `spirit_split` 45/1/20/0 reserves two `mini_wraith` on death, no recursive split |
| 1 `rift_watcher` | 100 / 0 / 2 | `nourish` 30/1/20/60,5 heal in r96; `rift_pulse` 40/4/60/240,0,circle r48, slow0.70 for120f | Fixed support; nourish excludes self and obeys total cap; death gives recipients ATK0.80 for180f. Elite `rift_bind` 40/10/40/360,0,line half-width5 length64, bounded slow0.40 for90f |
| 2 `void_hunter` | 90 / 126 / 2 | `claw_pair` 23/16/20/72,8+8, cone24x12, offsets0/12; `backstab_dash` 28/6/25/240,22,line half-width6 length56 | Lateral approach, flank speed1.20, silhouette always visible; retreat32px. Elite `hunter_echo` 35/1/25/600 summons one `hunter_echo` for480f |
| 2 `void_archer` | 55 / 78 / 2 | `void_arrow` 25/4/20/150,16,line half-width3 length128,speed192; `arrow_fan` 40/8/25/360,8x3, lanes at -15/0/15 degrees | Kite80-128px with obstacle-aware retreat. Elite `piercing_arrow` 35/6/25/300,20,line half-width4 length160,speed240,pierces one construct/ally but no repeated target |
| 2 `bramble_mage` | 70 / 58 / 3 | `bramble_growth` 40/1/25/180,three r19 pools at committed target and +/-32px,TTL300,tick8/60f,slow0.60; `entangling_whip` 28/6/20/240,10,line half-width4 length64,slow0.40 for48f | Only caster immune to its own pool; allies can be hit. Elite `bramble_cage` 50/1/30/480,three HP30 line walls around48px square,32px permanent gap,TTL240 |
| 2 `void_spore` | 25 / 42 / 1 | `spore_burst` 30/6/20/0,12,circle r40; residual r24 zone TTL180,tick5/60f,slow0.80 | Chain depth<=5; every triggered child warns30f, no instant chain hit. Elite `spore_split` 30/1/20/0 reserves two `small_void_spore` once |
| 2 `forest_caller` | 130 / 58 / 4 | `void_call` 45/1/30/300,two `void_firefly`; `energy_bolt` 25/4/20/180,8,line half-width5 length96,speed128 | Retreat toward validated route, interrupts on stagger in summon warning; own summons retire on final death. Elite `great_call` 60/1/35/720,one `void_beetle` for1200f |
| 2 `shadow_lurker` | 75 / 98 / 3 | `shadow_ambush` 35/8/25/210,18,target circle r32; `surface_claw` 23/5/20/120,12,cone24x14 | Burrow max180f, moving high-contrast trail, ground damage multiplier0.50 rather than immunity, all weapons hit at marked landing. Elite `shadow_trap` 40/1/25/480,one visible r24 trap TTL360,slow0.40 for90f on contact |
| 3 `chrono_guard` | 180 / 70 / 3 | `chronal_slam` 30/8/25/150,20,cone32x16; `rift_slash` 35/10/30/300,28,line half-width10 length48,slow corridor TTL360 | First lethal hit enters90f nonattacking recovery, then54HP; revive flag consumed before publication, never reset by heal. Elite `time_lock` 45/10/30/480,15,circle r56,slow0.40 for90f, retains time/dodge input |
| 3 `rift_weaver` | 100 / 64 / 4 | `rift_make` 40/1/25/240,one r32 zone TTL600,slow0.60; `distortion_bolt` 25/6/20/180,12,line half-width5 length112,speed160 | Predict position<=30f, freeze target at warning; max3 zones, shifts warn30f and grant an opt-in portal instead of random Player teleport. Elite `rift_fusion` 50/1/35/720,consume own zones,one r64 zone TTL480,tick5/60f,slow0.40 |
| 3 `blink_striker` | 95 / 106 / 3 | `blink_cut` 35/6/25/120,22,landing then cone29x14; `rift_cross` 40/4/25/270,28,target circle r24 | Landing visible from warning,8f transit,25f strike warning after landing; Rift halves transit distance, Stop postpones landing. Elite `triple_blink` 50/70/35/480,15x3,three fixed landing/strike geometries at hit offsets0/33/66 and local landing offsets(0,0)/(0,32)/(0,-32); each subsequent strike follows8f transit and25f post-landing warning |
| 3 `rewind_priest` | 110 / 58 / 4 | `rewind_heal` 45/1/30/300,one recipient +30%maxHP in r80; `slow_bolt` 30/6/20/210,10,line half-width5 length80,speed128,slow0.60 for180f | Up to180f health history, never resurrects or changes kill ledger; history-derived heal stays under encounter cap. Elite `time_reverse` 60/1/35/900,one recipient heal up to remaining cap,ATK1.25 for300f |
| 3 `chrono_storm_elemental` | 150 / 78 / 4 | `time_storm` 40/1/30/300,two r24 zones inside r64,TTL180,tick10/60f; `timeflow_push` 25/8/25/180,15,line half-width12 length48,slow0.60 for120f | Fast1.25/slow0.60 zone pattern fixed by seed; swaps warn30f every90f; death pulse warns35f before slow0.70 for180f. Elite `time_stasis` 55/1/35/600,r56 fieldTTL120,slow0.40,enemy-only action freeze; Player keeps actions |
| 3 `eternal_hound` | 70 / 140 / 3 | `temporal_bite` 23/5/20/90,16,cone19x10 | Once-only300f dormant sigil then35HP; destroy HP12 sigil to finalize; no room clear/reward until final. Elite `time_hunt` 30/6/25/300,30,line half-width8 length40,hit heals up to20 within cap |
| 4 `forge_titan` | 350 / 56 / 4 | `forge_fist` 30/10/30/210,25,cone40x20; `ground_fissure` 40/12/35/360,30,line half-width16 length64,poolTTL180; `flame_breath` 50/30/30/480,tick15/60f,cone80x24 | Breath below50%; below30% overheat600f ATK1.25/speed1.15 then60f warned explosion40,r48; killed corpse explosion has independent60f warning and finite pool. Elite `plane_collapse` 60/20/40/720,40,circle r96 with validated escape route |
| 4 `void_web_weaver` | 120 / 70 / 5 | `void_web` 35/1/25/300,link two valid allies,HP15,TTL480; `thread_fan` 30/15/25/210,8x5,line lanes; `binding_thread` 35/8/25/300,14,line half-width3 length96,slow0.40 for90f | Three links max,ATK1.15/speed1.10 strongest-only; visual elevation gives no melee immunity; link collision warns35f. Elite `web_cage` 55/1/35/600,three HP25 line segments with32px gap,TTL360 |
| 4 `phase_ranger` | 85 / 84 / 3 | `phase_arrow` 25/4/20/120,22,line half-width4 length144,speed240; `void_arrow_rain` 40/30/30/360,10x6,independent r8 landing circles offsets0/5/10/15/20/25 | Every projectile visible for its entire damaging flight; shift max80px/CD180f,marked arrival,30f vulnerable recovery. Elite `phase_split` 35/1/25/600,two `ranger_echo` for600f,no recursive split |
| 4 `chaos_amalgam` | 200 / 98 / 5 | Red `rage_combo` 30/36/30/120,12x3,cone32x16,offset0/12/24; `flame_charge` 30/8/25/300,25,line19x64,poolTTL180. Blue `frost_wave` 30/10/25/180,15,circle r56,slow0.60; `ice_spikes` 40/8/30/300,20,three lines. Void `void_pull` 25/8/25/150,18,cone40x20; `void_pulse` 35/10/25/300,22,circle r64 | Red/blue/void240f cycle (150f below50%) and30f switch recovery; never switch a committed action. Elite `chaos_outburst` 55/15/35/600,35,circle r80,slow0.70/burn5 per60f for180f/knockback32 |
| 4 `plane_ripper` | 140 / 84 / 5 | `plane_rip` 50/1/35/480,one portal pair distance>=96px,TTL720; `rift_strike` 25/6/20/180,16,cone48x24 | Both teams use blue-white portals with12f per-actor transit cooldown; safe arrivals>=48px from Player; portal death collapse warns45f before20,r32. Elite `one_way_plane` 50/1/30/720,enemy-only red portals with shape icon and distinct cue |

Floor five draws from the verified floor-three/four rosters rather than adding undeclared species. Its profiles retain distinct cross-floor tactical combinations and the full payload/safety budgets.

### Summon definitions

The exact nine support IDs are `mini_wraith`, `small_void_spore`, `void_firefly`, `void_beetle`, `hunter_echo`, `ranger_echo`, `timeline_echo`, `void_sapling`, and `elite_mirror`. They reference a validated parent behavior subset and declare HP, damage ratio, lifetime, collision, and spawn warning. Wraith25HP/10 damage/TTL480; small spore12HP/6/TTL480; firefly20HP/6/TTL900; beetle80HP/18/TTL1200; hunter echo45HP/7/TTL480; ranger echo42HP/11/TTL600; timeline echo200HP/15/TTL1200; sapling60HP/15/TTL900; elite mirror20%parent base HP/50%damage/TTL480. All spawn warnings>=30f, damaging attack warnings>=23f, final explosions warn>=30f, and copies have no affixes, regeneration, revival, summoning, splitting, portal, or reward capabilities. `elite_mirror` can be bound to any valid ordinary parent but executes only its first damaging action. Support IDs never pass ordinary Launch count checks.

## 6. Elite affixes

Elite body scaling is HP x2.0, damage x1.25, collision unchanged, visual silhouette x1.15, plus the species elite move. Floor-one/two elites receive one affix; floor-three/four/five receive two. Maximum elites are one in combat rooms and two in elite rooms, with at most one support elite. Elite selection and affix draws use `elite_affix_v1:<floor_id>:<node_id>:<spawn_id>`. Affixes cannot alter warning floors or spawn recursive elite children. Affix IDs use lower-case stable content IDs; original uppercase codes are documentation aliases only.

| ID / original alias | Exact bounded behavior | Exclusions / floors / cue |
|---|---|---|
| `frenzy` / `FRENZY` | Damage1.25,speed1.15,damage taken1.20; no warning shortening | Excludes fortified;1-5;red chevrons/steam |
| `fortified` / `FORTIFIED` | HP1.50 on elite body,knockback resistance+0.20 capped0.90,speed0.80 | Excludes frenzy;1-5;stone plate icon |
| `regenerating` / `REGENERATING` | Every120f heal3%maxHP, encounter total30%maxHP, interrupts for120f after heavy hit | Excludes nullified/shielded;1-5;green cross |
| `teleporting` / `TELEPORTING` | Every480f reserve48-80px collision-safe landing,30f departure warning+30f arrival recovery | Excludes anchored;2-5;double-arrow outline |
| `splitting` / `SPLITTING` | Final death reserves two ordinary no-affix copies,33%baseHP,TTL480,once-only,zero independent reward | Excludes nullified/mirroring and species with own split/echo/summon/portal/revival;2-5;two-fragment icon |
| `shielded` / `SHIELDED` | Shield30%maxHP; regeneration after1200f only once; shield break gives45f exposure | Excludes regenerating/chaining;2-5;gold shield contour |
| `nullified` / `NULLIFIED` | Converts Stop into at least30f delay plus30f vulnerability, Rift movement floor0.70, retained damage/echo interactions | Excludes regenerating/splitting;3-5;clock-fragment icon; never time immunity |
| `anchored` / `ANCHORED` | Zero displacement from knockback/portal; incoming launch control becomes+20 poise and20f recovery at threshold100 | Excludes teleporting;3-5;ground chain icon; Stop/Rift remain effective |
| `chaining` / `CHAINING` | Accepted Player damage grants up to two nearby allies ATK1.15 for90f,source cooldown120f,no stacking | Excludes shielded;3-5;linked lightning icon |
| `mirroring` / `MIRRORING` | Every900f warn40f then spawn one `elite_mirror`,TTL480,no more than one alive | Excludes splitting and species with own split/echo/summon/portal/revival;4-5;outlined duplicate icon |

Affix state includes clocks, used shield regeneration, healing expenditure, child spawn ledger, source/generation claims, and owner lifetime. Mutual exclusions are symmetric. A pool without a legal pair selects a different candidate through the same deterministic decision; an empty valid pool reports `NO_LEGAL_ELITE_AFFIX_SET` rather than granting fewer affixes. No generic coin/drop table executes outside P14 economy authority.

## 7. Five Boss behavior kits

All Bosses use the same strict coordinator and public control bridge but different data and arena handlers. Tables use `W/A/R/CD` in frames, inclusive active offsets, and px geometry. `W` already combines the original warning/preparation portions; do not add an invisible extra preparation clock. Idle is20f unless a table specifies a larger recovery. Primary move selection uses weights10 melee,8 ranged,6 zone,4 summon/utility,2 enrage; maximum consecutive use is one except bolts (two) and explicit multi-hit actions. Named P1 moves remain in later phases unless a form changes. Phase transitions happen after the current frame damage settlement, cancel pending primary actions, retire their facts, and create a60f nonattacking cue. No new HP bar, hidden healing, infinite poise, or extra HP appears at transitions.

Enrage begins at the declared unscaled accepted frame count and changes damage by1.20 and cooldown by0.85; warning and recovery floors stay fixed. Every enrage action has a validated reachable safe corridor at least48px wide after combined P14 hazard and Boss geometry. Safe geometry is explicit scene/arena state and is announced from warning. A rule cannot permanently consume the last safe route; coexisting geometry that violates this delays the Boss action, preserving its decision index. The final Boss allows multiple defensive answers and never forces a particular time pair, weapon, item, or remaining energy balance.

### 7.1 Ruin King / Guardian of the Ruins

800 total HP, P1 above60%, P2 at/below60%; movement70/84px/sec; poise threshold200 with45f recovery extension; enrage at18000f. Arena has four HP80 cover pillars and one open perimeter route. Charge collision breaks only declared destructible cover and grants60f exposed recovery; wall placement cannot block both exits or encase Player/Boss.

| Move ID / phases | W/A/R/CD | Mechanical result |
|---|---|---|
| `guardian_shield_sweep` /1-2 | 48/10/40/240 | 18(22P2),paired widening-triangle cones at -45/+45 degrees, length56 half-width56,knockback40; front half-plane covered, rear safe side |
| `guardian_fist_slam` /1-2 | 55/8/60/360 | 25,target circle r48 at locked point; second12-damage r32 explosion after60f with its own40f warning |
| `guardian_rift_beam` /1-2 | 55/30/50/480 | 15 at offsets0/10/20,line half-width12 length192,cover blocks |
| `guardian_charge` /1-2 | 45/60/45/600 | 22,swept line half-width16 length128,speed112,wall collision stops |
| `guardian_rift_pulse` /2 | 60/6/55/720 | 28,circle r96,perimeter reachable in warning |
| `guardian_debris_barrage` /2 | 40/1/40/480 | Six10-damage projectiles within120 degrees,speed128,TTL90; debris construct TTL480,HP20,at most four,placement safe |
| `guardian_wall` /2 | 55/1/35/900 | HP150 wall segments total128px,TTL600,32px passage; final collapse warns40f before8 damage r24 |
| `guardian_enrage_collapse` /enrage | 75/15/60/900 | 40,three fixed line strips leaving48px safe corridor; destroys cover after warning,never unavoidable full arena damage |

Stop extends the committed warning or recovery and exposes the blue core; Rewind dodges the locked slam/beam; Accelerate converts60f slam recovery; Rift slows charge and aligns debris lanes. Core heavy/finisher, piercing, elemental, and poise interactions use existing weapon endpoints.

### 7.2 Forest Heart / Void Tree Matriarch

1400 total HP, P2 at60%,stationary body; six HP100 root constructs,poise200 converted to core exposure; enrage16200f. Destroying a root permanently disables its segment and exposes the body45f. At P2 three surviving roots retire deterministically, never resurrect destroyed roots. Four HP30 spore sacs and three one-use healing flowers are authoritative constructs; each flower heals20 through HealthComponent once. The body is always hittable by melee at the trunk. Edge erosion is capped at two16px steps and respects the48px safe route.

| Move ID / phases | W/A/R/CD | Mechanical result |
|---|---|---|
| `matriarch_root_sweep` /1-2 | 45/12/40/180 | 20(26P2),selected surviving-root cone96x48;burn6 per60f for180f |
| `matriarch_spore_release` /1-2 | 60/1/45/600 | Up to four r19 pools,TTL360,tick8/60f,slow0.75; placements fixed from warning; source eight-spore visual count may remain decorative |
| `matriarch_root_pierce` /1-2 | 47/8/35/420 | 28,line half-width8 length128,slow0.40 for90f |
| `matriarch_void_seed` /1-2 | 40/1/35/720 | Mark one sac,35 damage r40 after warning; killing it in warning cancels owned burst; poolr29/TTL480/tick12/60f |
| `matriarch_void_cage` /2 | 70/1/45/1080 | ThreeHP50 walls around48px square,32px permanent gap,TTL300; inner8-damage pulses each warn30f; collapse warns40f before15 persegment |
| `matriarch_call` /2 | 70/1/50/1200 | Two `void_sapling` at marked edge slots;owner death cancels |
| `matriarch_drain_roots` /2 | 50/60/40/900 | Three line lanes half-width5 length128;5 damage offsets0/15/30/45;body heals actual accepted HP loss x1 capped80percast and200encounter |
| `matriarch_enrage_dissolution` /enrage | 80/20/60/720 | 45,four marked pool sectors,TTL300,central48px corridor remains; no full-screen unavoidable field |

Stop extends root/seed warnings and vulnerability; Rewind clears fixed pool paths; Accelerate reaches breakable sacs/roots; Rift diverts saplings/slows drain lanes. Staff freeze/blind and gauntlet poise extend trunk recovery instead of being rejected by stationary form.

### 7.3 Time Sovereign / Traitor of Time

2000 total HP,P2 at60%;speed112/126px/sec,poise150/200;enrage14400f. History holds180f positions/HP; self rewind restores at most150HP percast,300HP perencounter,never decrements phase/kill/claim facts. Watch weakpoint is a hittable child proxy carrying damage to the body and is reachable by every weapon. Its independent HP cannot cause an extra room reward.

| Move ID / phases | W/A/R/CD | Mechanical result |
|---|---|---|
| `traitor_temporal_slash` /1-2 | 35/6/30/180 | 24(30P2),cone48x24;mark time damage1.15 for240f,one mark maximum |
| `traitor_chrono_bolt` /1-2 | 32/1/30/120 | 18,one visible projectile speed160/r8/range240,impact r16 slow zoneTTL180 |
| `traitor_blink` /1-2 | 35/1/30/480 | Safe fixed landing48px behind locked Player direction; subsequent slash has its entire35f warning,no instant boosted hit |
| `traitor_self_rewind` /1-2 | 70/1/55/1500 | Mark historical landing/heal amount,weakpoint80 cumulative damage cancels; capped restore and55f punishment |
| `traitor_time_freeze` /2 | 60/120/45/900 | circle r80,tick15/60f,slow0.40;time regen floor0.50,all time input retained |
| `traitor_rift_slash` /2 | 45/39/45/480 | Three20-damage cones at0/17/34,locked directions0/-30/+30;all visible at commitment |
| `traitor_timeline_split` /2 | 75/1/60/1320 | Two `timeline_echo`,each TTL1200,HP200;final explosion warns35f before20,r32 |
| `traitor_enrage_collapse` /enrage | 75/30/60/600 | 50,three r48 locked circles,48px safe corridor;accepted hit costs at most10energy,never energy zero;echo bursts separately warn |

Four time-response IDs use shared cooldown900f inP1/600f inP2,minimum45f response warning,and defer until current primary recovery. They can be queued once per authentic ability generation, not triggered by a mere UI/input event:

- `traitor.counter_stop`: after72f, warns45f for r64 pulse20; weakpoint damage40 cancels and extends recovery60f. Stop's original warning extension/exposure remains granted; the counter never retroactively clears the Player's source.
- `traitor.counter_rewind`: marks the restored endpoint and follows to a collision-safe nearby landing with45f warning; the existing Rewind echo crossing the watch grants30f exposure. It never changes Player history or teleports Player.
- `traitor.counter_accelerate`:30f warning then r64 slow0.70 fieldTTL120; six distinct accelerated hit identities shatter it and grant90f exposure; Accelerate benefit remains positive outside the field.
- `traitor.counter_rift`: marks its own field interaction45f, then a30f delayed instability pulse extends Boss recovery45f. The Player Rift remains its full paid lifetime; no arbitrary source deletion.

Each response leaves a positive window and obeys the same concurrency/escape budgets. Synthetic tests prove each of the six time pairs has at least one conversion under both phases and each of five weapon loadouts can damage the weakpoint.

### 7.4 Forge Colossus / Forge Lord

2800 total HP,three forms at100-60%,60-25%,25-0%;no extra500HP or healing at transformation. Smith moves84px/sec, Furnace stationary, Forged140px/sec;poise250/200/180;enrage12600f. FourHP120 anvils, four fixed vents,and four cooling pools are declared arena recipes. Pools remove owned burn on entry through the modifier authority with30f peractor cooldown; they do not disappear during enrage. Furnace vents coordinate with P14 forge-vent rule to avoid duplicate damage origins and preserve the same safe-route budget. Stage changes retire prior form-owned persistent hazards before new ones activate.

| Move ID / form | W/A/R/CD | Mechanical result |
|---|---|---|
| `forge_hammer_slam` /1 | 48/10/55/300 | 28,target circle r56,poolr32TTL180,tick8/60f,burn10/60f for180f |
| `forge_furnace_spray` /1 | 35/45/35/420 | 12 at0/15/30,cone96x32,locked direction,ground poolTTL120 |
| `forge_lava_toss` /1 | 47/1/35/360 | One22-damage marked projectile speed112,impact poolr32TTL300,tick8/60f;two-shot variant requires second full warning |
| `forge_combo` /1 | 40/44/50/600 | 18/22/32 at0/16/34;two cones40/48 and finalcircler56,all geometry visible fromwarning |
| `forge_furnace_devour` /2 | 55/90/45/720 | r112 pull<=32px/sec,tick10/60f;inner r16 hit40once,escape with ordinary movement |
| `forge_anvil_sweep` /2 | 35/12/35/180 | One selected-arm cone80x40,32damage;sequences allocate separate warnings/generations,at mosttwo concurrent arms |
| `forge_eruption` /2 | 65/20/55/900 | Six marked r24 circles,35each,placement>=32px,union keeps48px route,poolsTTL120 |
| `forge_forged_thrust` /3 | 30/6/30/150 | 36,line half-width10 length80,knockback32 |
| `forge_sword_wave` /3 | 32/1/35/240 | 30,visible line-wave half-width16,speed144,range192,pierces one declared obstacle |
| `forge_forged_cyclone` /3 | 42/60/45/720 | 15 at0/10/20/30/40/50,r48,movement48px/sec,fixed chase route;no ground immunity |
| `forge_enrage_ultimate` /enrage | 80/10/80/900 | 60,three line strips and finite poolsTTL300;cooling-pool corridor safe;no full arena forced damage |

Stop extends hammer/form3 recovery; Rewind escapes a marked toss/eruption; Accelerate overcomes the capped pull; Rift slows waves/cyclone. Furnace converts staff/poise/control to core exposure; stationary never means control immunity.

### 7.5 Void Throne / King of the Void

3000 total HP,three phases at100-60%,60-20%,20-0%;movement126/0/154px/sec,poise180/220/200;enrage10800f. Four HP120 pillars become nondamaging cover debris inP2. Core is always reachable; outer body damage0.60 and core exposure damage1.50,not an exclusive weakpoint that melee cannot reach. P3 creates fourHP100 plane-core constructs;each destroyed core deals100body damage and60f exposure once perround. A round of allfour gives120f exposure then cores may regenerate after600f,maximumtwo rounds total. This replaces the original inconsistent5-second stun/80-frame recovery and unlimited damage loop. P3 start heals Player30%maximum HP once through HealthComponent;no revival if Player died in that frame.

| Move ID / phase | W/A/R/CD | Mechanical result |
|---|---|---|
| `voidking_scepter_strike` /1,3 | 28/5/30/150 | 30,cone48x24,burn2/30f for180f |
| `voidking_void_bolt` /1,3 | 28/1/30/90 | 22,visible projectile r10,speed176,range240,slow0.65 for120f |
| `voidking_plane_tear` /1,3 | 47/90/35/480 | line half-width12 length160,tick15/60f,slow0.50;final25 r32 burst independently warns40f;time skills remain usable |
| `voidking_void_step` /1,3 | 30/1/30/360 | Mark landing40px behind oldtarget;follow-up starts new28fwarning,never free guaranteed hit |
| `voidking_void_grasp` /1,3 | 55/6/40/720 | 20,target circle r48,slow0.40 for90f;no stamina-cost override or unavoidable next attack |
| `voidking_tentacle_lash` /2 | 35/8/35/120 | 35,line half-width12 length96;selectedtentacle,30f core exposure;series keep every warning |
| `voidking_vortex` /2 | 60/120/45/900 | circler128,pull<=32px/sec,tick12/60f;inner r24hit40once,normalmovementescape |
| `voidking_devour` /2 | 75/10/65/1200 | 50,circler64;accepted hit applies damage-output0.85 debuff180f then removes;never deletes/silences item ownership or paid abilities |
| `voidking_shard_projection` /2 | 28/1/30/300 | Eight18-damage visible radialprojectiles,speed128,TTL120;at mostfour pickupconstructsTTL180,+5energy each via authenticated once-only Player resource boundary |
| `voidking_dual_strike` /3 | 35/22/40/180 | 28+28,cone48x24+perpendicularline10x64,offset0/17;no hidden +20% dual-hit bonus |
| `voidking_void_end` /3 | 80/15/80/1080 | 55,one markedhalf-arena andtwo r24 circles,oppositehalf remains safe48pxcorridor,finitezoneTTL300 |
| `voidking_existence_denial` /3 | 110/20/100/1800 | 65,three declaredline strips,48pxcorridor;any corebreak interrupts;ordinary dodge/guard also works;no HP-to1,energy-zero,item-silence or instantDOTcombo |
| `voidking_enrage_zero` /enrage | 90/10/90/1200 | 70,alternatinghalf-arena with48pxcorridor,corebreak interruption;no999damage or forced1HP |

Stop exposes core and extends denial warning; Rewind moves from locked grasp/half-arena geometry; Accelerate reaches core-break windows; Rift redirects shard paths/slows tentacles and extends recoveries. Each of all six time pairs remains useful through allthree phases.

Boss final receipt contains `boss_id`, phase history, accepted battle frames, accepted damage duringP3, committed Rewind uses duringP3, core-round claims, and content/action digests. P15 stores these as versioned narrative inputs; the later ending resolver combines them with five-core collection and curse/health facts. Do not choose an ending or award an achievement inside a Boss scene.

## 8. Encounter composition and scene integration

Each of five Launch profiles owns exactly five named combat recipes and three elite recipes, totalingforty, plus one Boss encounter perprofile. A recipe contains stable ID, room-type/template constraints, threat budget, at mostthree waves, integer delays/warnings, canonical enemy references, elite capabilities, and ordered slot offsets. At leastone recipe per floor includes support/ranged/melee priorities and one uses room topology. Floorone firstcombat forbids elite and support+exploder+zone overlap; floorfour/five permit at mosttwo of those three pressure roles simultaneously.

| Floor | Five combat recipe IDs / concrete roster | Three elite recipe IDs / designated elite |
|---|---|---|
| Ruins | `sentinel_line`:3sentinels;`watcher_guard`:2sentinels+watcher;`moth_crossfire`:2moths+sentinel;`wraith_shell`:wraith+strider;`ruin_full`:2sentinels+moth+watcher | `sentinel_trial`:sentinel;`shell_trial`:strider;`watcher_trial`:watcher |
| Forest | `hunter_archer`:2hunters+archer;`bramble_spores`:mage+3spores;`caller_archer`:caller+archer;`lurker_hunter`:lurker+hunter;`forest_full`:hunter+archer+mage+2spores | `hunter_trial`:hunter;`bramble_trial`:mage;`caller_trial`:caller |
| Rift | `guard_priest`:guard+priest;`weaver_blink`:weaver+blink;`hound_pack`:3hounds;`storm_archer`:storm+2archers;`rift_full`:guard+weaver+blink | `guard_trial`:guard;`blink_trial`:blink;`storm_trial`:storm |
| Forge | `titan_ranger`:titan+ranger;`web_titan`:webweaver+titan;`chaos_crossfire`:amalgam+archer;`ripper_pack`:ripper+2hunters;`forge_full`:titan+ranger+webweaver | `titan_trial`:titan;`chaos_trial`:amalgam;`ripper_trial`:ripper |
| Throne | `throne_front`:guard+titan;`throne_lanes`:ranger+2archers;`throne_mirror`:amalgam+blink;`throne_space`:ripper+weaver;`throne_guard`:guard+webweaver+priest | `throne_titan_trial`:titan;`throne_chaos_trial`:amalgam;`throne_blink_trial`:blink |

Recipe IDs are scoped by the existing profileID; these names cannot collide with the M1 encounter namespace. Combat threat budgets byfloor are4-6/5-8/6-9/7-10/7-11; elite recipes replaceone member of a valid combatrecipe with the designated elite and addone normal escort,never exceed the roster/payload budgets. Elite budget cost is basecost+3; recipe validation may split a too-large roster into two orderedwaves. Authored five-floor profile selection uses `launch_encounter_v1:<floor_id>:<node_id>`, chooses room-compatible recipes without immediate repeat, and seals the chosen recipe andpositions. Boss selection has no randomidentity.

Launch spawn positioning consumes the active `LaunchRoomScene`'s validated `EncounterAnchors` and CameraBounds, not M1 `SpawnPoints`/`BossSpawnPoint` fallback coordinates. Resolve deterministic offsets around `enemy_wave_primary` or the Boss anchor, using the existing16px grid; require collisionfree positions,32px separation,>=64px from Player entry,room-bound margin16px,and reachable route for eachbody. Arena recipes declare cover/sac/root/pool/corepositions and validate against those samebounds. Native roomscenes retain exactlyone root script under `RoomSceneContract`; constructs/actors spawn through the runtimeauthority afterbinding.

M1 continues `EncounterRunner`'s timer-based waves. Launch uses `LaunchEncounterRuntime` frame-based pending waves and registers the same `RoomRuntime` spawn/death/completion interface. RoomRuntime mode selects one runner beforebegin,including event-combat continuation; it cannot runboth. Generation cancellation and stagedspawn cleanup apply on newrun,death,room/floortransition,Savefailure,Replayrestore,andreset. A stalecallback cannot createanactor,damage,orcompletearoom.

## 9. Time, weapon, Character, and UI contracts

Launch actors keep the existing public signatures for hostile identity/threat configuration, identity snapshots, `apply_time_stop_source(source_id: StringName, duration: float)`, Stop removal, Rift application/removal, weakpoints, damage vulnerability, elemental status, weapon hit control, cleanup, and Boss UI. Sources store authoritative remaining frames rather than Timer callbacks. Source identity deduplicates applications and restoration. Ordinary Stop freezes action/motion while unscaled source lifetimes continue. Elite Stop grants at least 30 frames of freeze or conversion; Boss Stop grants `clamp(round(duration * 60 * 0.35), 30, 66)` warning/recovery extension and 45 frames of exposure per new source. Rift movement floors are 0.45 ordinary, 0.60 elite, and 0.70 Boss. Actor-owned payloads use the same frame bridge and retain positive Stop/Rift effects.

All Bosses implement `extend_character_boss_exposure(stop_generation: int, frames: int) -> bool`, strict Character exposure snapshots/identity, replay authority configuration, restore preflight, and authorized restore. Preserve the current schema 1 identity/claim format, maximum 30 extension frames, maximum 32 active claims, and monotonic consumed-generation floor. Share this state in a dedicated Boss conversion component. Warden's schema 1 restore contract remains byte-compatible.

All Bosses implement `apply_weapon_control_conversion(source_id: StringName, recovery_frames: int, exposure_frames: int, poise_damage: float) -> bool`. New conversion applies only in RECOVERY/EXPOSED and preserves committed windup; source claims are bounded and deduplicated, with extension capped at 90 frames. Staff freeze/blind become 12/8 frame extensions. Gauntlets retain `gauntlets_poised_launch`, the 1.40 poise factor, no airborne state, and `preserve_committed`. Sword guard/finisher, Bow erosion/piercing, Gun Time Load/Void Penetration, Staff elements, and all five Character endpoints remain valid. Every Boss supports a positive control conversion.

`get_boss_ui_snapshot() -> Dictionary` returns existing Boss HUD fields plus localized name, phase index/total, current/maximum HP, action cue, exposure, and enrage facts through a strict ViewState extension. Stable IDs never appear onscreen. Controller-only movement/guard/time, settings, pause/resume, restart, loadout selection, and room/floor completion work at 640x360, 1280x720, 1920x1080, and 2560x1080 with safe framing. Phase/title labels fit the existing compact HUD.

## 10. Save and Replay

Introduce `HostileReplaySeal` schema 1 with strict JSON-safe world state: run/floor/node/encounter identity; content/profile/action digests; frame and encounter generation; recipe/wave/pending warnings; stable-source-sorted actor records; domain position/velocity; HP/life state; AI decision index; action phase/generation/committed geometry/hit claims/cooldowns; revival/phase history; affix/summon/construct/payload state; time/elemental/conversion lifetimes; healing/shield/core/reward expenditure; pending final-death receipts; exact publication prefix and terminal digest. Nodes, Callables, Resources, and weak-referenced damage owners are not serialized. Stable IDs rebind validated authorities on restore.

SaveEnvelope schema 4 and an explicit v3-to-v4 migration add `hostile_runtime`. Inactive profiles, M1 profiles, and Launch between-room checkpoints without pending hostile effects receive an empty seal. Legacy active adapter combat cannot be converted into a fabricated P15 fight: it fails with `LEGACY_LAUNCH_HOSTILE_STATE_UNAVAILABLE` and preserves the original save/backups, exposing the existing recovery/new-run flow. A current active P15 save round-trips exact state before activation. Loading stages actors under a detached root, prevalidates references, phase/frame, geometry and ledgers, then atomically installs roster and threats. Corruption, changed packs, duplicate generations, exceeded budgets, inconsistent pending deaths, and unauthorized restore reject without publishing kills, heals, spawns, or room facts.

Full-player Launch Replay envelope/frame/snapshot advance to schema 7 because hostile checkpoints become required. M1 full-player Replay 2 and weapon Replay 6 retain existing contracts. RunDungeonReplaySeal advances to schema 4 and seals resolved encounter definitions, the hostile world digest, final defeat receipts, and Boss phase history. Schema 3 P14 adapter replays cannot play through P15 behavior; legacy reading requires the matching old content fingerprint or returns an explicit incompatibility code. Add closed, versioned hostile action/spawn/life/phase/arena/conversion/defeat fact validators.

Live and Replay advance the same Player/HostileFrameBridge boundary. Compare checkpoint state and accepted fact prefixes as well as final HP. Recipe, target, generation, hit-index, time-claim, revival, arena-HP, defeat-receipt, or payload-geometry divergence rolls back and fails closed. Gameplay Rewind uses only approved Player history and never calls hostile world restore. Replay/Save restore uses an opaque host authority capability and reconstructs previous world state without ordinary gameplay publication.

## 11. Visual and audio deliverables

P15 shows distinct species and Bosses through project-owned raster pixel atlases and reproducible local generation. `PixelProxyActor` remains an M1 fallback but cannot constitute all 27 Launch actors' final art. Enemy frames are 32x32 or 48x48; Boss frames are 64x64 or 96x96. Every actor has idle 2 frames, move 4, warning 3, active 2, recovery 2, hit 1, and death 4; stationary actors breathe instead of walking. Special tracks include shell/open, burrow/landing, blink, sigil/reform, three Amalgam faces, broken roots, trunk exposure, watch weakpoint, three Forge forms, and three Void forms. Art scale never changes collision dimensions.

Assets live under `data/content_packs/base/assets/enemies/launch/` and `assets/bosses/launch/`, with source/generator provenance under `assets/sources/p15/`. Scenes are `enemy_<species>.tscn` and `boss_<bossid>.tscn`. Each original generated asset records `CC0-1.0`, content hash, and generation recipe; external art requires a recorded compatible license. Generated rasters are saved and imported. Runtime SVG or recolored M1 polygon assets do not satisfy this gate.

Reuse `CombatAudioSynth` for offline original sound with closed stone/acid/root/shadow/clock/metal/void families and distinct warning, impact, death, and phase patterns. Save WAV sources or deterministic generator recipes with hashes. Warning audio has a localized subtitle alternative; cue pitch/duration never drives gameplay. Five original Boss loop stems provide normal/phase/enrage layers and crossfades through local manifested assets.

High-contrast outlines and affix symbols work without color, flash, shake, rumble, or animation. Reduced motion uses static shapes and countdown markers. No single-frame white flash or fullscreen strobe is permitted. Audio/subtitle settings never remove geometry; rumble settings never change damage. Capture all 22 enemies in normal/elite states, all Boss phases, 48 moves, and four time responses under normal/reduced-motion/high-contrast modes at 640x360 and ultrawide. Verify larger-resolution HUD and scene framing too.

## 12. Verification and evidence gate

Completion requires code, content, tests, documentation, and reproducible build/import paths for each slice:

- Exact 22 enemy, 10 affix, 9 summon, 5 Boss, 5 profile, 40 recipe, and 5 Boss encounter counts; canonical IDs, localization, asset hashes, handlers, parameters, and references validate.
- Every base/elite action, 48 Boss moves, and four responses execute real effects. Test selection chooses moves but never fabricates damage, results, or room clears.
- Mechanism tests cover distinct behavior, every legal affix pair, once-only revival, interrupts, teleport arrival, breakable cages/links/cores, heal caps, cleanup, and nonrecursive children.
- Warning/active/recovery boundaries, committed aim, multi-hit deduplication, geometry agreement, expiry extension, pause, rejection, and rollback publication pass.
- Main streams all five Boss rooms and combat/elite/event-combat per floor with actual Launch actors and active floor hazards. No M1 fallback resolves a Launch ID.
- Thirty canonical seeds repeat recipe/affix/arena/action digests. `30 x 150 x 5 = 22,500` synthetic traces prove bounded deterministic behavior; a separate `150 x 5 = 750` production SceneTree matrix captures real damage/control/phase/core/terminal facts.
- Five weapons, four abilities, six pairs, and five Characters retain positive Boss conversions. Every large AOE has a validated escape using ordinary movement, dodge, or guard without a mandatory loadout.
- Mid-action/time/burrow/dormancy/shell/split/phase/core/death/wave Save and Replay round-trip. Partial failures restore exact state and observable fact prefixes.
- Restart and transition remove actors, pending waves, payloads, threats, modifiers, links, portals, conversions, and staged scenes. Scan generic Godot errors and leaks in addition to process exit codes.
- Supported resolutions, inputs, accessibility, zh_CN/en, raster pixel content, Boss music/audio/subtitles pass visual and interaction QA.
- Full project validation, Python content contracts, Godot focused/integration/smoke/replay/migration suites, document governance, and clean checkout certification pass. Export evidence records actual results or honest existing environment blockers.

Simulation remains synthetic, does not count toward authentic playtests (`0 / 20`), and does not promote formal M1 beyond `M1 Candidate — External Validation Pending`. The retention review records commits, tests, content fingerprints, visual evidence, limitations, and rollback points. This milestone performs no remote push, public publication, purchase, private-identity operation, or commercial monetization.

## 13. Execution slices and self-review

Implement P15A content/action contracts; P15B fixed-frame transactions; P15C Ruins; P15D Forest; P15E Rift; P15F Forge/affixes/composition; P15G first two Bosses; P15H Time/Forge Bosses; P15I final Boss; P15J Save/Replay and routing; P15K assets/UI/audio/accessibility; P15L simulation and clean certification. Each slice begins with failing tests and ends with precise file-list commits.

Design self-review (2026-10-04): counts reconcile to 5/6/6/5 with Forge Spirit preserved in Expansion. Five Bosses retain P14 references; primary moves total `8 + 8 + 8 + 11 + 13 = 48`, plus four time responses. Nine summons do not inflate ordinary counts. Every named Boss move has a bounded readable version; time/weapon/Character endpoints have tests. Ring geometry makes no safe-center claim. Nonterminal revival cannot finalize a room. Floor/Boss hazards share safety budgets. Save/Replay versions and all module/test/asset/documentation ownership are explicit. The triple-blink active interval is 58 frames, covering its final offset 54. This design claims no runtime or human verification.
