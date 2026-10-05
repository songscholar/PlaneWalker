# Plane Walker Full Product Completion Design

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: Full-product scope, architecture, and completion contract
- Applies To: P0–P9 foundation, Wave 4A–4D, formal M1 release, and all Next/Launch/Expansion delivery
- Implementation Status: Active; P11 five weapons, P12 five characters and P13 complete Launch pools are locally certified. P14 native dungeon panels, events and physical Save/Replay have focused evidence. P15 production native encounters, five Boss foundations, Time Watch and live combat checkpoint/migration have focused evidence; remaining native species/affixes and Boss arena constructs continue. P16 Main Hub/meta/training/tutorial, narrative/endings and active native save recovery are integrated with focused verification. P17 raster assets/music, P18 local Mod/DLC management and P20A build sharing are verified locally; P20B local records are in progress. Expansion modes, replay productization, cosmetics and additional authored content remain. Full clean-checkout validation, real line coverage, retained platform exports and complete gameplay certification remain pending.
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/0_深度收敛与系统职责设计.md`
- Supersedes: `docs/superpowers/specs/2026-09-28-plane-walker-staged-development-design.md` for execution order and terminal scope
- Preserves: All verified Wave 0/1, Wave 2, Wave 3A, and Wave 3B contracts and regression evidence
- Last Verified: 2026-10-05
- Contract References: `AGENTS.md`, future approved ADRs, `docs/contracts/`, current implementation plans

## 1. Decision

Plane Walker will be delivered as one continuous full-product program. The program does not terminate at M1 and does not remove previously designed content to reduce scope.

The required sequence is:

1. Establish a reproducible foundation through P0–P9.
2. Complete Wave 4A, 4B, 4C, and 4D.
3. Produce the formal M1 release decision from repository evidence plus authentic human-playtest evidence.
4. Promote either Bow or one third time ability to Current using the recorded M1 evidence.
5. Continue without a new authorization stop through Next, Launch, and Expansion.
6. Finish the five characters, five weapons, four time abilities, five floors, five bosses, Hub, meta progression, full narrative, endings, replay, rankings, Mod support, cosmetics, content-pack/DLC infrastructure, and expansion modes.

M1 is a quality gate and learning checkpoint, not the final product boundary. A failure at an M1 gate triggers repair and re-verification; it does not authorize deleting the full-product scope.

## 2. Product Promise

The player observes commitments, chooses when to commit, manipulates time, and converts the resulting window into damage, position, defense, or a deliberate risk-reward trade.

Every major feature must reinforce at least one of four depth pillars:

- **Time mastery:** time abilities change opportunity, pathing, or risk rather than acting as interchangeable panic buttons.
- **Weapon rhythm:** every weapon asks a distinct execution question and retains its identity after upgrades.
- **Build drafting:** a run develops a recognizable direction early and presents meaningful pivots, payoffs, and safety choices.
- **Risk conversion:** curses, low health, contracts, routes, and resource spending exchange safety for a visible tactical benefit.

The product is offline-first. Online or platform services enhance the experience but never make the complete single-player game unavailable.

## 3. Non-Negotiable Scope

### 3.1 Characters

The authoritative launch character set contains five playable characters:

| ID | English name | Chinese working name | Combat identity |
|---|---|---|---|
| `wanderer` | Wanderer | 行者 | Balanced baseline; converts clear timing into reliable sword and time-skill value |
| `time_guardian` | Time Guardian | 时之守护者 | Defensive timing, parry, ward, and cooldown control |
| `void_walker` | Void Walker | 虚空行者 | Low-health pressure, spatial risk, and void conversion |
| `primordial_knight` | Primordial Knight | 原初骑士 | Heavy commitments, armor windows, and deliberate burst |
| `time_lord` | Time Lord | 时之领主 | High-complexity time-resource routing and multi-ability interactions |

Characters may equip every launch weapon. Character identity is expressed through passive rules, action modifiers, starting resources, and character talent hooks; it may not be implemented as a simple damage multiplier skin.

### 3.2 Weapons

The authoritative launch weapon set contains:

| ID | Weapon | Rhythm question |
|---|---|---|
| `sword` | Sword / 剑 | Can the player use the correct short commitment and counter window? |
| `bow` | Bow / 弓 | Can the player trade position and time for charge, precision, and penetration? |
| `gun` | Gun / 枪 | Can the player manage ammunition, reload timing, and burst cycles? |
| `staff` | Staff / 杖 | Can the player sequence spells and control areas? |
| `gauntlets` | Gauntlets / 拳套 | Can the player sustain close-range pressure without losing escape discipline? |

Every weapon requires a complete input path, action-state integration, animation/VFX/audio language, item hooks, controller mapping, tests, and at least one Boss interaction.

### 3.3 Time abilities

The authoritative set contains:

| ID | Ability | Tactical grammar |
|---|---|---|
| `stop` | Time Stop / 时间停止 | Alters enemy and projectile time to create a conversion window |
| `rewind` | Rewind / 时间回溯 | Alters player history while preserving resource cost and world consequences |
| `accelerate` | Accelerate / 时间加速 | Compresses the player's rhythm in exchange for execution pressure |
| `rift` | Rift / 时间裂隙 | Alters paths, zones, projectiles, and spatial relationships |

Each run equips exactly two different time abilities. Four abilities therefore create six legal unordered loadouts. Five characters × five weapons × six time loadouts create **150 required loadout smoke combinations**.

### 3.4 Launch archetypes

These eight IDs are the only authoritative top-level launch archetypes:

| ID | Display concept | Core loop |
|---|---|---|
| `freeze_burst` | 冻结爆发 | Create a stop/slow window and convert it into concentrated damage |
| `rewind_echo` | 回溯残影 | Plan a rewind path and turn history into damage, bait, or defense |
| `rift_trap` | 裂隙陷阱 | Shape routes and projectile fields around persistent spatial control |
| `accelerated_combo` | 加速连击 | Maintain a compressed action sequence for escalating payoff |
| `low_hp_void` | 低血虚无 | Control a dangerous health threshold to unlock void benefits |
| `perfect_guard` | 完美格挡 | Convert precise defense into tempo, resources, and counters |
| `piercing_barrage` | 穿透弹幕 | Align enemies, weak points, and ammunition for penetration chains |
| `echo_legion` | 残影军团 | Use echoes or summons to repeat actions and manipulate attention |

Terms such as `heavy_cleave`, `evasive_guard`, `reload_burst`, and `area_control` are mechanic tags. They may support an archetype but may not silently create competing top-level archetype taxonomies.

### 3.5 Launch content counts

| Content type | Launch requirement | Expansion floor |
|---|---:|---:|
| Passive items | 42 | May grow through versioned packs |
| Active items | 8 | May grow through versioned packs |
| Total items | 50 | No arbitrary maximum |
| Blessings | 28 | Versioned additions allowed |
| Curses | 18 | Versioned additions allowed |
| Run talents | 15 | Five routes × three core choices |
| Ordinary/elite enemy definitions | 22 | +5 Expansion enemies minimum |
| Floor bosses | 5 | Challenge variants and Expansion bosses added separately |
| Room templates | 30 | Ten combat, five elite, three treasure, two shop, three event, five Boss, two rest |
| Regular events | 15 | Versioned additions allowed |
| Special events | 3 | Narrative or cross-floor events |
| Merchant identities | 5 | Each has distinct inventory and trade rule |
| Floors | 5 | One visual/mechanical identity and one Boss per floor |

Every item, blessing, curse, talent, enemy, room, event, merchant, character, weapon, ability, and Boss is a versioned content definition with stable ID, localization keys, availability, compatibility tags, and validation rules.

## 4. Run and Progression Structure

### 4.1 M1

M1 remains the verified five-room slice with Wanderer, Sword, Time Stop, Time Rewind, three build directions, three normal enemies, one elite pattern, and the Chrono Warden. It proves architecture, feel, readability, selection safety, restart speed, and production pipeline.

Wave 4A–4D are mandatory M1 completion work, using the owner's exact scope:

- **Wave 4A — Localization/data baseline and playtest recording:** close and commit the existing localization and data changes, establish the clean import/build/test path, and add the schema and tooling used to record playtest sessions and evidence.
- **Wave 4B — Encounter mechanics completion:** implement the Rewind Echo afterimage, telegraphs for every Boss attack, active elite mechanics, and the authored five-room encounter configuration with regression tests.
- **Wave 4C — Pixel presentation and combat feedback:** replace temporary presentation with the approved Pixel Proxy language, complete core animations, integrate combat audio, and finish hit, danger, time-power, camera, VFX, and UI feedback.
- **Wave 4D — Stability, human playtest, tuning, and release decision:** validate thirty deterministic seeds, import and analyze twenty authentic external playthroughs, tune values from the recorded evidence, repair regressions, and produce the formal M1 Go/No-Go report.

Automated agents must never fabricate human sessions. If twenty real external playthroughs have not been supplied, the repository must contain the complete toolchain, protocol, sample fixture explicitly marked synthetic, report template, and import validation. The release state remains `M1 Candidate — External Validation Pending`; the program may continue building authorized later scope, but it may not claim the human-evidence Gate passed. When real sessions are imported, the same deterministic report pipeline produces the formal decision.

### 4.2 Post-M1 promotion

After M1 evidence exists, exactly one primary complexity variable is promoted first:

- Bow, or
- Time Rift, or
- Time Accelerate.

The choice is evidence-driven. The promotion score uses M1 build diversity, ranged-pressure failures, time-skill comprehension, input load, completion time, and player demand. The decision and raw metrics are recorded in an ADR. If human evidence is pending, implementation may prepare all three behind availability flags, but only the conservative highest-evidence option is enabled as Current.

### 4.3 Launch run

The launch run contains five floors, each with six to nine rooms, a distinct environmental rule, at least three encounter mixes, route choices, economy opportunities, narrative beats, and a floor Boss. Target successful-run duration is 30–45 minutes. Difficulty comes from readable combinations and resource decisions rather than untelegraphed contact damage or health inflation.

Build direction should be recognizable by the end of floor two and deliberately strengthened or pivoted from floor three onward. Bosses test the player's weapon rhythm, time loadout, build identity, and spatial awareness without broadly nullifying those systems.

## 5. Hub, Meta, Narrative, and Endings

The Hub is implemented as three streamed districts rather than one oversized scene:

1. **Council district:** run launch, mission/narrative council, archive, accessibility/tutorial recall.
2. **Craft district:** forge, equipment and loadout management, training, build library.
3. **Rift district:** merchants, gallery/cosmetics, challenge modes, rankings/replay access, expansion gateway.

Together the districts expose all nine designed Hub functions while keeping load time, navigation, controller focus, and pixel composition manageable.

Meta progression prioritizes option unlocks, information, rerolls, training, collection, and route access. Direct permanent combat power follows the limits in `docs/0_深度收敛与系统职责设计.md`; it must not become the main reason a run is winnable.

The full narrative requires:

- onboarding and first-run story;
- five floor arcs and five Boss resolutions;
- Hub NPC progression and relationship states;
- discoverable records and event outcomes;
- main ending, faction/choice variants, and hidden ending conditions;
- localization-complete dialogue and ending credits;
- deterministic save flags with migration tests.

## 6. Modes and Expansion Features

The continuous program includes:

- Boss Rush with validated loadout presets and timing categories;
- daily challenge with offline seed derivation and optional provider-backed submission;
- authored challenge sets;
- endless mode with explicit scaling budgets and run-summary checkpoints;
- replay recording, playback, validation, seeking, sharing/export adapter, and compatibility/version refusal;
- offline local rankings plus optional provider-backed global/friend boards;
- data-only first-party Mod packages, validation, compatibility, safe enable/disable, and save isolation;
- cosmetics collection, loadout preview, unlock routes, and free in-game acquisition;
- versioned first-party content packs used by base game, updates, and DLC;
- DLC discovery and entitlement adapters with offline development fixtures.

Paid gacha is not a product requirement. Real-money probability pools, currency purchases, sale timers, and monetized pity systems remain behind a separate Commercial Decision Gate. Neutral interfaces and free cosmetic collection are in scope.

## 7. Target Architecture

### 7.1 Authoritative runtime boundaries

- `RunOrchestrator` is the only writer of run phase.
- One authoritative RunState owns run identity, seed, room, build, resources, selection, terminal state, and revision.
- Presentation receives immutable/deep-copied ViewState and emits intents; it does not mutate domain state.
- Gameplay facts are published once through typed signals. Compatibility publication is temporary, measured, and removed after parity.
- Gameplay randomness derives from run seed plus stable channel/context identifiers. Presentation randomness never consumes gameplay RNG.
- JSON/content-pack definitions are the only content source. Legacy hard-coded pools are retired after parity tests.
- Typed effect handlers execute validated definitions; content data may not invoke arbitrary scripts.

### 7.2 Content packs

Base content, first-party updates, Mods, and DLC use the same versioned pack envelope:

```text
pack_id, pack_version, schema_version, game_version_range,
dependencies, load_order, content_manifest, localization_sources,
asset_manifest, integrity_hashes, entitlement_tag
```

The registry validates identity uniqueness, dependency cycles, version compatibility, localization, effect handlers, assets, availability, archetype tags, and cross-references before activation. Failure produces a structured report and disables only the invalid pack when safe.

### 7.3 Save service

Save operations use temp write, integrity verification, backup rotation, and atomic rename. The service supports explicit schema versions, forward-version refusal, ordered migrations, corruption recovery, profile isolation, Mod/content-pack fingerprints, and deterministic fixtures. Optional cloud sync is a provider capability, not the primary save authority.

P2 completed this boundary on 2026-09-29. `SaveService` owns production profile/settings writes, while GameState is a temporary compatibility caller for legacy import and existing settings/profile APIs. P3 `ContentSnapshotProvider` supplies the save-compatible active-pack fingerprint; runtime assembly must inject it without changing the version-1 envelope. P4 removes GameState's run-domain mirrors but retains the SaveService-backed compatibility surface until profile/settings callers move to a dedicated composition boundary.

### 7.4 Platform providers

All platform features use `PlatformProvider` interfaces with an always-available offline implementation:

- identity and display name;
- achievements;
- cloud storage;
- leaderboards;
- friends/presence;
- workshop/content discovery;
- entitlement checks;
- screenshots/share hooks.

Provider failure degrades to local behavior and a clear status message. Core play, saves, replay, Mods, challenges, Hub, and narrative remain available offline.

### 7.5 Replay

Replay is not input-only. A replay stores:

- build/game/content-pack versions;
- run configuration and seed;
- normalized input events with frame index;
- RNG checkpoints;
- periodic authoritative keyframes;
- state hashes;
- pause/scene/selection commands;
- terminal summary.

Playback verifies state hashes, reports the first divergence, may recover from a compatible keyframe for viewing, and refuses unsupported versions without corrupting data.

### 7.6 Mod safety

First-party supported Mods are data-only at initial release. They may add validated content definitions, localization, approved assets, and declarative effects from the handler catalog. Arbitrary GDScript execution is unsupported in ranked/verified play and, if ever exposed for offline experimentation, is isolated behind an explicit unsafe mode with separate saves and disabled online submission.

## 8. Presentation and Accessibility

The visual direction is modern pixel ruins:

- 640×360 logical canvas with integer scaling where display geometry permits;
- 16×16 environment tile basis;
- approximately 32×48 primary actor basis with deliberate exceptions for silhouettes;
- nearest-neighbor sampling and no accidental subpixel shimmer;
- restrained palette per floor with one time-energy accent family;
- shape, motion, sound, and color redundancy for time powers and hostile danger.

Required presentation systems include complete HUD, choice, inventory/build, map, shop, Hub, dialogue, pause/settings, results, replay, ranking, Mod management, challenge, accessibility, credits, and content-pack status views.

Accessibility requires controller-only completion, remapping, focus recovery, hold/toggle alternatives, camera shake control, hit-flash control, readable text scale, high-contrast danger language, color-independent cues, subtitle controls, volume buses, and difficulty-assist disclosure that does not shame the player.

## 9. Foundation Program

The foundation is executed as hard-gated phases:

| Phase | Deliverable | Exit Gate |
|---|---|---|
| P0 | Baseline/checkpoint | Current localization/runtime work is preserved, contract-tested, committed precisely, and reproduced from a clean checkout |
| P1 | Test and CI foundation | One command imports, validates, runs tests, scans logs, and reports honest coverage categories |
| P2 (Completed 2026-09-29) | Atomic SaveService | Atomic write, backups, migrations, corruption recovery, and forward refusal pass destructive-fixture tests |
| P3 (Completed 2026-09-29) | ContentRegistry v2 and effect runtime | JSON/content packs are the only source; schemas, references, handlers, localization, and eligibility validate |
| P4 (Completed 2026-09-29) | Single RunState/RoomRuntime | RunOrchestrator is sole phase writer; mirrored writable state and LegacyRunAdapter are retired after parity |
| P5 (Completed 2026-09-29) | Single event publication | Typed signals publish each fact once; dual publish/subscribe paths are removed |
| P6 (Completed 2026-09-29) | Controller/focus/accessibility | Every current flow completes controller-only and accessibility settings persist |
| P7 | Reproducible exports | Windows, Linux/Steam Deck, and macOS export from a clean checkout with documented toolchain |
| P8 (Completed 2026-09-29) | Documentation governance | README, current specs, contracts, ADRs, historical/archive labels, and link/status validation are complete |
| P9 | Detached-worktree certification | Clean import, tests, coverage report, export, and packaged startup succeed without hidden local state |

P0–P9 are foundation gates for the same continuous product program. They do not replace gameplay/content work; they make later parallel delivery safe and reproducible.

Completion evidence for P2, P3, P4/P5, P6, P8, P10A candidate loadouts, the [P11 five-weapon program](../../current/2026-09-30-p11-five-weapons-evidence.md), the [P12 five-character program](../../current/2026-09-30-p12-five-characters-evidence.md), [P13A Launch archetype authority](../../current/2026-10-01-p13a-launch-archetype-authority-evidence.md), and [P13B complete Launch pools](../../current/2026-10-01-p13b-launch-content-evidence.md) is recorded under `docs/current/`. P7/P9 tooling rejects invalid evidence. Official project-local templates, three development release exports and actual host startup are now available. Supplemental first-import localization classification and real AST line instrumentation have focused tests; the combined immutable-checkout validation, full coverage suite and retained release/startup certification remain active. Later product work continues without weakening those evidence gates or reintroducing GameState run mirrors, generic event publication, or content-registry bypasses.

## 10. Delivery Sequence After Foundation

After P0–P9, work continues in dependency order:

1. Wave 4A–4D and formal M1 decision.
2. Evidence-based Bow/third-time-ability promotion.
3. Four complete time abilities.
4. Five complete weapons — `Completed / Certified 2026-09-30`.
5. Five complete characters and 150 loadout smoke matrix — `Completed / Certified 2026-10-01`.
6. Eight archetype mechanics and the complete launch item/blessing/curse/talent pools — `Completed / Certified 2026-10-01`.
7. Five-floor dungeon, route/economy/events/merchant budgets, and thirty rooms — `Active / P14`.
8. Twenty-two launch enemies, elite affixes, and five bosses.
9. Three-district Hub, meta progression, tutorials, narrative, NPC arcs, and endings.
10. Full art, animation, VFX, audio, music, UI, localization, accessibility, and performance pass.
11. Boss Rush, daily/authored challenges, and endless mode.
12. Replay, ranking, provider integrations, Mod support, operations tooling, cosmetics, and content-pack/DLC delivery.
13. Clean-checkout product certification and release-operation checklist.

P10A completed the canonical `5 / 5 / 4` character, weapon, and time-ability identity catalog, candidate-only Bow/Rift/Accelerate runtime, configuration-driven two-slot HUD, local Candidate Lab, and all six legal time-pair verification on 2026-09-29. This is locally verified preparation for the evidence-based promotion decision. It does not satisfy delivery step 2, change Quick Start, or promote Bow, Rift, or Accelerate to Current; authentic external playtest evidence remains `0 / 20`.

P11A–P11H completed delivery step 4 at implementation commit `01c3712` on 2026-09-30: all five weapons use the shared action authority, the formal Launch Loadout reaches every weapon and legal time pair, deterministic weapon Replay and external-fact validation pass, and the 30-loadout matrix plus synthetic simulation report are locally certified. This does not complete five character-specific gameplay kits, the 150-loadout matrix, full player-facing replay productization, or any later floor, Boss, Hub, narrative, ranking, Mod, or DLC gate. Formal M1 and external export/release boundaries are unchanged.

P12 completed delivery step 5 at implementation commit `e7b1ef9` on 2026-10-01: five complete Launch character runtimes, fifteen character talents, player-facing character UI/feedback, deterministic Replay, all 150 loadouts, 40 talent subsets, 30 pairwise integrations, and two byte-identical 4500-sample reports are locally certified.

P13A completed the authority half of delivery step 6 at implementation commit `efebc11` on 2026-10-01: exactly eight versioned archetype profiles, milestone-aware Registry references and drafts, authoritative three-key/eight-key build domains, Replay-compatible snapshots, strict ViewState projection, and localized HUD identity pass the `156 / 156` scene gate.

P13B completed delivery step 6 at implementation certification commit `9a04639` on 2026-10-01: the exact `50 items / 28 blessings / 18 Launch curses / 15 run talents` pools, `42 passive / 8 active` split, 62-effect catalog, atomic reward transactions, eight active handlers, fifteen data-authoritative talents, Replay schema 6, SaveEnvelope schema 2, two byte-identical 240-sample formation reports, the 150-loadout matrix, and the `168 / 168` repository scene gate are locally certified in `docs/current/2026-10-01-p13b-launch-content-evidence.md`. Formal M1, human-playtest, line-coverage, export, signing, and publication status are unchanged. P14 five-floor dungeon delivery is next and does not claim P15 enemy or Boss behavior completion.

Parallel agents may work on independent lanes, but shared contracts, manifests, autoloads, and assembly scenes have one integration owner.

## 11. Verification Matrix

Completion requires automated and manual evidence at the appropriate layer:

- unit tests for pure domain logic, effects, state machines, economy, save migration, provider fallbacks, and replay codecs;
- contract tests for content, localization, assets, UI ViewState, inputs, packs, Mods, saves, and replays;
- integration tests for run lifecycle, rooms, rewards, Hub, narrative flags, save/load, controller focus, content packs, and optional providers;
- deterministic simulations for encounter budgets, build formation, economy, loadout compatibility, and endless scaling;
- smoke tests for all 150 character/weapon/time-loadout combinations;
- visual/interaction QA at 640×360, 1280×720, 1920×1080, ultrawide safe framing, keyboard/mouse, and controller;
- replay round-trip and divergence tests across supported compatible versions;
- export and packaged-startup checks on Windows, Linux/Steam Deck, and macOS targets;
- authentic human playtest evidence for feel, comprehension, perceived fairness, replay desire, onboarding, and accessibility.

Exit code zero is insufficient. Logs are scanned for parse errors, script errors, assertion failures, orphan nodes, ObjectDB leaks, resources in use, invalid calls, and missing content/localization.

## 12. Product Complete Gate

Plane Walker is product-complete only when all of the following are true:

### Scope

- All five characters, five weapons, four time abilities, six time loadouts, eight archetypes, five floors, five bosses, launch content counts, Hub functions, narrative, endings, modes, replay, rankings, Mod support, cosmetics, and content-pack/DLC infrastructure are present.
- The base game is fully playable offline from first launch through every ending and supported mode.
- Optional online/provider features have tested offline fallback and honest unavailable states.

### Quality

- A clean checkout imports, validates, tests, exports, packages, and starts reproducibly.
- Automated test suites and 150-loadout smoke matrix pass.
- Save migration, corruption recovery, replay validation, content packs, Mods, localization, controller, accessibility, and export gates pass.
- No known critical crash, save loss, progression block, reward duplication, terminal-state reversal, unsafe Mod execution, or unbounded economy exploit remains.
- Performance budgets hold in representative worst-case combat and Hub scenes.

### Experience

- Threats, damage, time effects, rewards, and failure causes are readable without developer explanation.
- Each weapon and time ability has a distinct player-described purpose.
- Each archetype reaches a recognizable loop and can answer every Boss without a mandatory hard counter.
- Onboarding, controller-only use, localization, accessibility, and restart flows are production-complete.

### Evidence and release operations

- Repository evidence identifies exact build, tests, content versions, known limitations, and rollback points.
- Human playtest evidence is authentic and clearly separated from automated simulation.
- Store publication, signing, remote upload, public announcements, purchases, and credential-bound platform configuration are listed as external release operations, never falsely marked complete by repository automation.

## 13. External Execution Boundary

The repository program implements and verifies everything possible without private accounts or public side effects. The following remain external operations:

- conducting and observing real human sessions, obtaining consent, and importing authentic results;
- configuring real Steam/app identities, cloud quotas, leaderboards, Workshop, achievements, friend/presence, entitlements, and store pages;
- purchasing assets, localization, certificates, hosting, analytics, or other paid services;
- signing/notarizing with private identities;
- pushing to remotes, publishing builds, posting announcements, or activating commercial products.

Missing external access never stops in-repository work. Agents implement offline providers, fixtures, import/export formats, validation, dry-run checklists, and report templates, then record the external step.

## 14. Commercial Decision Gate

The following require an explicit later commercial decision and are not activated by this specification:

- paid gacha or any real-money random reward;
- purchasable premium currency;
- DLC price, bundle, discount, preorder, or sale schedule;
- paid battle pass, subscription, or scarcity timer;
- real-money storefront and refund behavior.

Allowed before that decision:

- free cosmetic collection and deterministic unlocks;
- neutral catalog, entitlement, receipt, and content-pack interfaces using offline fixtures;
- first-party DLC-quality content implemented as inactive/versioned packs;
- pricing fields in test fixtures clearly marked non-production and never shown as a live offer.

## 15. Governance

- The executable documentation policy is [Document Governance v1](../../contracts/document-governance-v1.md); accepted architecture and governance decisions are indexed in the [ADR authority chain](../../adrs/README.md).
- `Implemented` means the repository implementation exists but its complete local verification gate has not yet passed.
- `Verified Locally` means the declared repository tests and evidence pass without claiming external publication, platform, commercial, credential-bound, or authentic-human results.
- `External Validation Pending` means repository work may be complete but required human, platform, credential, commercial, signing, export-environment, or publication evidence is still absent.
- `Published` may be used only after the named external artifact or service is actually public and its publication evidence is recorded.
- Every Current implementation plan links to this specification and states its exit Gate.
- Every completed plan becomes Historical with completion commits and preserved regression contracts.
- Product counts, canonical IDs, architecture authorities, M1 evidence criteria, or Product Complete Gate changes require a reviewed update to this file.
- An external task may be pending while repository implementation continues; documentation must distinguish `Implemented`, `Verified Locally`, `External Validation Pending`, and `Published`.
- No document may claim human, platform, commercial, or public-release evidence that was not actually produced.

The offline governance check is:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --baseline tools/document_governance_baseline.json
```
