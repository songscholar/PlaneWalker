# Plane Walker P11 Five Complete Weapons Design

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: Five-weapon runtime, input, presentation, and verification authority
- Applies To: Sword, Bow, Gun, Staff, Gauntlets, shared weapon action authority, weapon input semantics, weapon HUD state, weapon feedback, item hooks, time interactions, and the 30 weapon/time-loadout smoke matrix
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/3.1combat-system-design.md`, `docs/4_角色与数值体系设计.md`, `docs/5_6_UI美术音效技术设计.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-29
- Implementation Status: Approved under the standing full-product authorization; P11 implementation begins after locally certified P10A commit `2df1078`

## 1. Decision

P11 completes all five launch weapons through one authoritative weapon-action pipeline. It does not add Gun, Staff, and Gauntlets as conditional branches inside `PlayerController`, and it does not allow Bow or any new weapon to keep an independent action clock.

The selected architecture is:

```text
semantic input
  -> WeaponIntentRouter
  -> WeaponActionCoordinator (single action authority)
  -> active WeaponRuntime (weapon-specific rules and resources)
  -> hitbox/projectile/zone payload
  -> typed committed/hit/resource facts
  -> immutable weapon ViewState
  -> HUD, Pixel Proxy, VFX, audio, camera, replay snapshot
```

Five small weapon runtimes share one coordinator and one data contract:

- Sword asks for short commitments, charge choice, and guard timing.
- Bow asks for position, charge duration, range, and penetration alignment.
- Gun asks for ammunition, reload timing, and burst-cycle control.
- Staff asks for element sequencing, mana budgeting, and area control.
- Gauntlets asks for sustained close pressure without losing escape discipline.

P11 ends only when every weapon has a complete input path, action-state integration, unique resource or rhythm state, hit payload, item/modifier hooks, localized HUD state, animation/VFX/audio cues, controller support, four time-ability interactions, one Chrono Warden interaction, deterministic snapshot/reset behavior, and automated verification.

## 2. Considered approaches

### 2.1 Continue expanding `PlayerController`

This is the smallest short-term diff. It would add `gun_weapon`, `staff_weapon`, and `gauntlets_weapon` fields beside the current Sword and Bow fields, then route every input, reset, cancel, modifier, UI snapshot, and fact through more weapon-ID branches.

This approach is rejected. The current controller already owns Sword timing directly while Bow advances charge and cooldown in its own `_process()`. Adding three more special cases would produce multiple action clocks, duplicate cancellation rules, weapon-specific reset gaps, and presentation code that continues to assume Sword.

### 2.2 Shared coordinator plus small mechanism runtimes

One coordinator owns global action phases, buffering, cancel windows, generation tokens, resource commit order, and typed action facts. Each weapon runtime owns only its distinctive mechanics, resources, payload construction, and presentation snapshot. Versioned runtime profiles contain declarative timing, cost, payload, and cue data.

This approach is selected. It preserves one player action authority while keeping each weapon understandable and independently testable.

### 2.3 Fully data-driven behavior graph

A general behavior DSL could encode every weapon action, branch, hit, status, and time interaction. This is rejected for P11. It would create a second scripting language before the five concrete weapons prove which abstractions are stable, and it would make debugging action transactions and cancellation harder.

## 3. Authority and source-conflict decisions

When retained design documents disagree, P11 uses this authority order:

1. Full Product Completion Spec for product identity and non-negotiable scope.
2. This P11 specification for executable architecture and conflict resolutions.
3. Detailed action tables in `docs/3.1combat-system-design.md` for rhythm, frame relationships, and special mechanics.
4. UI/audio language in `docs/5_6_UI美术音效技术设计.md`.
5. Summary DPS tables in `docs/4_角色与数值体系设计.md` as balance targets, not literal runtime constants.

The following conflicts are resolved now:

- Gun is a firearm with ammunition, aimed fire, shotgun fire, reload timing, and burst cycles. The retained “five-tile thrust” summary is historical and does not define the launch Gun.
- Gauntlets use the detailed five-hit chain and separate cross-chain Combo counter. The older fourth-hit multiplier summary does not replace that chain.
- Staff uses elements, mana, ordered spell combinations, projectiles, and zones. Random outcomes use deterministic run-seeded channels.
- Old Q/R examples cannot override current time-skill bindings. Weapon commands use semantic action slots and are remappable.
- Absolute legacy damage numbers do not replace the current `Stats.attack` authority. Profiles store multipliers; simulations tune them against target DPS and risk.

