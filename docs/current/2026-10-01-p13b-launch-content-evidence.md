# Plane Walker P13B Complete Launch Pools Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P13B Launch content, typed-effect, active-item, talent, Replay, Save, UI, simulation, and repository certification evidence below the approved Full Product Completion Design
- Applies To: Exact `50 / 28 / 18 / 15` Launch pools, `42 / 8` item split, eight archetypes, atomic reward effects, eight active items, fifteen talents, Replay schema 6, SaveEnvelope schema 2, thirty-seed formation, and the 150-loadout runtime matrix
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p13b-launch-content-design.md`, `docs/superpowers/plans/2026-10-01-plane-walker-p13b-launch-content.md`, `docs/contracts/content-pack-v2.md`, `docs/contracts/save-service-v2.md`
- Last Verified: 2026-10-01
- Evidence Status: Verified Locally
- Worktree Base HEAD: `4fbf9b1`
- Implementation Certification Commit: `9a04639`
- Certified Repository State: `9a04639` plus this documentation-certification commit
- Rollback Point: `4fbf9b1`

## Completion decision

P13B is locally complete. The Launch Base Pack now exposes exactly:

```text
50 items = 42 passive + 8 active
28 blessings
18 Launch curses
15 character run talents
```

The curse content file contains 24 definitions in total: the 18 P13B Launch curses plus 6 frozen M1/NEXT definitions. This certification does not misreport the full file as an 18-row file.

The eight authoritative build routes remain, in approved order:

```text
freeze_burst
rewind_echo
rift_trap
accelerated_combo
low_hp_void
perfect_guard
piercing_barrage
echo_legion
```

Each route has starter, payoff, risk, utility, talent, and active-item formation coverage. M1/CURRENT/NEXT retain their frozen three-route behavior. P13B closes content and runtime authority only; it does not claim P14 floors, P15 enemies/Boss kits, Hub, narrative, rankings, Mod UX, or other later product stages.

## Exact Launch catalog and integrity hashes

The closed Launch catalog, Base Pack definitions, schemas, localization, and registry contracts enforce the exact IDs, order, availability, category, route, role, compatibility, icon, effect, handler, and manifest relationships. Current certified SHA-256 values are:

```text
data/content/effect_catalog.json
1354c36f1b76b64ee05b4226c687e76a28ab3fb63a0923c4b3a2b8115883ce2b

data/content/launch_pool_catalog.json
79b50539f4714e94edb42bac497bbf5a211028d6486b370ddd96cf9575a599ba

data/content_packs/base/pack.json
6d132ffc3762a8fd567a86e9ade74049a967feaf7623a2be0c2f893714a72537

data/content_packs/base/content/items.json
629cf16f94ad5783b55bc2679064bfeecf75f04ec76cc551a21eedf8411e0f25

data/content_packs/base/content/blessings.json
416cd323625e6bf2d75f6b2f1fae0ebc5a6d52ab485b790e9d215b17e4264866

data/content_packs/base/content/curses.json
a0861dba4b87f1dc3e1f2fab0d6d3ba0e839db00d7056924791e22815e7c6138

data/content_packs/base/content/talents.json
55b7b9cbb1a4eba4b82c743bf01a5540ca5d1f91f0040d72e4f2086592a2cf4c

