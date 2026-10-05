# Native UI Finish Design

- Status: Prepared / Authorized scope
- Document Role: Current product UI completion specification
- Authority Level: Below AGENTS.md and the full product completion design
- Applies To: All player-facing native Godot UI and its raster resources
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Implementation Status: Preparation complete; runtime changes wait for the gameplay milestone
- Depends On: [Full product completion design](2026-09-28-plane-walker-full-product-completion-design.md), [UI and art direction](../../5_6_UI美术音效技术设计.md), [native rendered coverage](../plans/2026-10-05-native-rendered-ui-coverage.md)
- Implementation Plan: [Native UI finish plan](../plans/2026-10-06-native-ui-finish.md)
- Exit Gate: Finished native UI, authenticated assets, complete input flows, retained visual matrix and clean exported startup

## 1. Problem and Scope

The current UI exposes most product commands and already has revision checks,
focus recovery, localization and targeted integration evidence. That functional
coverage does not establish finished presentation. Hub functions largely reuse
one scrollable text list; the HUD uses text panels and progress bars; map nodes
are labeled rectangles; results are one multiline label. No shared Theme or
project font resource was found during the 2026-10-06 audit.

This milestone completes the native presentation of existing gameplay and
product flows. It includes resources, layout, interaction feedback, localization,
accessibility, testing, documentation and exported delivery. It does not change
combat rules, content eligibility, currencies, rewards, ranking policy, save
semantics or online authorization. Project standing authorization selects the
design and implementation order; no intermediate design approval is required.

Execution order is strict: finish and retain the gameplay milestone first,
then implement this UI milestone. Preparation may proceed in parallel. The
integration lead must record the gameplay passing evidence and announce the
UI phase before any implementation task in the linked plan starts.

## 2. Chosen Direction

### Alternatives Considered

| Approach | Benefit | Cost | Decision |
|---|---|---|---|
| Theme the current lists | Small changes and immediate consistency | Keeps weak hierarchy and text-heavy product surfaces | Use only as an intermediate compatibility stage |
| Native purpose-built pixel UI | Matches the approved ruins world, preserves Godot input and state contracts, permits measured visual improvement | Requires authored resources and several page layouts | Selected |
| Replace with a web UI or third-party menu framework | Existing component libraries | Introduces a second UI/input stack and migration risk | Excluded from this milestone |

The visual language is modern pixel ruins: readable charcoal stone, pale
carved edges, patinated metal, restrained time-energy accents and recognizable
objects. Environment and character art remain visible where players need
context. Menus use authored bitmap frames and tight hierarchy; they do not
turn every section into a floating card. A panel can frame a modal or a tool;
individual rewards can be cards. Sections inside panels use dividers and
spacing rather than additional boxed panels.

The 2026-04-22 art document remains inspiration, while the newer full-product
specification and this document settle concrete implementation conflicts:
retain the current 640x360 logical basis; use hard edges with 0-2 logical pixel
corners; use an unblurred dark veil; retain two equipped time slots and the
current single authoritative active-item state. Do not implement historical
three-dimensional previews, four-slot skill wheels, two active-item runtime
slots, invented dodge charges, or rewards merely to match old diagrams.

### Palette and Typography

| Token | Value | Role |
|---|---|---|
| ink | `#111619` | Main text backplates |
| stone | `#242d2d` | Stone frame recesses |
| stone_edge | `#697771` | Neutral carved edges |
| bone | `#edf0dc` | Main readable text |
| muted | `#abb8ac` | Secondary text |
| patina | `#79baa1` | Owned/cleared state |
| time | `#61d5e7` | Time resources and current selection |
| brass | `#e5bd69` | Currency and earned rewards |
| danger | `#f07065` | Damage, irreversible cost and failed state |
| ember | `#df9b65` | Forge and weapon resource |
| void | `#b897d7` | Void-specific content, limited accent |

At least three semantic accent families must appear across the UI. No single
blue/purple family dominates every page. Normal text must have at least 4.5:1
contrast; large text and essential icon boundaries at least 3:1. Ownership,
danger, selection and rarity always have a shape, icon or label in addition to
color. Rarity colors keep the current content tiers and add distinct corner
marks; UI does not create new rarity definitions.

Use a committed OFL-1.1 font pair: Noto Sans SC for Chinese and readable body
text, Pixelify Sans for Latin display labels and counters where its glyphs are
available. Godot FontFile fallback is explicit. Every localized code point
must be supported by the committed pair; source download URLs, license text
and SHA-256 are retained. Font absence may use Godot's default during an
intermediate implementation, but cannot pass the milestone exit gate.