## 4. Milestone isolation

P11 must not silently retune the still-unreleased M1 candidate while authentic human evidence remains `0 / 20`.

Weapon profiles are milestone-aware:

```text
sword_m1_v1         M1
sword_launch_v1     NEXT / LAUNCH / EXPANSION
bow_candidate_v1    NEXT
bow_launch_v1       LAUNCH / EXPANSION
gun_launch_v1       LAUNCH / EXPANSION
staff_launch_v1     LAUNCH / EXPANSION
gauntlets_launch_v1 LAUNCH / EXPANSION
```

The shared runtime may replace implementation plumbing, but `sword_m1_v1` must preserve the verified M1 timing, damage, movement, reward hooks, facts, feedback, room flow, and Quick Start config until an evidence-backed promotion or tuning decision changes it.

Bow remains a clearly labelled candidate in `NEXT`. Gun, Staff, and Gauntlets remain unavailable before `LAUNCH`. Completing their runtime does not leak them into M1 or the P10 Candidate Lab.

## 5. Shared runtime architecture

### 5.1 `WeaponIntentRouter`

The router converts physical and persisted input actions into semantic intents. It owns no gameplay resources and publishes no combat facts.

Final semantic slots are:

```text
weapon_primary
weapon_secondary
weapon_utility
weapon_skill
weapon_ultimate
time_slot_1
time_slot_2
dash
interact
pause
```

The input persistence layer migrates the current `attack`, `heavy_attack`, `ranged_attack`, `time_stop`, `time_rewind`, `time_rift`, and `time_accelerate` bindings into the new semantic slots without losing user remaps. The fixed time action IDs remain accepted by a compatibility adapter for one save/input schema version, while runtime dispatch uses the two equipped slot actions.

Hold/toggle accessibility modes produce the same semantic press, release, and held-frame sequence. A weapon runtime cannot inspect raw keyboard, mouse, or controller events.

### 5.2 `WeaponActionCoordinator`

The coordinator is the only weapon-action writer. It owns:

- current action phase and immutable action token;
- hold duration, windup, active, recovery, resource-action, and channel timing;
- buffer priority and cancel windows;
- movement multiplier;
- atomic resource validation and commit;
- generation invalidation on hitstun, death, rewind safety restore, selection freeze, terminal state, loadout reconfiguration, and new-run reset;
- exactly-once committed facts;
- snapshot and safe restore.

The generic phases are:

```text
READY
HOLD
WINDUP
ACTIVE
RECOVERY
RESOURCE_ACTION
CHANNEL
DASH
TIME_CAST
HITSTUN
DEAD
```

Weapon-specific names such as `GUN_RELOAD` or `GAUNTLETS_PUNCH_4` never enter the global phase enum. They remain `action_id` values inside an immutable action plan.

### 5.3 `WeaponRuntime`

Every runtime implements the same narrow contract:

```gdscript
weapon_id() -> StringName
configure(owner, profile, modifier_state) -> bool
capabilities() -> PackedStringArray
plan_intent(intent, context) -> WeaponActionPlanResult
commit_action(plan, token) -> WeaponCommitResult
on_phase_enter(plan, phase, token) -> Array
cancel_action(token, reason) -> void
finish_action(token) -> void
apply_modifier(effect_id, value) -> bool
reset_runtime_state(reason) -> void
snapshot() -> Dictionary
restore_snapshot(snapshot) -> bool
presentation_snapshot() -> Dictionary
```

`plan_intent()` is read-only. It may reject, but it may not spend ammunition, mana, time energy, cooldown, Combo, or spawn payloads. `commit_action()` performs one atomic transaction after every required payload can be constructed.

### 5.4 Runtime profiles

The Base Pack adds a versioned `weapon_runtime_profile` category. A profile may declare:

