# Plane Walker P12 Five Complete Characters Design

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: Five-character runtime, identity, input, presentation, replay, talent, and 150-loadout verification authority
- Applies To: Wanderer, Time Guardian, Void Walker, Primordial Knight, Time Lord, character runtime profiles, character skills, weapon mastery, time-pair conversions, character HUD, Launch Loadout selection, replay, simulations, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/4_角色与数值体系设计.md`, `docs/0_深度收敛与系统职责设计.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-30
- Implementation Status: P12A character-profile authority is certified locally at `61eaae6`; P12B deterministic shared-runtime work is next

## 1. Decision

P12 completes the five launch characters as a real runtime dimension rather than a catalog-only label. Every Launch run chooses exactly one character, one weapon, and two distinct time abilities:

```text
5 characters × 5 weapons × 6 unordered time pairs = 150 loadouts
```

The serialized pair uses the stable order `stop < rewind < rift < accelerate`. Reversed duplicates are invalid configuration rather than additional loadouts, so Launch and Expansion each expose exactly 150 accepted tuples, not 300 ordered slot permutations.

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

The Base Pack adds `character_runtime_profile_v1`. Each profile is a Content Pack v2 entry with the mandatory envelope fields `id`, `category=character_runtime_profile`, `availability`, `name_key`, `description_key`, `tags`, `compatibility`, and `effects`, followed by the typed runtime fields below. `content_entry_v2.schema.json` adds only this closed category and its closed fields; profiles cannot bypass the Content Pack v2 envelope, closed effect-handler catalog, localization coverage, cross-reference checks, manifest membership, or SHA-256 integrity map.

The exact entry fields are:

```text
id
category
availability
name_key
description_key
tags
compatibility
effects
references
profile_version
character_id
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

`base_stats` has exactly `max_hp`, `attack`, `defense`, `move_speed`, `attack_speed`, `crit_chance`, `crit_multiplier`, `time_energy_max`, and `time_energy_regen`. `mobility` has exactly `dash_duration_frames`, `dash_cooldown_frames`, `dash_speed`, `dash_cost_kind`, `dash_cost`, and `dash_invulnerable_frames`. `runtime_kind` is one of `wanderer_m1_compat`, `wanderer`, `time_guardian`, `void_walker`, `primordial_knight`, or `time_lord`. Resource, passive, skill, mastery, time-interaction, presentation, capability, and talent references use approved typed handler IDs; content cannot invoke arbitrary methods.

ContentRegistry rejects:

- missing or duplicate profile IDs;
- character/profile ID mismatch;
- availability widening;
- non-finite, negative, or impossible stats;
- unknown runtime, passive, skill, mastery, time, payload, cue, talent, palette, or meter handlers;
- unsupported weapon/time references;
- invalid frame windows, costs, caps, rates, or cooldowns;
- Launch profiles that omit any of the five weapons or four time abilities from their interaction contract, or `wanderer_m1_v1` that exposes anything beyond its certified milestone-eligible M1/CURRENT/NEXT surface.

P12A registers all fifteen Talent identities and localization keys so every `talent_ids` reference is real at pack-ingestion time. The three frozen Wanderer Talents retain their M1 effects and cover every `wanderer_m1_v1` and `wanderer_launch_v1` milestone: M1, CURRENT, NEXT, LAUNCH, and EXPANSION. The twelve other identities are Launch/Expansion character-scoped definitions; their runtime modifiers remain inactive until Task 5 installs the typed talent handlers. A profile cannot activate when a Talent is missing, has the wrong category or character, or does not cover every milestone exposed by the profile.

`RunLoadoutPolicy` resolves exactly one character profile and one weapon profile before accepting a run. The Host injects both authoritative deep copies into the Player. Character and weapon assembly is a single two-phase transaction: if either side fails, the prior character, weapon, stats, health, energy, snapshots, UI state, and runtime remain unchanged.

The Registry fingerprint and Replay identity include the sorted active-pack rows and aggregate digest from Content Pack v2. A profile loaded from an unmanifested file, a digest-mismatched Base Pack, an optional pack isolated by dependency/integrity failure, or an entry whose operational projection differs from the authoritative profile is never eligible for a run.

## 6. Stats, damage, and fresh-run reconstruction

Each new run rebuilds a fresh Stats state from the character profile before applying run-local rewards. Character switching never mutates and reuses the previous run's already-modified Stats resource.

Launch baselines use current engine units. Frames are authoritative 60 Hz frames; Dash has no resource cost in P12, so `dash_cost_kind=none` and `dash_cost=0` are explicit profile values rather than omitted behavior.

| Profile | HP | ATK | DEF | Move | Attack speed | Crit | Crit multiplier | Time max | Time regen/s | Dash duration | Dash cooldown | Dash speed | Dash cost | Dash i-frames |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| `wanderer_m1_v1` | 200 | 30 | 0 | 220 | 1.00 | 0.05 | 1.50 | 100 | 2 | 17f | 27f | 520 | `none:0` | 12f |
| `wanderer_launch_v1` | 200 | 30 | 0 | 220 | 1.00 | 0.05 | 1.50 | 100 | 2 | 17f | 27f | 520 | `none:0` | 12f |
| `time_guardian_launch_v1` | 240 | 27 | 10 | 190 | 0.90 | 0.04 | 1.50 | 120 | 2 | 18f | 30f | 500 | `none:0` | 12f |
| `void_walker_launch_v1` | 160 | 32 | 0 | 235 | 1.05 | 0.08 | 1.60 | 90 | 2 | 15f | 24f | 560 | `none:0` | 11f |
| `primordial_knight_launch_v1` | 230 | 31 | 8 | 200 | 0.90 | 0.05 | 1.55 | 110 | 2 | 18f | 30f | 490 | `none:0` | 10f |
| `time_lord_launch_v1` | 175 | 24 | 2 | 205 | 0.95 | 0.05 | 1.50 | 160 | 4 | 16f | 27f | 520 | `none:0` | 12f |

These values are deterministic implementation baselines, not human-validated balance conclusions.

P11 weapon baselines remain unchanged for Wanderer. Every weapon payload derives character scaling from:

```text
character_attack_scale = active_character_attack / 30.0
```

The scale applies at immutable action planning to Sword, Bow, Gun, Staff, and Gauntlets, including payloads that currently use weapon-specific base numbers. Wanderer therefore retains exact P11 damage while other characters affect all five weapons consistently. Character echoes and conversions carry explicit non-recursive tags and cannot generate mastery, resources, time extensions, or additional echoes.

Critical results use the deterministic run-seed channel and freeze the roll/result into the committed damage plan. Global `randf()` is not accepted for P12 character or 150-matrix evidence.

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

### 7.1 One authoritative fixed-frame pump

Gameplay time is exactly 60 authoritative frames per second. `PlayerController.advance_action_frame(frame_intents)` is the only live, Replay, and simulation pump and performs this order once per frame:

1. increment `runtime_frame` and validate the ordered intent envelope for that frame;
2. call `TimeManager.advance_frame(runtime_frame)` to regenerate energy through a fixed-point remainder, decrement cooldowns, Stop, Accelerate, Rewind windows, and every active Rift descriptor;
3. advance `PlayerActionState`, `TimeActionTransaction`, `CharacterActionCoordinator`, `WeaponActionCoordinator`, and deterministic world-payload lifetimes in that order;
4. expire stale tokens/generations and publish committed domain facts;
5. submit at most one accepted action from the frame's priority-ordered intents.

`TimeManager._process(delta)`, `RewindRecorder._process(delta)`, character runtimes, and payload runtimes may project visuals or interpolate only; they cannot change energy, cooldowns, effect duration, snapshots, corruption cadence, resources, or gameplay geometry. Rewind samples are captured every six authoritative frames for the existing ten-samples-per-second window. Replay feeds recorded intents into the same pump and may not call a time or character shortcut. A live/replay digest mismatch at any frame is a hard failure.

### 7.2 Time-action transaction

Every equipped time ability uses one `TimeActionTransaction`:

```text
prepare(token, generation, frame, run_id, ability_id, pre_context) -> prepared_ticket
commit(prepared_ticket) -> committed_fact | failure
rollback(prepared_ticket) -> exact_prepared_state
```

Prepare freezes cost, cooldown, source generation, position, selected pair, active Rift descriptors, and Rewind's pre-return position/path without mutating gameplay. Commit validates the same resource revisions and installs all energy, cooldown, action-state, owned-effect, Rift, and character-conversion changes atomically. Any failed install rolls every participant back to its prepare snapshot; no partial cost, cleared action, consumed snapshot, Primer, Page, Path Mark, or world payload remains.

The owning transaction publishes exactly one fact only after commit:

```text
time_skill_committed(ability_id, token, generation, frame, run_id, context)
```

Wanderer conversion, Time Lord Primer/pair state, Rewind interactions, replay capture, and presentation consume this fact rather than `time_skill_started`. Rejected or rolled-back attempts publish no committed fact. The Rewind origin used by Stop + Rewind and Rewind + Rift is the position frozen during prepare, never a position sampled after restore.

The new semantic action is:

```text
character_skill
```

Input profile schema 3 finalizes the P11 compatibility window. The v3 primary and backup are `input_profile_v3.json` and `backup_3.json`. Load order is verified v3 primary, verified v3 backup, verified v2 primary/backup, then verified v1 primary/backup. Schema 1 always runs the already-certified 1→2 mapper and the resulting semantic profile then runs the same 2→3 mapper; no direct 1→3 path exists. Successful migration is atomically persisted as schema 3 and round-tripped before the previous files can be treated as legacy recovery sources.

The 2→3 mapper preserves every v2 binding record byte-for-byte and adds `character_skill`. Fresh v3 defaults are keyboard `C` and controller button index `8` (right-stick click), released by retirement of the fixed Accelerate action. If either default is already owned in a real saved v2 fixture, the mapper does not steal or delete that remap: for keyboard/mouse it chooses the first unowned physical keycode in ascending printable-key order after testing `C`; for controller it chooses the first unowned button index in `8, 0..31` order. Exhausting either finite family rejects migration with `NO_REACHABLE_CHARACTER_SKILL` and preserves the verified v2 source. Tests include a checked-in real schema-2 file, a schema-1→2→3 fixture, collisions, corrupt primary recovery, atomic promotion, and exact v3 load/save/load equality.

The runtime no longer listens to or requires physical bindings for fixed `time_stop`, `time_rewind`, `time_rift`, and `time_accelerate`, although canonical ID mapping remains available for old replay/config migration. The action receives remap, conflict, persistence, glyph, and hold/toggle accessibility coverage. Character runtimes inspect semantic press/release/held-frame intents only.

When multiple edges arrive on one frame, the only gameplay priority is `Dash → time_slot_1/time_slot_2 in slot order → character_skill → weapon semantic actions in profile declaration order`. Once an action commits, lower-priority same-frame edges are recorded as `priority_suppressed` and discarded; they are never silently buffered. Dash cancels an uncommitted character windup/hold; hitstun and Gameplay Rewind cancel every uncommitted character phase before their own transition. Guardian Guard/Fortress hold follows this rule exactly: cancellation before any guard resolution spends no Ward/energy and starts no cooldown; cancellation after a perfect/normal guard preserves its fact/Ward and starts the 240-frame ordinary cooldown; cancellation at or after Fortress commit never refunds costs, and Fortress keeps its remaining authoritative frames. Dash cannot cancel committed Fortress, hitstun does not refund it, and Rewind restores only eligible player movement/HP. Waypoint anchors, committed Devour/Cleave payloads, and armed Dominion are likewise not deleted or refunded after commit.

## 8. Weapon mastery fact

P12 adds one coordinator-safe typed fact:

```text
weapon_mastery_confirmed(
  weapon_id,
  mastery_family,
  mastery_id,
  action_id,
  token,
  generation,
  target_id,
  context
)
```

The five mastery families are:

| Weapon | Mastery success |
|---|---|
| Sword | `sword_perfect_guard` on a prevented perfect guard, `sword_counter_confirmed` when Counter confirms damage, or `sword_charged_commitment` when a `charged_slash` released at ≥30 hold frames confirms damage |
| Bow | `bow_full_charge_weakpoint` when the ≥48-frame full tier confirms a weak point, or `bow_full_charge_penetration` when that arrow confirms its second distinct stable target |
| Gun | `gun_perfect_reload` on confirmation frames `28..35`, or `gun_magazine_finisher` when a non-Time-Load normal/aimed shot spends the final available round and confirms damage |
| Staff | `staff_ordered_combination` when the valid second charged element confirms within the 300-frame sequence, or `staff_controlled_zone` when one Plane Collapse generation confirms three distinct stable targets |
| Gauntlets | `gauntlets_dodge_counter` when Dodge Counter confirms damage, `gauntlets_combo_threshold` when one action crosses Combo 15 or 30, or `gauntlets_chain_finisher` when punch five confirms damage |

The exactly-once claim key is `(generation, action_token, mastery_family)`. For P12, `mastery_family` is the canonical `weapon_id`; multiple `mastery_id` values reported by the same weapon action still mint at most one fact/resource. Pellets, arrows, chains, zones, echoes, status ticks, repeated callbacks, and multiple target entries cannot multiply character resources. A later generation may reuse the numeric token only because the generation remains part of the key.

Mastery facts are frozen semantic outcomes, not character-specific branches inside weapon runtimes. Character runtimes consume the common fact and apply their own bounded interpretation.

## 9. Character facts and irreversible ledgers

P12 adds typed facts:

```text
character_skill_committed(character_id, skill_id, token, context)
character_resource_changed(character_id, resource_id, current, maximum, reason)
character_conversion_resolved(character_id, conversion_id, token, context)
```

Facts publish exactly once from their owning coordinator/runtime. Rejected character plans change no HP, energy, cooldown, resource, status, payload, cue, replay prefix, or presentation state.

### 9.1 Immutable damage resolution

`DamageInfo` becomes an immutable planned input and every target produces one immutable `DamageResolution`:

```text
resolution_id
run_id
target_id
hostile_source_id
attack_generation
action_token
original_amount
post_weapon_defense_amount
post_character_defense_amount
post_accessibility_amount
post_defense_amount
finalized_damage
prevented
prevent_reason
guard_kind
irreversible
tags
```

The only legal resolution order is:

```text
validity / death / immunity
→ weapon defense
→ character guard / Fortress / Ward
→ accessibility damage-received multiplier
→ flat defense
→ finalized damage
→ HP, hit reaction, death, irreversible ledger, and facts
```

Weapon and character defense return typed decisions and never mutate `DamageInfo.amount`. `prevented=true` fixes `finalized_damage=0`; it changes no HP, creates no Void Debt, generic `damage_applied`, hit reaction, knockback, or minimum-one-damage result, but may publish one typed guard/mastery fact. If a positive non-prevented attack remains after percentage stages, flat defense retains the existing minimum of one damage. Self-cost, corruption, terminal, and explicitly unguardable damage bypass weapon/character defense according to tags but still create a resolution/ledger record. Sword perfect guard and Guardian perfect guard therefore prevent the hit directly; subtract-one-then-heal is forbidden.

### 9.2 Stable hostile attack identity

Every hostile runtime receives a deterministic `hostile_source_id` from encounter identity, room generation, spawn slot, and spawn ordinal. `get_instance_id()`, memory address, tree order, localized name, and presentation-node path are forbidden identity inputs. Each source increments `attack_generation` when a new attack plan commits. Every pellet in one burst, every collision of one projectile, and every target affected by one zone tick shares the committed `(hostile_source_id, attack_generation)`; the next burst, projectile launch, or zone tick receives the next generation.

`DamageInfo`, guard claims, Ward claims, telegraph facts, Replay events, and tests carry both fields. Missing/empty source IDs or non-positive generations reject Launch hostile damage. Enemy Base, Chaser, Shooter, Projectile, Tank, Time Crack, and Chrono Warden all use the same allocator and snapshot their next-generation floor.

### 9.3 Unscaled hostile-threat facts

`HostileThreatRegistry` owns gameplay risk boundaries as immutable facts:

```text
hostile_source_id
attack_generation
shape
origin
aim_direction
target_point
summon_slots
radius
length
active_from_frame
active_through_frame
```

Geometry is authored in unscaled world units and queried by Void Walker against the current authoritative frame. `CombatTelegraph2D` only projects a threat fact and may apply visual scale `1.0`, `1.25`, or `1.5` and extra visual lead time without changing the registry. Gameplay risk membership, debt conversion, damage, and Replay digest must be byte-identical at all three accessibility scales. A presentation snapshot is never accepted as a gameplay query source.

### 9.4 Irreversible HP ledger and Rewind transaction

`IrreversibleCharacterLedger` stores monotonically increasing `irreversible_hp_loss_total: float` and `revision: int` beside resource/mastery claim roots. Every accepted self-cost, corruption tick, terminal cost, and other explicitly irreversible HP loss appends one stable claim and increases both values; healing never decrements the total. Each Rewind sample records the total and revision current at capture.

The maximum HP Rewind may install is:

```text
clamp(snapshot_hp - (current_irreversible_hp_loss_total - snapshot_irreversible_hp_loss_total), 0, current_max_hp)
```

A negative ledger delta, missing revision, duplicate claim, invalid HP, dead-to-alive transition, or participant revision mismatch rejects prepare. `RewindRecorder` exposes `prepare_rewind_transaction()`, `commit_rewind_transaction(ticket)`, and `rollback_rewind_transaction(ticket)`. Prepare freezes origin, path, destination, adjusted HP, safe action, facing, velocity, participant revisions, and TimeAction context and proves every participant can restore before changing anything. Commit installs the eligible player state and consumes snapshots only after all installs succeed. Failure restores the exact pre-prepare player/action/HP/snapshot state; actions, payloads, and snapshots cannot be cleared during preflight.

The following are irreversible ledgers and are never refunded by Rewind:

- character-skill HP and time-energy costs;
- Path Mark, Ward, Void Debt, Resonance, and Codex Page consumption;
- mastery claims;
- Void self-damage;
- room-clear banking and terminal rewards;
- killed enemies, dropped rewards, and world-owned echoes/zones.

### 9.5 World-payload authority

`WorldPayloadAuthority` assigns every committed projectile, echo, zone, Rift, delayed strike, anchor-owned pulse, and reward-bearing world effect a stable ID:

```text
run_id:owner_character_generation:payload_family:source_token:payload_generation
```

The descriptor freezes handler ID, owner, source action/time token and generation, transform, gameplay geometry, remaining frames, hit/claim set, non-recursive tags, and deterministic parameters. Instance IDs and presentation nodes are never serialized. The three restoration semantics are intentionally different:

1. **Gameplay Rewind:** does not restore, delete, respawn, or rewind any already committed world payload. Only eligible player movement/HP/action state changes.
2. **Replay checkpoint restore:** validates the complete stable-ID descriptor set, prepares every payload off-tree, and atomically replaces the current authoritative set with the exact checkpoint set. Any missing handler, duplicate ID, invalid claim set, or failed spawn rolls back to the exact pre-restore set.
3. **Run reset or loadout replacement:** destroys every payload whose `run_id` and owner character generation belong to the outgoing runtime, invalidates callbacks, and proves the authority is empty for that generation before the new runtime activates.

`TimeManager` Replay snapshots include energy/revision, every cooldown, Stop source/remaining/extension claims, Accelerate token/remaining, Rewind window, `time_rift_source_sequence`, and the sorted complete active-Rift stable-ID descriptors. Gameplay Rewind never installs that Replay snapshot; Replay checkpoint restore installs it only through the same atomic payload transaction.

## 10. Wanderer

Wanderer is the reliable conversion character. Its visible resource is `path_marks`, `0..5`.

### Path Mark loop

- Each eligible weapon mastery advances `path_progress` once per action token.
- The first eligible mastery in each room creates exactly one Path Mark and leaves `path_progress=0`; after that, three progress confirms create one Path Mark and reset progress to zero.
- An accepted equipped time-skill commit consumes at most one Path Mark and opens a 180-frame Wayfarer Window.
- The next mastery inside the window restores six time energy, heals two percent maximum HP, and applies the weapon's bounded forgiveness descriptor; it cannot generate another mark from the same token.
- Room clear heals two HP per unspent Path Mark and records the room completion, but no permanent damage multiplier is granted.
- Run terminal converts banked room completions into a pending `memory_fragment` summary field for the later Hub/meta system. P12 records the deterministic amount without pretending the Hub wallet already exists.

The one-shot forgiveness descriptor expires after 180 frames and is exact per equipped weapon: Sword subtracts four frames from the next recovery (minimum one), Bow reduces the next full-charge threshold from 48 to 44 effective frames, Gun expands the next reload perfect window from `28..35` to `26..37`, Staff extends the current/next ordered-combination window by 60 frames to a maximum 360, and Gauntlets extends the current Combo timeout by 30 frames to a maximum 150. It never changes damage, creates a resource, stacks with itself, or survives loadout/reset.

### Character skill: Waypoint Recall

- First accepted press has six windup frames and twelve recovery frames, costs 30 time energy at commit, and creates an anchor for 480 frames.
- A second accepted press uses the same six-frame windup/twelve-frame recovery, returns to the anchor position, and heals 25% of positive enemy `finalized_damage` recorded since placement, capped by missing HP. Self-cost, corruption, prevented damage, and healing do not enter the accumulator.
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
- One `(hostile_source_id, attack_generation)` grants at most one Ward, regardless of pellets, zones, or repeated collision.
- Taking eligible damage with Ward consumes one stack, reduces the final amount by 35%, and opens a 180-frame Rebuke Window.
- The next weapon mastery inside Rebuke creates one non-recursive `0.75 × character attack` time echo and reduces the longer equipped time-skill cooldown by 30 frames.
- Ward cannot reduce self-cost, corruption, terminal, or explicitly unguardable damage.
- Universal Dash remains available. Character defense never removes a weapon's own guard, charge cancel, or Dodge Counter.
- Within the character-defense stage, normal Guard resolves before Fortress and Ward; percentage reductions multiply. A Ward granted by the current hit is appended after damage resolution and cannot be consumed by that same hit.

### Character skill: Bulwark / Chrono Fortress

- Press begins a deterministic guard: frames `0..8` are perfect, `9..23` are normal, frame `24` is closed.
- Perfect guard prevents the eligible hit and grants one Ward. Normal guard reduces the eligible hit by 50% and grants one Ward only if no Ward was granted for that hostile token.
- Holding to 30 frames may consume three Ward and 40 time energy to commit Chrono Fortress for 180 frames.
- Fortress reduces movement to 70%, grants 50% damage reduction inside the 120-degree facing cone, and may gain at most one Ward per hostile attack token.
- Reaching three Ward during Fortress arms one shockwave on the next mastery: 192-pixel radius, `1.0 × character attack` time damage, one hit per target, no mastery/resource recursion. It does not auto-repeat on every multi-hit attack.
- Releasing or closing without Fortress starts the ordinary Guard cooldown of 240 frames. Fortress commit replaces it with a 600-frame cooldown. A failed frame-30 resource check ends the guard and starts the ordinary cooldown without spending Ward or energy.

### Time conversions

| Ability | Time Guardian conversion |
|---|---|
| Stop | One Rebuke echo per Stop generation may extend Boss exposure by 30 frames; it cannot extend enemy Stop |
| Rewind | Spent Ward and prevented damage remain spent; a restored position cannot recreate the same guard claim |
| Accelerate | Weapon recovery shortens normally, while guard accessibility windows remain fixed real frames |
| Rift | A full-Ward Rebuke echo may anchor to the authorized Rift center once per Rift generation |

## 12. Void Walker

Void Walker converts visible health risk into bounded spatial payoff. Its resource is `void_debt`, `0..100`.

### Void Debt loop

- Actual enemy damage and explicit character self-cost add debt after final damage resolution.
- Debt grants no permanent global damage multiplier.
- At 60 or more debt, corruption deals one true HP every 30 authoritative frames, totaling two HP per second; this tick is source-owned, deterministic, and never mastery-eligible.
- An eligible mastery converts up to 20 debt only when the player is inside a declared risk boundary: within 240 pixels of a hostile, inside an active hostile telegraph, or intersecting an authorized Rift.
- Conversion creates one 160-pixel-radius non-recursive void echo for `0.75 × character attack` and heals at most six HP. It cannot be multiplied by target count.
- At 100 debt, further debt is rejected rather than overflowing. A later talent may change the cap, but no base runtime enters undefined negative-HP state.

### Character skill: Void Devour

- Commit costs 25 time energy and `max(10, 20% maximum HP)` as irreversible self-damage, and is accepted only when current HP is strictly greater than the frozen cost so payment leaves at least one HP.
- The action has 24 windup frames, one active commit frame, 30 recovery frames, and a 480-frame cooldown. Dash or hitstun before the active frame cancels without cost; after commit the cone and costs persist.
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
| Rift | Risk conversion inside the authorized Rift consumes ten additional debt and increases only the echo radius from 160 to 224 pixels, not damage or target-count healing |

## 13. Primordial Knight

Primordial Knight converts heavy commitment into armor and a delayed planar echo. Its resource is `resonance`, `0..3`.

### Planar Resonance loop

- One eligible mastery grants one Resonance per action token.
- At three Resonance, the next profile-declared commitment-tier action reserves all three stacks atomically.
- The committed action gains 35% eligible enemy-damage reduction during its vulnerable windup and schedules a planar echo on the first authoritative frame after recovery.
- The echo repeats the action's approved payload descriptor at `0.75 ×` damage and cannot generate mastery, Resonance, character facts, resource rewards, or another echo.
- If payload construction, armor installation, or echo scheduling fails, Resonance and action state roll back together.
- The echo is world-owned after commit and is not deleted by a later player-position Rewind.

This preserves the retained twin-plane fantasy without adding a second formal weapon or multiplying the 150-loadout space.

The five Launch commitment-tier actions are exact: Sword `charged_slash` released at 30 or more hold frames, Bow `precision_draw` at its full-charge tier, Gun `aimed_fire` at 18 or more hold frames, Staff `charged_element` at 30 or more hold frames, and Gauntlets `charged_heavy` at 30 or more hold frames. Ultimates never auto-consume Resonance unless a later versioned profile explicitly replaces this table.

### Character skill: Realm Cleave

- Commit costs 35 time energy and consumes the current `0..3` Resonance stacks.
- It has 36 windup frames, one active commit frame, 30 recovery frames, and a 540-frame cooldown. During windup only, typed armor reduces eligible enemy damage by 40%; it does not affect true, self-cost, corruption, terminal, or unguardable damage.
- The 360-degree five-tile payload deals `1.5 × character attack + 0.35 × character attack per consumed stack`.
- Consuming three stacks adds a 480-frame `planar_instability` target claim that increases later approved damage by 20%; repeated targets and echoes cannot duplicate it.
- Windup grants armor, not invulnerability. Boss control converts through the P11 poise/exposure contract.

### Time conversions

| Ability | Primordial Knight conversion |
|---|---|
| Stop | A scheduled echo may release at owned Stop end, but cannot prolong Stop |
| Rewind | Player state may rewind; committed world-owned echo and consumed Resonance remain authoritative |
| Accelerate | Echo delay shortens, while the armor window remains bounded by the committed action definition |
| Rift | One echo may anchor to the authorized Rift center and multiply its area/length by 1.25 while keeping damage unchanged |

## 14. Time Lord

Time Lord routes the two equipped time abilities into one deliberate pair engine. Its resource is `codex_pages`, `0..3`, plus one optional `primer_ability_id`.

### Chrono Codex loop

- One eligible weapon mastery grants one Codex Page per action token, with a profile rate cap of one granted Page per 60 authoritative frames.
- The first equipped time ability committed with at least one Page becomes the Primer and opens a 300-frame pair window.
- Committing the other equipped ability inside the window consumes one Page and resolves exactly one unordered pair interaction.
- Repeating the same ability refreshes neither Primer nor Page claim.
- Time Lord's higher energy maximum and regeneration do not replace Staff Mana, Gun ammunition, Gauntlets Combo, Bow charge, or Sword guard.

### Character skill: Codex Infusion / Time Dominion

- Tap costs ten time energy, starts a 120-frame cooldown, and arms one Codex Infusion for 300 frames. The next mastery converts its approved echo to `2.0 × character attack` time damage and clears the infusion; expiry clears it without refund.
- Holding to 60 frames may consume two Pages and 60 time energy to commit Time Dominion for the currently equipped unordered pair.
- Dominion arms one enhanced pair charge for 300 frames and starts a 480-frame cooldown. The next valid completion of the equipped pair consumes that charge and uses the enhanced column below; expiry clears it without refund. It never casts an ability, refreshes Primer, or grants an unselected third ability.
- Costs, Page consumption, Primer identity, world consequences, and cooldown claims are irreversible through Rewind.

### Pair interactions

The base pair window is 300 frames. Only the other equipped ability can complete the Primer, exactly one Page is consumed, and one pair resolution is allowed per Primer generation.

| Equipped pair | Base conversion | Dominion-enhanced conversion | Hard cap |
|---|---|---|---|
| Stop + Rewind | At Rewind's prepare-frozen origin, create a 96-pixel stasis zone for 90 frames; hostile movement/projectile speed scalar is 0.50 | 128 pixels, 150 frames, scalar 0.35 | one zone per pair generation; no damage, resource, Stop extension, or world refund |
| Stop + Rift | While both authorized sources overlap, hostile projectiles inside the Rift use speed scalar 0.50 | scalar 0.35 | effect ends at the earlier source end and is capped at 180f base / 240f enhanced |
| Stop + Accelerate | At owned Stop end, newly committed weapon/character recovery uses multiplier 0.80 for 90 frames | multiplier 0.65 for 150 frames | minimum one recovery frame; no enemy Stop extension or cooldown acceleration |
| Rewind + Rift | The existing world-owned Rift persists and emits one pulse at Rewind's prepare-frozen origin for `1.25 × character attack` time damage using the Rift's authored unscaled radius | `1.75 × character attack` | one pulse, one hit per target, no knockback, Page, mastery, Rift respawn, or healing |
| Rewind + Accelerate | Arm the next mastery for 180 frames; it creates one non-recursive second-pass echo for `0.75 × character attack` | 300 frames and `1.10 × character attack` | one echo, one target claim, no Page/mastery/resource generation |
| Rift + Accelerate | Authorized periodic weapon/character payloads whose committed geometry intersects the Rift use tick-interval multiplier 0.75 | multiplier 0.50 | cap 180f base / 240f enhanced; committed tick count and total damage remain unchanged, so unused ticks are not added |

## 15. Fifteen character Run Talents

P12 completes the fixed launch total of fifteen Run Talents. The three existing M1 talents become Wanderer's Launch route without changing their M1 behavior and remain eligible anywhere the milestone-aware Wanderer profiles resolve; P12 adds twelve new character-scoped talents for the other four characters. These are not extra items or blessings.

| Character | Talent ID | Exact effect |
|---|---|---|
| Wanderer | `tal_eternity_reserve` | Existing M1 `low_energy_regen_multiplier=2.0` below `30` energy is unchanged. `wanderer_launch_v1` additionally changes Wayfarer mastery restore from 6 to 8 energy. |
| Wanderer | `tal_ruin_execute` | Existing M1 `heavy_execute_multiplier_bonus=0.5` at target HP ratio `≤0.30` is unchanged. Launch additionally grants one Path progress after the first mastery that consumes each Wayfarer Window. |
| Wanderer | `tal_steel_recover` | Existing M1 `max_hp_bonus=20` and acquisition heal `20` are unchanged. Launch additionally changes room-clear healing from 2 to 3 HP per unspent Path Mark. |
| Time Guardian | `widened_guard` | Perfect frames become `0..11`, normal frames `12..26`, and close frame `27`; cooldowns and Fortress hold threshold remain unchanged. |
| Time Guardian | `fortress_core` | Fortress Ward cost becomes 2 instead of 3; energy cost, duration, reduction, and cooldown remain unchanged. |
| Time Guardian | `temporal_rebuke` | Rebuke echo becomes `1.00 × character attack` and longer equipped time cooldown reduction becomes 45 frames instead of `0.75 ×` and 30 frames. |
| Void Walker | `deep_debt` | Debt cap becomes 120 and corruption threshold becomes 75; tick remains two true HP per second. |
| Void Walker | `bounded_devour` | Devour healing becomes 18% of confirmed damage, capped at 16% maximum HP per cast; cost, damage, and reset remain unchanged. |
| Void Walker | `risk_step` | Hostile proximity risk radius becomes 288 pixels and mastery conversion cap becomes 25 debt; telegraph/Rift rules and healing cap remain unchanged. |
| Primordial Knight | `resonant_plate` | Committed Resonance and Realm Cleave armor persists through the first 12 recovery frames; reduction percentage is unchanged. |
| Primordial Knight | `echo_forge` | Planar Resonance echo becomes `1.00 ×` approved payload damage instead of `0.75 ×`; all non-recursion rules remain. |
| Primordial Knight | `realm_collapse` | Three-stack `planar_instability` lasts 600 frames instead of 480; its 20% approved-damage bonus is unchanged. |
| Time Lord | `codex_margin` | Primer pair window becomes 420 frames instead of 300. |
| Time Lord | `efficient_inscription` | Infusion energy cost becomes 5 instead of 10; duration, result, and tap cooldown remain unchanged. |
| Time Lord | `dominion_cadence` | Dominion energy cost becomes 45 and cooldown 360 frames instead of 60 and 480; Page cost and charge lifetime remain unchanged. |

Talent eligibility is character-scoped. Content validation rejects a character talent attached to another character, duplicate mutually exclusive nodes, unknown capability routes, or values outside profile caps.

`wanderer_m1_v1` dispatches only the three frozen existing M1 effects and cannot resolve any Launch-only hook above. `wanderer_launch_v1` may resolve both the frozen effect and its declared Launch hook. Therefore P12 edits the three existing entries and adds exactly twelve entries; the Registry must count exactly fifteen character Run Talents, never eighteen.

### 15.1 Forty-case talent-subset matrix

Each character orders its three talent bits exactly as listed below and enumerates all `2^3=8` subsets, including empty, for `5 × 8 = 40` cases. Applying a subset canonicalizes IDs, rejects duplicates/cross-character IDs, applies each handler once, then snapshots cost, cooldown, window, cap, and character resource state. Replay record/playback and checkpoint restore must produce the same snapshot and event prefix for every row.

Wanderer bit order is `E=tal_eternity_reserve`, `R=tal_ruin_execute`, `S=tal_steel_recover`; the expected vector is `Wayfarer energy / bonus progress / max-HP bonus / room-clear HP per Mark`:

| Bits | Talents | Expected vector |
|---|---|---|
| `000` | none | `6 / 0 / 0 / 2` |
| `100` | E | `8 / 0 / 0 / 2` |
| `010` | R | `6 / 1 / 0 / 2` |
| `001` | S | `6 / 0 / 20 / 3` |
| `110` | E+R | `8 / 1 / 0 / 2` |
| `101` | E+S | `8 / 0 / 20 / 3` |
| `011` | R+S | `6 / 1 / 20 / 3` |
| `111` | E+R+S | `8 / 1 / 20 / 3` |

Time Guardian bit order is `W=widened_guard`, `F=fortress_core`, `T=temporal_rebuke`; the vector is `perfect last frame / Fortress Ward cost / Rebuke echo / cooldown reduction frames`:

| Bits | Talents | Expected vector |
|---|---|---|
| `000` | none | `8 / 3 / 0.75 / 30` |
| `100` | W | `11 / 3 / 0.75 / 30` |
| `010` | F | `8 / 2 / 0.75 / 30` |
| `001` | T | `8 / 3 / 1.00 / 45` |
| `110` | W+F | `11 / 2 / 0.75 / 30` |
| `101` | W+T | `11 / 3 / 1.00 / 45` |
| `011` | F+T | `8 / 2 / 1.00 / 45` |
| `111` | W+F+T | `11 / 2 / 1.00 / 45` |

Void Walker bit order is `D=deep_debt`, `B=bounded_devour`, `R=risk_step`; the vector is `Debt cap / corruption threshold / Devour heal ratio / heal cap / proximity radius / conversion cap`:

| Bits | Talents | Expected vector |
|---|---|---|
| `000` | none | `100 / 60 / 0.15 / 0.12 / 240 / 20` |
| `100` | D | `120 / 75 / 0.15 / 0.12 / 240 / 20` |
| `010` | B | `100 / 60 / 0.18 / 0.16 / 240 / 20` |
| `001` | R | `100 / 60 / 0.15 / 0.12 / 288 / 25` |
| `110` | D+B | `120 / 75 / 0.18 / 0.16 / 240 / 20` |
| `101` | D+R | `120 / 75 / 0.15 / 0.12 / 288 / 25` |
| `011` | B+R | `100 / 60 / 0.18 / 0.16 / 288 / 25` |
| `111` | D+B+R | `120 / 75 / 0.18 / 0.16 / 288 / 25` |

Primordial Knight bit order is `P=resonant_plate`, `E=echo_forge`, `C=realm_collapse`; the vector is `armor recovery extension frames / echo multiplier / instability frames`:

| Bits | Talents | Expected vector |
|---|---|---|
| `000` | none | `0 / 0.75 / 480` |
| `100` | P | `12 / 0.75 / 480` |
| `010` | E | `0 / 1.00 / 480` |
| `001` | C | `0 / 0.75 / 600` |
| `110` | P+E | `12 / 1.00 / 480` |
| `101` | P+C | `12 / 0.75 / 600` |
| `011` | E+C | `0 / 1.00 / 600` |
| `111` | P+E+C | `12 / 1.00 / 600` |

Time Lord bit order is `M=codex_margin`, `I=efficient_inscription`, `D=dominion_cadence`; the vector is `pair window frames / Infusion energy / Dominion energy / Dominion cooldown frames`:

| Bits | Talents | Expected vector |
|---|---|---|
| `000` | none | `300 / 10 / 60 / 480` |
| `100` | M | `420 / 10 / 60 / 480` |
| `010` | I | `300 / 5 / 60 / 480` |
| `001` | D | `300 / 10 / 45 / 360` |
| `110` | M+I | `420 / 5 / 60 / 480` |
| `101` | M+D | `420 / 10 / 45 / 360` |
| `011` | I+D | `300 / 5 / 45 / 360` |
| `111` | M+I+D | `420 / 5 / 45 / 360` |

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

`wanderer_m1_v1` keeps the certified P11/M1 replay schema, fields, ordering, and digest behavior unchanged. Launch profiles use Player Replay schema 4, whose event envelope has exactly `schema_version`, `frame`, `sequence`, `capture_sequence`, `run_id`, `content_snapshot_digest`, `character_profile_id`, `character_profile_version`, `event_type`, and `payload`. Playback rejects unknown fields, gaps, non-monotonic counters, profile/content identity mismatch, and invalid before/after state hashes before any mutation.

The Launch Player replay checkpoint includes:

- character/profile identity and version;
- character coordinator token, generation, phase, frame, cooldown, and committed plan;
- character resource and passive state;
- character-owned anchors, guard claims, debt ledgers, echoes, primers, pair windows, and talent routes;
- irreversible ledger roots;
- character event-prefix identity;
- the complete `TimeActionTransaction` token/generation floor and committed time facts;
- `DamageResolution` and irreversible-HP claim roots;
- the sorted exact `WorldPayloadAuthority` descriptor set, including active Rift descriptors and claim sets.

Replay external facts add validated character mastery, damage resolution, skill result, time-skill commit, time conversion, hostile threat, payload lifecycle, and room transition families. Every state-changing fact contains complete `state_before_hash` and `state_after` data. Record validates the actual transition before append; playback validates the prospective envelope and transition before mutation, applies through the same domain owner, then requires the resulting canonical hash to equal `state_after_hash`.

Replay checkpoint restore is atomic across Character Runtime, Weapon Coordinator, PlayerActionState, HealthComponent, TimeManager including Rifts, HostileThreatRegistry, WorldPayloadAuthority, irreversible ledgers, event prefix, ViewState, and Pixel Proxy state. All participants prepare and validate first; payloads are staged off-tree; commit swaps the exact state and only then advances capture sequence. A failed restore rolls every participant back to the exact pre-restore checkpoint and never preserves a partial HP refund, duplicate Ward, missing debt, revived/missing echo, refunded Page, altered Rift set, or consumed capture sequence. Safe reset is allowed only when rollback itself proves impossible and must terminate the run with a stable diagnostic rather than continue a divergent Replay.

Gameplay Rewind is not Replay checkpoint restore. It follows Section 9.4, never installs the TimeManager/WorldPayload Replay checkpoint, and cannot use Replay restore to reclaim irreversible state.

Death, run reset, loadout replacement, selection, terminal state, and scene disposal clear character-owned anchors, guard windows, corruption ticks, skill payloads, armor sources, echoes, pair windows, auras, and callbacks. No previous character state survives a later run.

## 18. Verification matrix

P12 requires layered evidence:

1. Content Pack v2 and character-profile schema contracts for six profiles, exact numeric projections, closed handlers, localization, references, manifest membership, SHA-256 integrity, availability, and aggregate content digest.
2. Atomic character+weapon loadout assembly, failure rollback, fresh Stats reconstruction, and byte-equivalent `wanderer_m1_v1` stats/action/HUD/replay parity.
3. Fixed-frame tests proving live, Replay, and simulation call the same pump and produce identical energy, cooldown, Stop, Accelerate, Rift, corruption, snapshot, and action digests without gameplay `_process(delta)` mutation.
4. Immutable DamageResolution tests for immunity, weapon defense, Guardian perfect/normal guard, Fortress, Ward, accessibility multiplier, defense, prevented hits, minimum damage, self-cost, death, and no ghost damage/Debt/reaction.
5. Rewind prepare/commit/rollback fault injection at every participant, irreversible-HP formula boundaries, no early snapshot/action clearing, and exact rollback after partial install failure.
6. Stable hostile identity and threat tests across pellets, bursts, projectiles, zone ticks, reset, Replay, and visual telegraph scales `1.0/1.25/1.5`, with identical gameplay risk membership.
7. World-payload tests proving Gameplay Rewind leaves committed payloads unchanged, Replay checkpoint reconstructs the exact stable-ID set atomically, and reset/loadout replacement clears the outgoing generation including Rifts.
8. Five focused character runtime suites covering every boundary, cap, cooldown, reset, snapshot, stale token, cancellation rule, and failure rollback.
9. Twenty-five character × weapon mastery contracts. Every pair produces its semantic resource at most once per `(generation, action_token, mastery_family)`, including different mastery IDs under one family.
10. Twenty character × individual-time-ability conversion contracts plus TimeAction rejection, rollback, exactly-once commit fact, and prepare-frozen Rewind origin.
11. Thirty character × unordered-time-pair contracts, including base and Dominion-enhanced values for all six Time Lord pair interactions.
12. Forty character talent-subset cases from Section 15.1, validating costs, cooldowns, windows, caps, resources, canonical subset identity, Replay record/playback, and checkpoint restore.
13. Policy and Launch UI enumeration of all 150 loadouts with no duplicate or missing tuple.
14. Five runtime smoke shards, one per character, each covering five weapons × six time pairs twice with identical pre-reset and clean-reset digests.
15. Thirty expensive pairwise Replay/Boss/room cases using `weapon_index = (character_index + time_pair_index) % 5`, covering every character×weapon, character×pair, and weapon×pair relationship without replacing the 150 lightweight matrix.
16. Keyboard, mouse, real controller, input priority, Guard/hold cancellation, schema-1→2→3, real schema-2 fixture, collision fallback, remap, hold/toggle, focus recovery, rejection, and localization-refresh tests.
17. Character HUD and Launch panel checks at 640×360, 1280×720, 1920×1080, and ultrawide safe frames.
18. Full repository validation with only registered warnings.

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

1. **P12A Character authority:** Content Pack v2 schema, six exact profiles, Registry resolution, LoadoutPolicy, fresh Stats boundary, facts, and failing contracts.
2. **P12B Deterministic shared runtime:** atomic Character Runtime assembly, fixed-frame TimeManager, TimeAction transactions, immutable DamageResolution, irreversible HP/Rewind transaction, world-payload authority, semantic input v3, snapshot/reset, `wanderer_m1_v1`, and `wanderer_launch_v1`.
3. **P12C Wanderer and Time Guardian:** Path Marks, Waypoint Recall, Ward, guard/Fortress, hostile attack identity, mastery/time conversions, talents, feedback, and tests.
4. **P12D Void Walker and Primordial Knight:** unscaled threat registry, Void Debt/Devour, Resonance/Realm Cleave, irreversible ledgers, payloads, talents, feedback, and tests.
5. **P12E Time Lord:** Codex Pages, unified committed time facts, infusion, six exact base/enhanced pair interactions, Dominion, separate Staff Mana, talents, feedback, and tests.
6. **P12F Cross-character systems:** Launch selector, character HUD/ViewState, Pixel Proxy, accessibility, schema-4 Launch Replay/checkpoints, legacy Wanderer isolation, and UI integration.
7. **P12G Certification:** 25 mastery, 20 ability, 30 pairwise, 40 talent subsets, 150 policy/UI/runtime matrices, simulation report v2, documentation, and full repository gate.

Shared files, manifests, Registry, RunLoadoutPolicy, Host, PlayerController, PlayerActionState, HealthComponent, TimeManager, replay codecs, ViewState, Launch UI, and Pixel Proxy have one integration owner at a time. Character-specific strategy runtimes, payloads, and focused tests may proceed in parallel only after P12A/P12B interfaces pass.

## 21. P12 exit gate

P12 is locally complete only when:

- all six character profiles resolve authoritatively at allowed milestones;
- M1/CURRENT/NEXT Wanderer parity remains unchanged;
- all five Launch characters have distinct stats, resource loop, skill, weapon mastery, four time interactions, three talents, HUD, feedback, controller, accessibility, snapshot, reset, replay, and cleanup;
- the shared 60 Hz pump is the sole gameplay clock and live/Replay/simulation digests match;
- prevented damage, irreversible HP, Rewind rollback, hostile identity, unscaled threats, TimeAction exactly-once facts, and all three world-payload restore semantics pass their fault-injection gates;
- all five weapons scale from character attack without changing Wanderer P11 values;
- Primordial Knight uses one formal weapon and Time Lord uses exactly two equipped time abilities;
- the Launch panel selects all three dimensions and every one of the 150 loadouts validates and starts;
- the 25 mastery, 20 ability, 30 pairwise, 40 talent-subset, five 30-loadout runtime shards, and deterministic 4500-sample simulation gates pass;
- full repository validation is green with only registered warnings;
- formal M1 remains `M1 Candidate — External Validation Pending`, authentic human playtests remain `0 / 20`, GDScript line coverage remains honestly reported, and export/signing/publication boundaries remain unchanged.