Base logical text sizes are 11 for secondary text, 12 for body/control text,
14 for page subheadings and 18 for page titles. Use 10 only for optional
metadata. Numeric counters use tabular or stable-width placement. Typography
does not scale with viewport width. Apply existing `text_scale` once from
AccessibilityRuntime; glyph metrics drive wrapping and minimum sizes.

## 3. Layout and Responsive Rules

- Canonical logical canvas: `640x360`.
- Supported output sizes: `640x360`, `1280x720`, `1920x1080`, `3440x1440`.
- Safe-area inset: 12 logical pixels; 8 for compact HUD elements.
- Spacing scale: 2, 4, 8, 12, 16 logical pixels.
- Normal command height: 28 logical pixels; icon button box: 28x28.
- Icon sizes: 16 for compact controls, 24 for slots, 32 for content, 48 for focused preview.
- Raster frames use nearest sampling, integer-aligned edges and 0-2 logical pixel corners.
- Modal maximum width: 616 logical pixels. Text/details scroll within their own region; command footer stays visible.
- At 1.5 text scale, layouts reflow and can reduce simultaneous rows. They never shrink essential text below its scaled minimum.

Use the project's canvas-items stretch and integer sampling rules. Read actual
logical `Control` bounds after Godot applies its stretch transform; do not add
a second root scaling transform. Ultrawide exposes additional world space and
centers constrained menus. HUD stays on the safe edges, with no stretched
character art or unlimited paragraph widths. Pixel assets keep their authored
aspect ratio. Longer English labels wrap rather than collide with icons.

Use container layouts for menus and stable anchored regions for the HUD.
Hover/focus affects only visual children and never changes track dimensions.
Scrolled controls remain reachable by both device types. Dialogs return focus
to the initiating control by stable action identity when it still exists.

## 4. Resource and Dependency Contract

### Authoritative Presentation Resources

Create `assets/production/ui/manifest.json`, `catalog.json`, `LICENSE.txt`,
`contact_sheet.png`, `frames.png`, `controls.png`, `room_icons.png`,
`time_icons.png`, `weapon_icons.png`, `content_icons.png`, `character_portraits.png`
and `boss_portraits.png`. Use the already-authenticated actor/cosmetic resources
for small animated character previews; larger portraits have their own
authored bitmap silhouettes. Add `assets/production/fonts/manifest.json`,
font binaries and complete upstream OFL texts.

`catalog.json` is the only source of semantic identities, atlas paths and
regions. Its schema id is `plane_walker_ui_catalog_v1`, with `schema_version`
1, `entries` keyed by icon id (`atlas_path`, `region` as four integers), and
`content_icons` mapping content id to existing icon id. The manifest
authenticates its hash and every declared file; gameplay content continues to
live in ContentRegistry. Cover all launch
`icon_id` values for 50 items, 28 blessings, 18 curses and 15 talents, all five
weapons, five characters, five bosses, four time powers, eight archetypes,
nine room types, the nine Hub functions and every toolbar command. Cover
enabled expansion content; unknown data-only Mod identities use one
recognizable missing-art glyph with a retained diagnostic rather than a
blank texture or leaked raw path.

Every content icon has a distinguishable object silhouette and internal
detail. Changing only hue or a border does not make a new icon. A generator
can reuse motif pieces (clock, lens, crystal, rune, shield, weapon, leaf), but
must combine an authored silhouette recipe and a semantic detail for each
identity. Pixel frames have deliberate chipped edges, metal corner fixtures
and sparse dithering. Do not use plain colored blocks as final artwork.

The manifest uses schema id `plane_walker_ui_art_v1`, schema version 1,
`catalog_sha256`, `files`, and `provenance`. Each file records relative path,
image size when raster, sha256, source kind, source path/URL, upstream version,
license, license path and nearest-filter policy when raster. Font manifests
use schema id `plane_walker_ui_fonts_v1`, schema version 1, and `files` with
path, sha256, family, version, source URL, SPDX license and license path.
Reject missing atlas regions,
out-of-bounds crops, zero-alpha glyphs, invalid hashes and undeclared files.
AI-created art records generator/model/prompt and applicable terms without
claiming it was hand drawn or mislabeling it as third-party CC0 art.

### Safe Production Paths

