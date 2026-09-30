# Plane Walker P12 Five Complete Characters Design

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: Five-character runtime, identity, input, presentation, replay, talent, and 150-loadout verification authority
- Applies To: Wanderer, Time Guardian, Void Walker, Primordial Knight, Time Lord, character runtime profiles, character skills, weapon mastery, time-pair conversions, character HUD, Launch Loadout selection, replay, simulations, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/4_角色与数值体系设计.md`, `docs/0_深度收敛与系统职责设计.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-30
- Implementation Status: Approved under the standing full-product authorization after locally certified P11 documentation commit `120dd46`; implementation has not started

## 1. Decision

P12 completes the five launch characters as a real runtime dimension rather than a catalog-only label. Every Launch run chooses exactly one character, one weapon, and two distinct time abilities:

```text
5 characters × 5 weapons × 6 unordered time pairs = 150 loadouts
```

Each character contains six inseparable parts:

1. an authoritative versioned runtime profile;
2. fresh base stats and mobility policy applied atomically at run start;
3. one distinctive visible character resource and passive loop;
4. one remappable `character_skill` action;
5. explicit weapon-mastery and equipped-time-ability conversions;
6. three character-specific Run Talent definitions.

Character identity cannot be a simple permanent damage multiplier. It must change what the player watches, earns, spends, risks, or sequences while preserving every weapon's core grammar.

## 2. Reconciliation with retained character drafts

The retained character document preserves names, story, visual direction, signature terminology, and build fantasies, but its April 2026 mechanics and absolute values are not executable authority where they conflict with Current specifications.

P12 resolves the important conflicts as follows:

- Canonical names and IDs are `wanderer`, `time_guardian`, `void_walker`, `primordial_knight`, and `time_lord`.
- A run still equips one formal weapon. Primordial Knight uses a delayed planar echo of that weapon rather than a second selectable weapon, so the required matrix remains 150 instead of expanding into weapon pairs.
- Time Lord strengthens and combines the two equipped time abilities. It does not grant unselected free Stop or Rewind actions.
- Time Guardian retains universal Dash and every weapon's escape/counter grammar. Its defensive identity is additive and never removes Gauntlets Dodge Counter or Bow charge cancel.
- Staff Mana and time energy remain separate resources for every character.
- Character skills use the semantic `character_skill` action. Legacy `LB / Q` examples do not override current weapon and time-slot mappings.
- Old character-specific item and blessing concepts are preserved as the fifteen P12 Run Talents rather than silently expanding the fixed launch item and blessing counts.
- Old raw damage multipliers are replaced by bounded resources, conversion windows, echoes, armor, recovery, and pair interactions.

## 3. Considered approaches

### 3.1 Character branches inside `PlayerController`

Adding five character-ID branches directly to `PlayerController`, `HealthComponent`, `TimeManager`, every weapon, and every UI projector would be the shortest initial diff. It is rejected because the controller already exceeds five thousand lines, character switching would be non-atomic, replay state would fragment, and later talents would multiply the branches.

### 3.2 Profile plus orchestrated character runtime

One `PlayerCharacterRuntime` owns a profile and delegates character-specific decisions to five small strategy runtimes. A shared character-action coordinator advances only from the Player's existing fixed frame pump and reserves the existing `PlayerActionState`; it never owns an independent `_process()` or wall clock. This approach is selected.

### 3.3 Fully data-driven character behavior graph

A behavior DSL could encode every damage interception, mastery rule, time interaction, and talent. It is rejected for P12. The five concrete characters must first prove the stable handler vocabulary; arbitrary data-driven condition graphs would be harder to validate and replay than typed strategies.

## 4. Milestone isolation

The character profiles are milestone-aware:

```text
wanderer_m1_v1              M1 / CURRENT / NEXT
wanderer_launch_v1          LAUNCH / EXPANSION
time_guardian_launch_v1     LAUNCH / EXPANSION
void_walker_launch_v1       LAUNCH / EXPANSION
primordial_knight_launch_v1 LAUNCH / EXPANSION
time_lord_launch_v1         LAUNCH / EXPANSION
```