- action IDs and activation mode;
- hold thresholds;
- windup, active, recovery, cancel, and buffer frames;
- movement multipliers;
- resource costs and cooldowns;
- payload descriptor IDs;
- hit multipliers and deterministic spread channels;
- status, VFX, audio, animation, camera, and accessibility cue IDs;
- milestone availability and compatibility tags.

Profiles cannot invoke scripts or arbitrary methods. Weapon scripts interpret only approved descriptors and typed handler IDs. ContentRegistry validates every weapon-to-profile reference, action ID, resource ID, cue ID, frame window, payload descriptor, and availability relationship before activation.

### 5.5 Modifier state

`WeaponModifierState` replaces `ItemEffect` branches that directly access `player.sword_weapon` or `player.bow_weapon`. Effect handlers target declared capabilities such as:

```text
weapon.damage
weapon.attack_speed
weapon.charge_rate
weapon.pierce
weapon.ammo_capacity
weapon.reload_window
weapon.mana_max
weapon.combo_timeout
weapon.status_duration
```

Unsupported effects fail closed during content validation. A modifier snapshot is frozen when an action commits so a mid-hit tier change cannot alter the same action.

## 6. Action transaction and fact model

One action follows this order:

1. Normalize semantic intent.
2. Validate equipped weapon, phase, resource, cooldown, availability, and payload descriptors.
3. Build all required payload instances or immutable descriptors.
4. Commit resource changes and action token atomically.
5. Publish exactly one `weapon_action_committed` fact.
6. Enter the committed phase and release payloads at the declared commit frame.
7. Publish hit/resource/status facts from their owning systems without re-publishing the action commit.

P11 replaces `player_attacked` with typed facts:

```text
weapon_action_committed(weapon_id, action_id, token, context)
weapon_resource_changed(weapon_id, resource_id, current, maximum, reason)
weapon_hit_confirmed(weapon_id, action_id, token, target_id, context)
```

The coordinator is the only `weapon_action_committed` publisher. Hitboxes, projectiles, zones, feedback, and weapon runtimes do not publish a second commit. The old `player_attacked` signal may exist only inside an early migration task and is removed before the P11 evidence gate.

Rejection is atomic:

- no resource spend;
- no cooldown;
- no action phase change;
- no projectile, pellet, zone, or hitbox;
- no committed fact;
- no animation, sound, hit pause, or camera feedback that implies success.

## 7. Weapon specifications

### 7.1 Sword

`sword_m1_v1` preserves current M1 behavior. `sword_launch_v1` adds the launch grammar:

- four-hit light chain;
- primary hold/release charge tiers;
- guard, normal block, perfect guard, and counter;
- Sword Intent and counter-chain state;
- weapon skill and ultimate;
- source-aware time marks and zones;
- recovery cancel discipline and Boss-safe poise conversion.

Sword remains the baseline for short, readable commitments. Perfect guard does not create a parallel damage or action clock; it schedules a coordinator-owned counter action.

### 7.2 Bow

`bow_candidate_v1` preserves the P10 candidate. `bow_launch_v1` adds:

- four charge outcomes with charge-hold timeout;
- charge movement penalties and explicit Dash cancel;
- scatter secondary;
- range correction and weak-point rules;
- weapon skill and ultimate;
- deterministic penetration, arrow rain, and time-trail payloads.

Bow charge moves into the coordinator. Bow no longer advances its authoritative charge or cooldown in an independent `_process()` path.

### 7.3 Gun

Gun uses a six-round firearm loop:

- primary hold below 18 frames releases normal fire;
- primary hold at or above 18 frames releases aimed fire;
- secondary commits eight-pellet shotgun fire and atomically costs two rounds;
- utility starts or confirms reload;
- special activates Time Load;
- ultimate commits Void Penetration after its hold/channel requirement.

Reload is 48 frames with half-open boundaries:

```text
[0,8)   locked
[8,40)  Dash-cancellable
[28,36) perfect confirmation window
[40,48) locked completion
```

Normal reload fills to six. Perfect reload immediately fills to seven, grants the free Time Load effect, and enters four frames of recovery. Early or late confirmation does not restart reload and does not partially reward it.