| Capability | Preferred path | Offline/reversible path |
|---|---|---|
| UI/layout/input/motion | Godot 4.6.1 Control, Theme, StyleBoxTexture, AtlasTexture, Tween, AnimationPlayer and FocusCoordinator | Same built-in APIs; no new UI framework |
| PNG composition and contact sheets | Existing pinned `Pillow==12.3.0` in requirements-production-art.txt | Existing project raster encoder for deterministic small sprites |
| Original small pixel assets | Project-authored masks, silhouette recipes and layered bitmap composition | Deterministic checked-in generator, output and hash manifest |
| Portrait or scene source imagery | Image generation via the available imagegen skill only when useful and authorized by existing scope | Authored bitmap art using existing actor/hub palettes and reference sheets |
| Fonts | Official Noto Sans SC and Pixelify Sans repositories, OFL-1.1 | Complete local vendored binaries; no runtime network |

No paid asset/service, credential discovery or public upload is needed. No
Godot addon is required for the UI domain. Verify any dependency version and
license before adding it; keep only the project-scoped tooling needed for the
resource generator. Asset creation happens after the gameplay phase passes.

## 5. Presentation Architecture

Keep domain state independent of nodes. `render(view_state)` remains the
entry point for existing views. Validators still run before presentation;
revision/run/epoch checks and `_submitted` guards retain their behavior.
Commands retain existing signals, argument types, action ids and revisions.
Views never write Profile, RunState, inventory, currency or save files.

Boss Rush, daily, authored challenges and endless currently build their own
combat chrome in their coordinators; they do not all instantiate CombatHudV2.
Task 8 must explicitly replace that presentation with the shared resource
components and a common mode HUD scene. A pure ModeCombatHudProjector consumes
the existing mode metadata, `Player.get_player_ui_snapshot()` and accepted
Boss display facts, then validates a versioned read-only ModeCombatHudViewState.
It does not fabricate a normal dungeon RunState or change save/replay schemas.
Retain each coordinator's pause/active/pending-save rules and timed run identity.
Completing only the primary CombatHudV2 scene cannot complete this milestone.

Shared assets enter through `UiArtCatalog`; shared `Theme` enters through
`UiTheme`; reusable visual behavior enters through small resource-slot,
icon-command, currency, tooltip, frame and motion components. These components
consume already projected values and have no gameplay service dependency.
Split Hub page layout builders from HubPanelView only where it removes its
current function-specific branching. HubPanelView still owns commands, draft
fields and focus scope. Preserve public controls or provide explicit aliases
needed by existing production consumers and tests during replacement.

Current RunViewState already supplies HP/energy, time slots, character/weapon
unions, one active item, build ids/scores, Boss state and optional validated
dungeon_state. Use those facts. Resolve ids to display art/text via the immutable
registry snapshot/catalog. Never infer unknown room contents from hidden data.
Where a historical drawing calls for unavailable facts, omit that indicator
or add a separately reviewed versioned read-only projection with save/replay
parity tests. This milestone does not require a new projection for dodge
charges, unprojected armor, a second active slot or non-authored status values.

## 6. Surface Specifications