data/content_packs/base/content/archetype_profiles.json
9bb211b494e9187ae7eff4d674a4bcdadef24d256856f99b094c735a7b33c067
```

The effect catalog contains 62 closed effect IDs. Every content effect is category-valid, bounded, normalized, routed to a known runtime domain, and covered by a runtime consumer or execution test. These hashes certify current bytes only; prior evidence retains the values valid at its own certification commit.

## Eight-route formation and Boss-safe coverage

`launch_pool_contract`, `launch_draft_archetype`, and the formation simulator prove the exact route catalog and minimum route budgets. Every route exposes at least `3 starter / 2 payoff / 1 risk`, explicit utility support, one content-backed talent opportunity, and exactly one active item. Boss hard-control is forbidden; handlers convert Boss interactions into approved damage, vulnerability, resource, positioning, or bounded duration behavior.

The eight active item identities are:

```text
absolute_zero_device
paradox_beacon
gravity_snare_device
redline_injector
blood_price_relic
aegis_reversal
railshot_module
army_of_yesterday
```

The forty-two passive items execute through real compatible Player/weapon states. The twenty-eight blessings remain positive persistent choices. Each of the eighteen Launch curses contains both a positive and negative bounded operation. The six frozen earlier-milestone curses remain compatible and separately identified.

## Typed effect and atomic reward transaction authority

`PlayerRewardEffectRuntime` prepares canonical digest-sealed plans and commits domains in a fixed order through the Player adapter. Focused unit, integration, Host, Facade, and Orchestrator tests cover:

- invalid definitions, bounds, categories, targets, capabilities, content digests, and stale revisions;
- persistent-domain failure, trigger failure, weapon failure, authority failure, and publication failure;
- exact Player snapshot compensation after a failed commit;
- explicit rollback after a successful commit;
- rollback-failure escalation to the `reward_transaction_integrity` terminal reason;
- no offer consumption, room transition, or published reward fact before the complete transaction commits;
- exactly-once final publication after Player state and authoritative selection agree.

The failure matrix preserves the pre-selection Player snapshot and keeps the offer retryable whenever exact compensation succeeds. If compensation cannot prove integrity, the run fails closed instead of continuing with divergent BuildState, Player, or room authority.

## Eight active items, input, HUD, feedback, and replacement

All eight handlers pass deterministic pure planning, exact resource claims, tamper rejection, stale token/generation rejection, idempotency, cooldown boundaries, reset, snapshot/restore, and rollback tests. The Player owns one active slot. Replacing an existing active requires explicit confirmation and remains reversible until the authoritative reward transaction commits.

The remappable `active_item` semantic input is wired through controller and keyboard profiles. Combat HUD and ChoicePanel project localized name, route, role, rarity, cooldown, cost, effect summary, and replacement state. CombatFeedback and Pixel Proxy presentation expose activation, rejection, cooldown, and accessible subtitle/audio/visual alternatives. Controller focus and the `640 x 360` safe-area contracts remain green.

## Fifteen data-authoritative talents

The five characters retain exactly three run talents each. `CharacterTalentState` consumes the versioned Base Pack definitions rather than duplicating selected modifier values in character scripts. Evidence covers all `5 x 2^3 = 40` canonical subsets, stable ordering, exact modifier vectors, duplicate/cross-character/invalid-effect rejection, live installation, reset, snapshot/restore, and rollback.

Loadout, draft, Player runtime, and character runtime agree on the selected definition copies. Replay restore rejects forged talent definitions even when both serialized copies and outer digests are changed together, because the local Base Pack remains authoritative.

## Replay schema 6 and SaveService schema 2

Implementation commit `9a04639` closes the final Replay and persistence boundaries:

- Launch full-player Replay schema 6 freezes the recording identity while persisting mutable passive, talent, active-item, reward, dash-invulnerability, and ordinary invulnerability state;
- Wanderer M1 Replay schema 2 preserves its exact historical player-state field set and byte-equivalent round trip;
- authenticated Launch v4/v5 documents fail closed because their missing reward domains cannot prove lossless migration;
- every participant is prevalidated before mutation, world state is staged, failed late restoration rolls every participant back atomically, and rejected restores publish no transient health/time/weapon notification;
- fixed-frame and late-frame rollback include reward and ordinary dash invulnerability tokens;
- SaveEnvelope schema 2 provides native profile/settings schemas, ordered v1 migration, resealing, production writeback, forward-v3 refusal, and corruption recovery;
- a real Launch Player with Sword runtime, non-empty dynamic `resource_regen_frame_accumulators`, and an activated active-item receipt survives physical JSON write/read and restores exactly into a fresh Player;
- nested active-item and reward runtime objects are explicitly opaque-but-runtime-validated rather than overclaimed by JSON Schema alone.

## Thirty-seed synthetic formation evidence

The deterministic simulator uses seeds `20260901..20260930`, eight routes, and 240 total samples. Each sample requires `3 starter / 2 payoff / 1 risk / 1 utility / 1 talent`; every route succeeds `30 / 30`, all fifteen talents are exposed, and repeated runs produce byte-identical JSON.

```text
synthetic: true
human_playtests: 0
content_digest: 62b2a2eb623de090524e10589feb8d64c1ec9c63edc17de0e6b93c99836344f9
report_sha256: 31d606acca265d8fb137aab8458a1316fc29ea38c2874511c7f6c19fcebea3e7
```

This report validates formation, exposure, definitions, and deterministic execution. It is not human feel, balance, comprehension, accessibility, or retention evidence.

## 150-loadout representative runtime matrix

The matrix covers `5 characters x 5 weapons x 6 time pairs = 150` Launch loadouts. Every case loads a content-backed talent and executes representative starter, payoff, general curse, and active content through real runtime state.

The matrix validates all 150 loadout combinations and five weapon-representative active routes. It does not claim that every one of the 150 cases executes all eight active items. Full eight-handler coverage comes from active-item runtime/integration tests and the 240-sample formation report.

## Implementation commits

```text
ac7ee32 feat(content): close launch pool contract
d667a99 feat(rewards): apply content effects atomically
e6edace feat(items): complete launch item pool
3762d35 feat(items): add active item runtime core
24c2475 feat(items): integrate active item player slot
1c8b8f2 feat(ui): project active item HUD state
4590521 feat(feedback): present active item combat cues
02f11c2 test(content): add launch pool formation simulation
61e26b3 feat(input): add active item remapping
cda14a3 test(content): certify launch pool loadout matrix
da091a0 feat(replay): persist active item state
f7c5312 feat(content): complete blessing and curse pools
c584589 feat(ui): confirm active item replacement
eb8e46c feat(talents): source launch modifiers from content
85c18a3 test(content): strengthen launch formation certification
ef6ef58 fix(localization): cover curse risk domains
957e0a5 fix(progression): seal build snapshot integrity
8129eca test(talents): load authoritative character definitions
8373c66 fix(progression): normalize replay-safe build rewards
87f01c9 feat(replay): seal launch reward state
bd4e8c3 feat(replay): seal authoritative run rewards
9a04639 fix(replay): preserve m1 and activate save v2
```

## Complete repository gate

The final local `./tools/validate_project.sh` run at implementation commit `9a04639` plus documentation-only working-tree changes passed:

- shell/CI, documentation governance, content schema, localization, playtest-data, simulation, M1 release, coverage-contract, and export-contract checks;
- Godot bootstrap and clean second import with only approved sandbox environment warnings;
- Godot scene suite: `168 / 168`;
- failed scenes: `0`;
- project validation: `PASS`;
- documentation governance: zero violations;
- `git diff --check`: clean.

Retained validation log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.wID6iF
```

The only registered scene-suite warning remains the existing `tests/reward_system_smoke.tscn` ObjectDB leak. The previously intermittent `enemy_projectile_test` wall-clock fixture was converted to deterministic manual physics and passed five consecutive focused runs before the final complete gate.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- No synthetic seed, simulation, loadout matrix, automated UI contract, or agent review is represented as human experience evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` because no trusted instrumented provider report exists.
- Export contract mode verifies repository policy and fail-closed behavior. Installed platform templates, real distributable export, packaged startup, signing/notarization, credentials, remote push, store configuration, and publication remain uncertified external or environment-dependent boundaries.
- P13B does not certify P14/P15 content or later Hub, progression, narrative, endings, online, Mod, cosmetic, operations, or DLC product stages.

## Next local program

P14 is the active repository-local stage. It delivers five deterministic floors, thirty integrity-sealed streamed room scenes, five floor rules, one Launch economy, five merchants, fifteen regular plus three special events, route/map/shop/event/rest UI, Save/Replay integration, thirty-seed simulation, and a 150-loadout dungeon matrix. P15 remains responsible for the twenty-two Launch enemies, elite affixes, and five final Boss behavior kits.