`wanderer_m1_v1` preserves the certified M1 Player stats, Quick Start, damage, action, time-energy, HUD, room, reward, replay, and reset behavior. P12 cannot add Path Marks, a character skill, a character HUD meter, or Launch stats to M1/CURRENT/NEXT by accident.

Formal M1 remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`. P12 does not promote Bow, Rift, or Accelerate to Current.

## 5. Character runtime profile authority

The Base Pack adds `character_runtime_profile_v1` with exact fields:

```text
id
profile_version
character_id
availability
runtime_kind
base_stats
mobility
resource
passive
character_skill
weapon_mastery
time_interactions
presentation
capabilities
talent_ids
```

`base_stats` contains finite engine-unit values for HP, attack, defense, move speed, attack speed, critical chance, critical multiplier, time-energy maximum, and time-energy regeneration. `mobility` contains Dash cooldown/cost policy and invulnerability frames. Resource, passive, skill, mastery, time-interaction, presentation, capability, and talent references use approved typed handler IDs; content cannot invoke arbitrary methods.

ContentRegistry rejects:

- missing or duplicate profile IDs;
- character/profile ID mismatch;
- availability widening;
- non-finite, negative, or impossible stats;
- unknown runtime, passive, skill, mastery, time, payload, cue, talent, palette, or meter handlers;
- unsupported weapon/time references;
- invalid frame windows, costs, caps, rates, or cooldowns;
- profiles that omit any of the five weapons or four time abilities from their interaction contract.

`RunLoadoutPolicy` resolves exactly one character profile and one weapon profile before accepting a run. The Host injects both authoritative deep copies into the Player. Character and weapon assembly is a single two-phase transaction: if either side fails, the prior character, weapon, stats, health, energy, snapshots, UI state, and runtime remain unchanged.

## 6. Stats, damage, and fresh-run reconstruction

Each new run rebuilds a fresh Stats state from the character profile before applying run-local rewards. Character switching never mutates and reuses the previous run's already-modified Stats resource.

Launch baselines use current engine units:

| Character | HP | ATK | DEF | Move | Time max | Time regen |
|---|---:|---:|---:|---:|---:|---:|
| Wanderer | 200 | 30 | 0 | 220 | 100 | 2/s |
| Time Guardian | 240 | 27 | 10 | 190 | 120 | 2/s |
| Void Walker | 160 | 32 | 0 | 235 | 90 | 2/s |
| Primordial Knight | 230 | 31 | 8 | 200 | 110 | 2/s |
| Time Lord | 175 | 24 | 2 | 205 | 160 | 4/s |

These values are deterministic implementation baselines, not human-validated balance conclusions.

P11 weapon baselines remain unchanged for Wanderer. Every weapon payload derives character scaling from:

```text
character_attack_scale = active_character_attack / 30.0
```

The scale applies at immutable action planning to Sword, Bow, Gun, Staff, and Gauntlets, including payloads that currently use weapon-specific base numbers. Wanderer therefore retains exact P11 damage while other characters affect all five weapons consistently. Character echoes and conversions carry explicit non-recursive tags and cannot generate mastery, resources, time extensions, or additional echoes.

Critical results use the deterministic run-seed channel. Global `randf()` is not accepted for P12 character or 150-matrix evidence.

## 7. Shared runtime and action contract

`PlayerCharacterRuntime` exposes a narrow contract:

```gdscript
configure(owner, profile, character_talents) -> bool
reset_runtime_state(reason) -> void
advance_frame(context) -> Array[Dictionary]
plan_character_skill(intent, context) -> Dictionary
commit_character_skill(plan, token) -> Dictionary
before_damage(damage_context) -> Dictionary
after_damage(damage_context) -> Array[Dictionary]
on_weapon_action_committed(action_context) -> Array[Dictionary]
on_weapon_mastery_confirmed(mastery_context) -> Array[Dictionary]
before_time_skill(time_context) -> Dictionary
after_time_skill(time_context) -> Array[Dictionary]
on_room_started(room_context) -> Array[Dictionary]
on_room_cleared(room_context) -> Array[Dictionary]
on_run_terminal(run_context) -> Dictionary
snapshot() -> Dictionary
restore_snapshot(snapshot) -> bool
presentation_snapshot() -> Dictionary
```

The character coordinator owns token, generation, hold, windup, active, recovery, cooldown, and immutable committed plan data, but advances only from `PlayerController.advance_action_frame()`. It must acquire a compatible `PlayerActionState` transition before commit. Weapon, time, Dash, hitstun, selection, death, rewind-safe restore, loadout replacement, and terminal state invalidate stale character callbacks.

The new semantic action is:

```text
character_skill
```

It receives keyboard, mouse/controller, remap, conflict, persistence, glyph, and hold/toggle accessibility coverage. Default bindings are conventional but never authoritative over saved remaps. Character runtimes inspect semantic press/release/held-frame intents only.

## 8. Weapon mastery fact

P12 adds one coordinator-safe typed fact:

```text
weapon_mastery_confirmed(
  weapon_id,
  mastery_id,
  action_id,
  token,
  target_id,
  context
)
```

The five mastery families are:

| Weapon | Mastery success |
|---|---|
| Sword | perfect guard/counter or the profile-declared correct heavy commitment |
| Bow | full-charge weak-point or penetration confirmation |
| Gun | perfect reload conversion or profile-declared magazine-finisher confirmation |
| Staff | valid ordered combination or profile-declared controlled-zone conversion |
| Gauntlets | Dodge Counter or profile-declared Combo threshold/finisher confirmation |

One action token may grant at most one mastery fact per mastery family. Pellets, arrows, chains, zones, echoes, status ticks, and multiple target entries cannot multiply character resources.

Mastery facts are frozen semantic outcomes, not character-specific branches inside weapon runtimes. Character runtimes consume the common fact and apply their own bounded interpretation.

## 9. Character facts and irreversible ledgers

P12 adds typed facts:

```text
character_skill_committed(character_id, skill_id, token, context)
character_resource_changed(character_id, resource_id, current, maximum, reason)
character_conversion_resolved(character_id, conversion_id, token, context)
```

Facts publish exactly once from their owning coordinator/runtime. Rejected character plans change no HP, energy, cooldown, resource, status, payload, cue, replay prefix, or presentation state.

The following are irreversible ledgers and are never refunded by Rewind:

- character-skill HP and time-energy costs;
- Path Mark, Ward, Void Debt, Resonance, and Codex Page consumption;
- mastery claims;
- Void self-damage;
- room-clear banking and terminal rewards;
- killed enemies, dropped rewards, and world-owned echoes/zones.

## 10. Wanderer

Wanderer is the reliable conversion character. Its visible resource is `path_marks`, `0..5`.

### Path Mark loop

- Each eligible weapon mastery advances `path_progress` once per action token.
- Three progress confirms create one Path Mark; the first mark in a room may be earned immediately to preserve onboarding pace.
- An accepted equipped time-skill commit consumes at most one Path Mark and opens a 180-frame Wayfarer Window.
- The next mastery inside the window restores six time energy, heals two percent maximum HP, and applies the weapon's bounded forgiveness descriptor; it cannot generate another mark from the same token.
- Room clear heals two HP per unspent Path Mark and records the room completion, but no permanent damage multiplier is granted.
- Run terminal converts banked room completions into a pending `memory_fragment` summary field for the later Hub/meta system. P12 records the deterministic amount without pretending the Hub wallet already exists.

### Character skill: Waypoint Recall

- First accepted press costs 30 time energy and creates an anchor for 480 frames.
- A second press returns to the anchor position and heals 25% of damage actually taken since placement, capped by missing HP.
- Expiry or use begins a 720-frame cooldown.
- The anchor does not resurrect, undo world consequences, duplicate rewards, or refund its cost through Rewind.

### Time conversions

| Ability | Wanderer conversion |
|---|---|
| Stop | Wayfarer Window lasts 60 additional frames; Stop duration itself is unchanged |
| Rewind | Player movement may rewind, but anchor ownership, costs, consumed marks, and room banking remain authoritative |
| Accelerate | Path progress threshold becomes two while Accelerate is active, with one mark maximum per action token |
| Rift | First mastery inside an authorized Rift generation grants one extra Path progress |

## 11. Time Guardian

Time Guardian converts precise defense into tempo. Its visible resource is `ward`, `0..3`.

### Chrono Bulwark loop

- A perfect character guard, a normal character guard, or a profile-declared defensive weapon mastery may grant Ward.
- One hostile attack token grants at most one Ward, regardless of pellets, zones, or repeated collision.
- Taking eligible damage with Ward consumes one stack, reduces the final amount by 35%, and opens a 180-frame Rebuke Window.
- The next weapon mastery inside Rebuke creates one non-recursive `0.75 × character attack` time echo and reduces the longer equipped time-skill cooldown by 30 frames.
- Ward cannot reduce self-cost, corruption, terminal, or explicitly unguardable damage.
- Universal Dash remains available. Character defense never removes a weapon's own guard, charge cancel, or Dodge Counter.

### Character skill: Bulwark / Chrono Fortress

- Press begins a deterministic guard: frames `0..8` are perfect, `9..23` are normal, frame `24` is closed.
- Perfect guard prevents the eligible hit and grants one Ward. Normal guard reduces the eligible hit by 50% and grants one Ward only if no Ward was granted for that hostile token.
- Holding to 30 frames may consume three Ward and 40 time energy to commit Chrono Fortress for 180 frames.
- Fortress reduces movement to 70%, grants 50% frontal damage reduction, and may gain at most one Ward per hostile attack token.
- Reaching three Ward during Fortress arms one bounded shockwave on the next mastery; it does not auto-repeat on every multi-hit attack.

### Time conversions

| Ability | Time Guardian conversion |
|---|---|
| Stop | Rebuke echo may extend Boss exposure but cannot extend enemy Stop |
| Rewind | Spent Ward and prevented damage remain spent; a restored position cannot recreate the same guard claim |
| Accelerate | Weapon recovery shortens normally, while guard accessibility windows remain fixed real frames |
| Rift | A full-Ward Rebuke echo may anchor to the authorized Rift center once per Rift generation |

## 12. Void Walker

Void Walker converts visible health risk into bounded spatial payoff. Its resource is `void_debt`, `0..100`.

### Void Debt loop

- Actual enemy damage and explicit character self-cost add debt after final damage resolution.
- Debt grants no permanent global damage multiplier.
- At 60 or more debt, corruption deals two true HP per second; this tick is source-owned, deterministic, and never mastery-eligible.
- An eligible mastery converts up to 20 debt only when the player is inside a declared risk boundary: within 240 pixels of a hostile, inside an active hostile telegraph, or intersecting an authorized Rift.
- Conversion creates one non-recursive void echo and heals at most six HP. It cannot be multiplied by target count.
- At 100 debt, further debt is rejected rather than overflowing. A later talent may change the cap, but no base runtime enters undefined negative-HP state.

### Character skill: Void Devour

- Commit costs 25 time energy and `max(10, 20% maximum HP)` as irreversible self-damage, but cannot pay through terminal death.
- It creates one 8-tile, 60-degree cone with `4.0 × character attack` base void damage.
- Healing equals 15% of total confirmed damage and is capped at 12% maximum HP per cast.
- One or more kills may reset the cooldown once per cast, never once per target.
- Rewind may restore enemy-inflicted HP according to its contract, but never refunds Devour HP, energy, debt, cooldown claim, or killed enemies.

### Time conversions

| Ability | Void Walker conversion |
|---|---|
| Stop | Corruption ticking pauses while the owned Stop source is active; debt does not decrease |
| Rewind | Enemy damage may rewind, but self-cost and debt stay in the irreversible ledger |
| Accelerate | Mastery conversion recovery shortens, while corruption ticks on the same authoritative frame budget |
| Rift | Risk conversion inside the authorized Rift consumes ten additional debt and increases only the echo area, not target-count healing |

## 13. Primordial Knight

Primordial Knight converts heavy commitment into armor and a delayed planar echo. Its resource is `resonance`, `0..3`.

### Planar Resonance loop

- One eligible mastery grants one Resonance per action token.
- At three Resonance, the next profile-declared commitment-tier action reserves all three stacks atomically.
- The committed action gains a bounded armor window during its vulnerable windup and schedules a planar echo after recovery.
- The echo repeats the action's approved payload descriptor at `0.75 ×` damage and cannot generate mastery, Resonance, character facts, resource rewards, or another echo.
- If payload construction, armor installation, or echo scheduling fails, Resonance and action state roll back together.
- The echo is world-owned after commit and is not deleted by a later player-position Rewind.

This preserves the retained twin-plane fantasy without adding a second formal weapon or multiplying the 150-loadout space.

### Character skill: Realm Cleave

- Commit costs 35 time energy and consumes the current `0..3` Resonance stacks.
- The 360-degree five-tile payload deals `1.5 × character attack + 0.35 × character attack per consumed stack`.
- Consuming three stacks adds an eight-second `planar_instability` target claim that increases later approved damage by 20%; repeated targets and echoes cannot duplicate it.
- Windup grants armor, not invulnerability. Boss control converts through the P11 poise/exposure contract.

### Time conversions

| Ability | Primordial Knight conversion |
|---|---|
| Stop | A scheduled echo may release at owned Stop end, but cannot prolong Stop |
| Rewind | Player state may rewind; committed world-owned echo and consumed Resonance remain authoritative |
| Accelerate | Echo delay shortens, while the armor window remains bounded by the committed action definition |
| Rift | One echo may anchor to and scale inside the authorized Rift generation |

## 14. Time Lord

Time Lord routes the two equipped time abilities into one deliberate pair engine. Its resource is `codex_pages`, `0..3`, plus one optional `primer_ability_id`.

### Chrono Codex loop

- One eligible weapon mastery grants one Codex Page per action token, subject to the profile rate cap.
- The first equipped time ability committed with at least one Page becomes the Primer and opens a 300-frame pair window.
- Committing the other equipped ability inside the window consumes one Page and resolves exactly one unordered pair interaction.
- Repeating the same ability refreshes neither Primer nor Page claim.
- Time Lord's higher energy maximum and regeneration do not replace Staff Mana, Gun ammunition, Gauntlets Combo, Bow charge, or Sword guard.

### Character skill: Codex Infusion / Time Dominion

- Tap costs ten time energy and arms one Codex Infusion. The next mastery converts its approved echo to `2.0 × character attack` time damage and clears the infusion.
- Holding to 60 frames may consume two Pages and 60 time energy to commit Time Dominion for the currently equipped unordered pair.
- Dominion reuses the pair interaction below at its enhanced bounded value and starts a 480-frame cooldown. It never casts an unselected third ability.
- Costs, Page consumption, Primer identity, world consequences, and cooldown claims are irreversible through Rewind.

### Pair interactions

| Equipped pair | Codex conversion |
|---|---|
| Stop + Rewind | Rewind leaves one bounded stasis echo at the pre-return position; no resource or world consequence is refunded |
| Stop + Rift | The authorized Rift slows hostile projectiles while Stop is active, capped by source and duration |
| Stop + Accelerate | Stop end grants one short player-recovery grace window without extending enemy lock |
| Rewind + Rift | The world-owned Rift persists and pulses once at the recorded pre-return position |
| Rewind + Accelerate | The next mastery creates one non-recursive second-pass echo without granting a Page |
| Rift + Accelerate | Rift tick spacing compresses while total tick count and total damage remain capped |

## 15. Fifteen character Run Talents

P12 converts the retained three build fantasies per character into exactly three character talents each. These are part of the fixed launch total of fifteen Run Talents, not extra items or blessings.

| Character | Talent IDs | Bounded effect |
|---|---|---|
| Wanderer | `pathfinder_rhythm`, `memory_anchor`, `universal_kit` | faster first Path Mark; stronger anchor recovery; larger but capped weapon forgiveness |
| Time Guardian | `widened_guard`, `fortress_core`, `temporal_rebuke` | wider perfect window; lower Fortress Ward threshold; stronger single Rebuke echo |
| Void Walker | `deep_debt`, `bounded_devour`, `risk_step` | higher debt cap with later corruption threshold; larger heal cap; wider risk boundary and conversion cap |
| Primordial Knight | `resonant_plate`, `echo_forge`, `realm_collapse` | longer armor window; stronger single echo; longer bounded instability claim |
| Time Lord | `codex_margin`, `efficient_inscription`, `dominion_cadence` | longer pair window; cheaper infusion; lower Dominion cost/cooldown |

Talent eligibility is character-scoped. Content validation rejects a character talent attached to another character, duplicate mutually exclusive nodes, unknown capability routes, or values outside profile caps.

## 16. ViewState, HUD, and Launch selection

`RunViewState` advances with a top-level `character_state` tagged union:

```text
character_id
skill_id
phase
cooldown_current
cooldown_max
meter_kind
meter_current
meter_max
status_id
status_stacks
status_remaining
secondary_id
secondary_value
```

Allowed primary meters are:

```text
wanderer          path_marks
time_guardian     ward
void_walker       void_debt
primordial_knight resonance
time_lord         codex_pages
```

The generic character HUD shows localized character name, one meter, one short status, and character-skill cooldown. It rejects unknown character/meter/status combinations, impossible values, non-finite numbers, invalid Primer IDs, and legacy character-specific top-level fields.

The Launch Loadout panel becomes three orthogonal selector rows rather than 150 cards:

```text
Character  < Wanderer >
Weapon     < Sword >
Time Pair  < Stop + Rewind >
```

The panel uses a compact two-column grid so Character, Weapon, Time Pair, fixed-height description, summary, Start, and Back still fit the existing 536×328 panel at 640×360. Focus order is Character → Weapon → Time Pair → Start → Back → Character. Selected stable IDs survive localization refresh and do not depend on array index or Registry alphabetical order.

Pixel Proxy uses profile-driven palette, silhouette accents, footprint, resource aura, skill cue, and damage-state cue. Programmatic proxy art is testable implementation evidence, not final human visual acceptance.

## 17. Replay, snapshot, and reset

The Player replay snapshot advances to include:

- character/profile identity and version;
- character coordinator token, generation, phase, frame, cooldown, and committed plan;
- character resource and passive state;
- character-owned anchors, guard claims, debt ledgers, echoes, primers, pair windows, and talent routes;
- irreversible ledger roots;
- character event-prefix identity.

Replay external facts add validated character mastery, damage resolution, skill result, time conversion, and room transition families. Record and playback validate complete before/after transitions before append or mutation.

Restore is atomic across Character Runtime, Weapon Coordinator, PlayerActionState, HealthComponent, TimeManager, owned payloads, irreversible ledgers, event prefix, ViewState, and Pixel Proxy state. A failed restore leaves the exact pre-restore snapshot or enters a documented safe reset; it never preserves a partial HP refund, duplicate Ward, missing debt, revived echo, refunded Page, or consumed capture sequence.

Death, run reset, loadout replacement, selection, terminal state, and scene disposal clear character-owned anchors, guard windows, corruption ticks, skill payloads, armor sources, echoes, pair windows, auras, and callbacks. No previous character state survives a later run.

## 18. Verification matrix

P12 requires layered evidence:

1. Character profile/schema contracts for six profiles, stats, resources, skills, mastery, time interactions, presentation, talents, availability, references, and pack integrity.
2. Atomic character+weapon loadout assembly, failure rollback, fresh Stats reconstruction, and Wanderer M1 parity.
3. Five focused character runtime suites covering every boundary, cap, cooldown, reset, snapshot, stale token, and failure rollback.
4. Twenty-five character × weapon mastery contracts. Every pair produces its semantic resource at most once per eligible action token.
5. Twenty character × individual-time-ability conversion contracts.
6. Thirty character × unordered-time-pair contracts, including all six Time Lord pair interactions.
7. Policy and Launch UI enumeration of all 150 loadouts with no duplicate or missing tuple.
8. Five runtime smoke shards, one per character, each covering five weapons × six time pairs twice with identical pre-reset and clean-reset digests.
9. Thirty expensive pairwise Replay/Boss/room cases using `weapon_index = (character_index + time_pair_index) % 5`, covering every character×weapon, character×pair, and weapon×pair relationship without replacing the 150 lightweight matrix.
10. Keyboard, mouse, real controller, remap, hold/toggle, focus recovery, rejection, and localization-refresh tests.
11. Character HUD and Launch panel checks at 640×360, 1280×720, 1920×1080, and ultrawide safe frames.
12. Full repository validation with only registered warnings.

## 19. Synthetic simulation report v2

The deterministic report advances to:

```text
5 characters × 5 weapons × 6 time pairs × 30 seeds = 4500 samples
```

Every sample identity includes `character_id`, `weapon_id`, ordered time pair, and seed. The report consumes the exact character and weapon profile hashes; generation is rejected if character profiles are missing or ignored.

In addition to P11 metrics, it records bounded character observations:

- signature resource efficiency;
- mastery conversion rate;
- damage prevented or armor value;
- Void Debt generated/converted;
- planar echo value;
- Codex pair completion frequency;
- character-skill use and rejection rates.

Summaries exist by character, weapon, character×weapon, and loadout. Two runs with identical inputs must be byte-identical. The report remains `source=synthetic`, `human_playtests=0`, and cannot authorize subjective balance, feel, comprehension, accessibility acceptance, or promotion.

## 20. Delivery decomposition

P12 is delivered through independently reviewable gates:

1. **P12A Character authority:** schema, six profiles, Registry resolution, LoadoutPolicy, fresh Stats boundary, facts, and failing contracts.
2. **P12B Runtime shell and Wanderer parity:** atomic Character Runtime assembly, coordinator, semantic input, snapshot/reset, `wanderer_m1_v1`, and `wanderer_launch_v1`.
3. **P12C Wanderer and Time Guardian:** Path Marks, Waypoint Recall, Ward, guard/Fortress, mastery/time conversions, talents, feedback, and tests.
4. **P12D Void Walker and Primordial Knight:** Void Debt/Devour and Resonance/Realm Cleave, irreversible ledgers, payloads, talents, feedback, and tests.
5. **P12E Time Lord:** Codex Pages, infusion, six pair interactions, Dominion, separate Staff Mana, talents, feedback, and tests.
6. **P12F Cross-character systems:** Launch selector, character HUD/ViewState, Pixel Proxy, accessibility, replay, legacy Wanderer assumptions, and UI integration.
7. **P12G Certification:** 25 mastery, 20 ability, 30 pairwise, 150 policy/UI/runtime matrices, simulation report v2, documentation, and full repository gate.

Shared files, manifests, Registry, RunLoadoutPolicy, Host, PlayerController, PlayerActionState, HealthComponent, TimeManager, replay codecs, ViewState, Launch UI, and Pixel Proxy have one integration owner at a time. Character-specific strategy runtimes, payloads, and focused tests may proceed in parallel only after P12A/P12B interfaces pass.

## 21. P12 exit gate

P12 is locally complete only when:

- all five character profiles resolve authoritatively at allowed milestones;
- M1/CURRENT/NEXT Wanderer parity remains unchanged;
- all five Launch characters have distinct stats, resource loop, skill, weapon mastery, four time interactions, three talents, HUD, feedback, controller, accessibility, snapshot, reset, replay, and cleanup;
- all five weapons scale from character attack without changing Wanderer P11 values;
- Primordial Knight uses one formal weapon and Time Lord uses exactly two equipped time abilities;
- the Launch panel selects all three dimensions and every one of the 150 loadouts validates and starts;
- the 25 mastery, 20 ability, 30 pairwise, five 30-loadout runtime shards, and deterministic 4500-sample simulation gates pass;
- full repository validation is green with only registered warnings;
- formal M1 remains `M1 Candidate — External Validation Pending`, authentic human playtests remain `0 / 20`, GDScript line coverage remains honestly reported, and export/signing/publication boundaries remain unchanged.