| Surface | Finished composition and content | Preserved interaction |
|---|---|---|
| Hub districts and chrome | Full readable raster environment; short district label; compact currency pair; NPC function glyphs; restrained travel/settings toolbar; active destination marker | Walk/interact, district travel, settings focus restoration |
| Gateway/loadout | Five character portrait selectors; five weapon glyph selectors; focused actor preview; two equipped time slots; legal time-pair selector; chosen kit summary; normal expedition as primary command; modes as secondary tab/list | Existing select_loadout/launch/resume signals and eligibility reasons |
| Council/meta progression | Branch tracks with linked node glyphs and ownership marks; focused detail shows cost, prerequisites and exact effect text; purchase command remains visible | Existing meta_unlock command; no client-side cost recomputation |
| Forge | Five-weapon selector; focused weapon on anvil bitmap; level pips and authored attack bonus; separate enchantment preferences and temper-payment options | forge_upgrade/enchant_preference/void_temper payloads unchanged |
| Meditation/builds | Named saved-build rows with character/weapon/time glyphs; focused summary; save/import controls; compact copy/paste/export/delete toolbar | Existing draft preservation, validated share codec and clipboard availability |
| Archive/gallery/mirror | Category tabs, artifact/appearance grid with locked silhouettes and selected details; existing cosmetic raster preview; local records as aligned rows | Existing claim/equip, replay, platform and provider refresh commands |
| Combat HUD | Compact lower-edge vitals, character glyph, weapon slot, two time slots and one active-item slot; numerical resource text; side build/status glyph strip; upper Boss strip with phase pips; small upper map inset when dungeon_state exists | Existing show_hud/pause/phase rules; HUD remains nonblocking |
| Inventory/build inspection | Existing build ids grouped into items/blessings/curses/talents; eight archetype score bars; selected exact name/description; counts and owned duplicate stacks | Read-only state from current projection; uses existing pause/inspection entry point or adds a presentation-only tab to pause |
| Reward choice | Two/three stable item frames with 32px art, name, rarity shape, exact effect description, archetype relation and replacement information; footer commands always reachable | Selection/skip/replacement action ids and mandatory-choice rules unchanged |
| Map/routes | Room-type glyph graph; visible knowledge states and selected path; focused room detail; route actions adjacent to graph; no hidden content leakage | Existing route_requested edge id/revision; map focus is inspection-only |
| Shop/rest/room interactions | Merchant/room bitmap context, coherent offer shelves, exact prices, sold/disabled reasons; services in separate unboxed section; currency footer | Existing merchant_action_requested/leave/room_choice payloads |
| Events | Authored event-vignette bitmap strip, body text, cost/reward preview, choices; result/pending encounter/reward stages clearly distinct | Existing event_option/dismiss/event_reward signals and precedence |
| Narrative/endings/credits | Character/subject portrait or relevant scene art, readable dialogue strip; response list; archive unlock/ending marks; credits from actual license sources | Existing action ids, close_available policy and authored text; reveal is skippable |
| Results/floor transition | Outcome heading, character/weapon art, reached floor, time/kills, graphical earned/build summary; settlement retry/return footer; next-floor art and command | One terminal publication; save retry and Profile return semantics unchanged |
| Pause/settings/remapping | Compact pause commands and read-only build tab; grouped settings tabs; proper sliders/toggles/options; mapped device glyphs; capture/conflict prompts; language and text scale preview | Existing persistence/remap conflict/reset/apply/cancel; no unbound commands |
| Tutorial/training | Lesson checklist with glyphs and progress; mapped input glyphs; small hint strip; training selectors plus original play/pause/reset/back icons and live resource display | Actual InputMap and observer progress; existing skip/guided/training rules |
| Boss Rush/daily/authored/endless | Mode-specific artwork and objective; fixed-loadout strip; five-Boss/three-stage track or endless cycle; records aligned; attempt/countdown/assist/practice labels; carried reward choices use reward component | Existing start/continue/resume/next/retry/reload and terminal return rules |
| Challenge rewards | Earned marks and title/item glyphs; equipped states; effect numbers and eligibility; claim/sync actions | Existing authoritative claim and equip operations |
| Replay | Unframed real gameplay viewport; recording list with kit glyphs and duration/status; stable timeline; bitmap play/pause/import/export/delete icons and speed menu | Existing seek/playback/router, diverged/missing states and delete confirmation |
| Local ranking/platform | Restrained section tabs; account/offline status; aligned record columns; storage/content/sharing rows and actual screenshot preview where available | Existing provider results/capabilities; local/offline labels remain honest |
| Mod/content packs | Installed-pack rows with authored emblem; enabled/owned/quarantined/locked states; dependencies and diagnostic detail; install/refresh controls and file dialog | Current data-only policy, mutation lock, separate save domain and unavailable entitlements |

Combat HUD slots are graphical rather than paragraph-shaped panels. Keep the
central 60% width and middle 50% height free of HUD text in combat, except
intentional transient prompts and world labels. At 640x360, vitals occupy at
most 220x46 and the action strip at most 248x44; Boss region at most 344x34.
At 1.5 text scale, supplementary labels move into tooltips/inspection; numeric
resources and critical readiness remain visible. Every used slot retains a
stable frame whether ready or cooling down.

Room names appear briefly after transition; time/currency/map use compact
placement. Add the inset only when validated dungeon_state is supplied.
Display blessings/curses/items using actual build ids; no invented active
buff duration is shown. High-risk choices and health-cost services get an
icon plus explicit cost text without a new confirmation step that changes
existing product flow.

## 7. Motion, Feedback and Accessibility