Normal and aimed shots cost one round. Shotgun costs two and rejects entirely at one round. Empty primary intent starts reload only; it cannot shoot and reload in the same transaction. Projectile construction failure leaves ammunition, cooldown, action state, and facts unchanged.

Time Load lasts 300 frames: ammunition cost becomes zero, future action timing gains 40% speed, and committed shots add 15% attack as time damage. The active version costs 25 time energy and starts its cooldown; the free perfect-reload version does not alter the active cooldown.

### 7.4 Staff

Staff uses Mana `100`, regeneration `3 / second`, and an ordered element sequence:

```text
Fire -> Ice -> Lightning -> Fire
```

Primary tap releases the free basic spell. Primary hold to 30 frames commits the current charged element. Utility cycles the element without interrupting a committed action. Special commits Plane Collapse. Ultimate commits Primordial Wrath.

Charged spell costs and identity are:

- Fire: 20 Mana, explosion and source-aware burn.
- Ice: 25 Mana, persistent slow field and Boss-safe freeze conversion.
- Lightning: 18 Mana, deterministic target chain with per-cast target deduplication.

An ordered combination is recorded only after the first charged spell confirms a hit. A different second element must confirm within 300 frames. At second-cast start, base plus possible combination Mana is reserved atomically. If no combination confirms, the extra reservation is refunded. Insufficient total Mana rejects before payload construction and sequence mutation.

Damage may restore Mana at 2%, but each tick/cast has a profile cap so multi-target zones cannot create unbounded resource growth.

All burn, slow, freeze, shock, blind, and zone sources use a shared source-aware `ElementalStatusRuntime`. Chrono Warden converts hard freeze to a deterministic short action delay or exposed-window extension; it never receives a random miss or broken behavior clock.

### 7.5 Gauntlets

Gauntlets separate two states:

```text
chain_step   0..4, chooses the next punch
combo_count  0..N, grows only from confirmed eligible hits
```

The five-hit chain uses the detailed windup/active/recovery values from the combat design. Windup and active frames cannot be skipped by Dash. Dash and time skills may execute only after the recovery cancel frame opens.

Primary advances the five-hit chain. Primary hold commits charged heavy. An attack within eight frames after Dash completion commits Dodge Counter. Special commits Space-Time Shatter. Ultimate commits Primordial Collapse Punch.

Combo rules are:

- light confirmed hit `+1`;
- charged heavy `+3`;
- Dodge Counter `+5`;
- no eligible hit for 120 frames resets Combo;
- real player damage resets Combo;
- Dash does not reset Combo;
- repeated target entry for the same action token cannot add Combo twice;
- extra time damage, shockwaves, or Accelerate echoes cannot recursively add Combo, energy, or Stop extension.

Combo tiers snapshot attack-speed, critical, time-damage, and energy-return modifiers for future actions. The 30+ slow aura is source-aware and removed exactly when the tier, loadout, run, or player lifetime ends.

Ordinary enemies may map launch effects to airborne behavior later in P11. Chrono Warden maps launch to controlled displacement or poise/stagger contribution and never enters an invalid airborne state.

## 8. Time interactions

Each weapon implements one explicit interaction with each of the four equipped time abilities. Interactions consume immutable time context and cannot rewrite `TimeManager` export values globally.

| Weapon | Stop | Rewind | Accelerate | Rift |
|---|---|---|---|---|
| Sword | judgment/conversion window | post-rewind empowered strike | faster future sword plans | guard/zone conversion |
| Bow | stopped-target full-charge burst | echo arrows after rewind | faster charge and recovery | penetration/zone detonation |
| Gun | aimed-shot time burst | next shot ammo-free and empowered | shorter recovery and bounded ammo efficiency | projectile/trail spatial interaction |
| Staff | larger/longer controlled field | free empowered charged cast window | 15-frame charge and reduced Mana | larger combination area plus time damage |
| Gauntlets | eligible hits extend one Stop by at most 30 frames | empowered Dodge Counter window | each third primary hit creates one non-recursive echo | high-Combo time modifier and spatial control |

Every interaction uses source IDs, generation tokens, explicit maximums, and cleanup tests. Time effects never become unbounded through multi-hit projectiles, zones, pellets, Combo echoes, or status ticks.

## 9. Boss interaction contract

Chrono Warden is the first executable Boss contract for all five weapons.

Each weapon must demonstrate:

- a readable conversion window during Boss recovery/exposed state;
- no interruption of an already committed Boss active attack unless the Boss contract explicitly allows it;
- time resistance preserved;
- projectile, pellet, chain, and zone target deduplication;
- controlled poise or exposure contribution instead of unsupported launch/freeze behavior;
- cleanup on phase transition, death, room disposal, and run terminal state.

Later floor Bosses must implement the same public resistance/poise/status boundary rather than adding weapon-specific exceptions.

## 10. Weapon ViewState and HUD

`RunViewState` advances with one validated `weapon_state` union:

```text
weapon_id
action_id
phase
meter_kind
meter_current
meter_max
status_id
status_stacks
status_remaining
secondary_id
secondary_value
```

Allowed meter mappings are:

```text
sword      guard / charge / counter
bow        charge / hold
gun        ammo / reload
staff      mana / element / sequence
gauntlets  combo / timeout / counter
```

Unknown weapon/meter/status combinations, negative or non-finite values, impossible maximums, and legacy weapon-specific top-level fields fail at the ViewState boundary.

The 640×360 HUD uses one compact weapon panel. It shows the current weapon name, one primary meter, and one short status line. It does not show internal action IDs. Gauntlets Combo appears at `5+`, Gun shows `current / maximum`, Staff shows Mana and element, Bow shows charge, and Sword shows guard/counter readiness.

Locale changes re-render cached state. Color is always paired with shape, text, motion, or sound. High-frequency Combo, perfect reload, charge, and elemental feedback respect shake, flash, contrast, text-size, subtitle, and volume settings.

## 11. Presentation and audio

Combat feedback routes by `weapon_id + action_id + impact_tier`, not by a universal Sword fallback.

Pixel Proxy reads facing and pose from the active weapon presentation snapshot. It cannot find a child named `SwordWeapon` to infer every weapon's attack direction.

Each weapon has a restrained proxy cue set:

- Sword: arcs, charge weight, guard flash, counter line.
- Bow: bow tension, charge tiers, arrow trail, scatter fan.
- Gun: muzzle flash, tracer, reload marker, perfect ring, Time Load tint.
- Staff: element orb, cast circle, zone boundary, combination signature.
- Gauntlets: alternating fists, punch wind, Combo aura, counter speed line.

Audio synthesis exposes distinct weapon/action cue IDs. A rejected action is silent except for an explicit accessible rejection cue. Ordinary attack feedback cannot play `sword_swing` for Gun, Staff, or Gauntlets.

## 12. Determinism, snapshot, and reset

All spread, critical, chain-target ordering, elemental selection, zone ticks, and presentation-independent variation derive from the run seed and stable channel/context identifiers.

Coordinator and weapon snapshots include enough state to verify or safely refuse restore:

- profile/version and weapon ID;
- action generation/token, phase, frame, and immutable committed plan;
- resources, cooldowns, hold duration, active buffs, and source IDs;
- weapon-specific chain, sequence, reload, element, Combo, or status state;
- deterministic RNG checkpoints where a committed action has pending outcomes.

Rewind does not restore spent ammunition, Mana, time energy, cooldowns, enemy damage, or world consequences unless the authoritative Rewind contract explicitly includes them. Unsafe mid-action snapshots restore to a documented safe state and invalidate stale callbacks.

Death, selection freeze, terminal state, loadout reconfiguration, new run, and scene disposal clear every transient hitbox, projectile transaction, aim line, reload confirmation, spell reservation, zone source, Combo aura, charge, channel, and presentation loop.

## 13. Verification matrix

P11 requires:

1. Profile/schema contracts for five weapon IDs, versioning, references, actions, resources, cues, frame windows, payload descriptors, and milestone availability.
2. Parameterized runtime contracts for read-only plan, atomic commit, cancel, finish, stale generation, reset, snapshot round-trip, modifier capability, and exactly-once facts.
3. Sword M1 parity tests proving the plumbing migration does not change the certified slice.
4. Bow candidate parity tests before enabling its launch profile.
5. Gun boundary tests for hold `17/18`, ammo `0/1/2/6/7`, reload `7/8/27/28/35/36/39/40/48`, active/free Time Load, and ultimate hold `59/60`.
6. Staff tests for Mana bounds, atomic combination reservation/refund, six ordered combinations, same-element and timeout rejection, deterministic Lightning chain, status overlap, zone cleanup, and Boss conversions.
7. Gauntlets tests for five chain steps, chain/Combo separation, tier boundaries `4/5`, `9/10`, `14/15`, `19/20`, `29/30`, timeout, damage reset, Dodge Counter `7/8/9`, non-recursive echoes, and Boss poise mapping.
8. Input migration, keyboard/mouse, controller, hold/toggle, remap, conflict detection, glyph, and persisted-profile tests.
9. HUD schema, localization, 640×360, 1280×720, 1920×1080, and ultrawide safe-frame tests.
10. Feedback tests proving correct weapon/action animation, VFX, audio, camera, flash, and accessibility routing without duplicate cues.
11. Chrono Warden integration tests for all five weapons and every declared resistance/status conversion.
12. A deterministic `5 weapons × 6 legal time pairs = 30` Wanderer smoke matrix. Each combination starts, commits representative weapon actions and both time abilities, renders valid ViewState, resets cleanly, and produces the same terminal summary for the same seed.
13. Thirty-seed action simulations that report DPS, risk uptime, resource starvation, burst, area coverage, status uptime, perfect-reload value, Staff combination frequency, and Gauntlets Combo retention.
14. Full repository validation, leak/error scanning, documentation evidence, and clean-checkout reproducibility.

Scene-test counts are not line coverage. GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` until a real provider is integrated.

## 14. Delivery decomposition

P11 is implemented as independently reviewable gates:

1. **P11A Shared authority:** ADR, semantic input contract, runtime-profile schema, coordinator, modifier state, facts, and failing shared contracts.
2. **P11B Sword migration:** `sword_m1_v1` parity, launch Sword profile, feedback migration, and removal of Sword-specific controller ownership.
3. **P11C Bow migration:** P10 candidate parity, launch Bow profile, coordinator-owned charge, scatter/skill/ultimate, and Bow time interactions.
4. **P11D Gun:** ammunition, three attacks, reload/perfect reload, Time Load, ultimate, projectile service, HUD, feedback, time and Boss interactions.
5. **P11E Staff:** Mana, elements, charged spells, ordered combinations, elemental status runtime, zones, skill/ultimate, HUD, feedback, time and Boss interactions.
6. **P11F Gauntlets:** five-hit chain, Combo state, heavy, Dodge Counter, skill/ultimate, poise mapping, HUD, feedback, time and Boss interactions.
7. **P11G Cross-weapon systems:** item/modifier hooks, input migration completion, removal of legacy weapon facts/branches, presentation/accessibility, snapshot/reset, and deterministic simulation.
8. **P11H Certification:** 30 loadout matrix, full validation, evidence record, historical plan conversion, and retention review.

Shared files, EventBus signals, input contracts, runtime profiles, PlayerController, PlayerActionState, Player scene assembly, HUD contracts, Base Pack manifest, and feedback routers have one integration owner at a time. Weapon-specific runtime, projectile, zone, and focused test files may proceed in parallel after P11A freezes their interfaces.

## 15. P11 exit gate

P11 is locally complete only when:

- all five weapons are usable through the same coordinator without weapon-specific controller action ownership;
- M1 Sword and P10 Bow candidate parity gates pass;
- Gun, Staff, and Gauntlets are complete at their allowed milestones and remain unavailable earlier;
- every weapon has primary, secondary, utility where applicable, skill, ultimate, resource/rhythm state, item hooks, four time interactions, Chrono Warden interaction, HUD, animation, VFX, audio, controller, accessibility, snapshot, reset, and cleanup;
- `player_attacked` and presentation Sword fallbacks are retired;
- the 30 weapon/time-loadout matrix and deterministic simulations pass;
- full repository validation passes with only registered warnings;
- formal M1 remains `M1 Candidate — External Validation Pending`, authentic human evidence remains `0 / 20`, and no weapon is falsely described as externally validated, published, or product-complete.