| Feedback | Standard | Reduced-motion behavior |
|---|---|---|
| Focus/hover | Immediate 1px glyph/edge change; optional 2px visual-only shift over 80ms | Static edge and glyph |
| Panel open/close | 120ms veil/fade and 4px visual-only travel | Immediate visibility, focus ready in the same frame |
| Choice reveal/accepted action | 80ms stagger, <=160ms edge emphasis; no delayed command dispatch | Static accepted/disabled state |
| HP loss | Instant foreground value; 240ms delayed-loss trail after 80ms hold | Instant value and static damage mark for 200ms |
| Heal/ready state | <=120ms restrained edge emphasis | Static plus/ready glyph |
| Low HP | <=1Hz small edge/pip emphasis, no full-screen strobe | Static danger shape and exact number |
| Dialogue | Optional 30 glyph/s reveal, one input reveals all, next input continues | Full text immediately |
| Replay movement | Existing playback | UI motion reduced; recorded world semantics unchanged |

Respect existing reduced_motion, screen-shake/hit-flash/danger, subtitle,
volume, text_scale and assist policies. Use AccessibilityRuntime hooks for
live changes. Disable decorative looping particles in reduced motion. Apply
UI animation in presentation only; never hold gameplay progress or save
completion behind animation duration. Kill owned tweens when a view closes,
re-renders, loses epoch or exits; restore stable properties before reuse.

Focus is visible with a non-color outline/bracket. Tooltips open on hover or
focused inspection, contain exact display content and remain inside safe
bounds. Familiar tool commands use bitmap icons with localized tooltips;
clear primary commands may use icon plus text. Existing keyboard/mouse/
controller event-shaped test coverage remains; physical-controller evidence
is recorded separately and is not claimed without an attached device.

## 8. Verification and Completion Criteria

Each implementation task defines a failing test before changing behavior.
Tests assert user-visible contracts or resource correctness, not a mirrored
copy of the implementation. Preserve current scene/integration suites. New
geometry checks include the visible portion of scrolled children, tooltip
placement, icon frames, command footer access and known focus destinations.

Create a registry of these 49 minimum retained states:

| Group | State ids | Count |
|---|---|---:|
| HUD | combat, low_hp, boss, active_item_cooldown, build_status, map_inset | 6 |
| Hub | council_district, craft_district, rift_district, council, gateway, forge, meditation, archive, gallery, mirror, training_function, merchant_function | 12 |
| Run panels | choice_item, choice_blessing, choice_curse, route_map, shop, event, narrative | 7 |
| Progress/result | floor_transition, defeat, victory, ending_credits | 4 |
| Settings | pause, settings, remap_capture, remap_conflict | 4 |
| Onboarding | tutorial_list, tutorial_hint, training_arena | 3 |
| Modes | boss_rush, stage_clear, daily, authored, endless, mode_result, challenge_rewards | 7 |
| Replay | replay_empty, replay_playback | 2 |
| Platform/content | platform, mods, platform_offline, mod_rejected | 4 |
| Total | Unique ids prefixed by group in the registry | 49 |

For each state retain native OpenGL screenshots at all four resolutions,
`zh_CN` and `en`, and text scales `1.0` and `1.5`: exactly 784 minimum images.
Additional states may be retained without redefining the minimum. Render each
state from actual production views/coordinators; deterministic assisted
fixtures are labeled visual evidence and never claimed as combat victory.
At least HUD, gateway, choices, map, results, settings and replay have separate
reduced-motion and high-contrast representative captures.

Automated assertions cover nonblank raster, expected icon/font assets,
text bounds, safe visible focus controls, stable slots, color-independent
states, no hidden-map leakage and no presentation mutation of snapshots.
Manual inspection covers readable text, recognizable art, semantic emphasis,
spacing, unclipped details and coherent style at minimum-size/large-text and
ultrawide; inspect all 49 states in both challenging configurations. Pixel
diversity alone cannot certify visual quality.

Exit gate additionally requires actual mapped keyboard/mouse/controller
event flows through Hub/loadout, reward/route/shop/event, terminal return,
remapping/settings, challenges, replay, cosmetics, platform and Mods. Keep
every command reachable, cancel/focus behavior intact and errors visible.
No Godot script errors, invalid calls, ObjectDB leaks or RID leaks are allowed.
Verify clean imports, content/localization/license contracts, final scene
suite, asset hashes and clean exported startup after the UI changes.

Retain source commit, resource hash manifest, commands, strict logs,
screenshot manifest/inspection notes, export hashes and limitations in
`docs/current/2026-10-06-native-ui-finish-evidence.md`. Record each focused
commit as a rollback point. This design document records preparation only;
it makes no claim that UI implementation or visual certification has passed.
