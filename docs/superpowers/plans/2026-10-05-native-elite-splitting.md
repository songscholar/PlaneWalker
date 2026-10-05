# Native Elite Splitting Implementation Plan

- Status: Active / Current
- Document Role: Current focused implementation plan below the approved P15 specification
- Authority Level: Project standing authorization; approved P15 section6
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Applies To: Native revision-ten Splitting, ordinary copy contracts, shared child authority and physical save continuation
- Depends On: Approved P15 hostile specification; retained native summon and Mirroring baselines
- Exit Gate: Native ordinary-copy, elite, summon, checkpoint, production and Metal gates pass; independent natural recipe migration and actual Profile checkpoint remain explicitly tracked until certified

> **For agentic workers:** Execute this focused plan task-by-task in the existing project team. Steps use checkbox syntax for tracking. The owner's project-wide standing authorization and approved P15 specification supply the design decision; milestone review is informational.

**Goal:** Final native elite death reserves exactly two ordinary no-affix copies with33% ordinary authored HP, full30-frame spawn warning, TTL480, zero independent reward and no recursive child capabilities.

**Architecture:** Native revision ten enables a stateless final-death trait while explicit revisions one through nine preserve their original metadata-only Splitting signatures. Existing SummonAuthority authenticates prepared or externally published final death, owns the once-only claim, deterministic positions, finite eight-child admission, warning, orphan continuation and expiry. A small canonical ordinary-copy projection and runtime preserve ordinary species behavior through the existing owned child Actor lease.

**Tech Stack:** Godot4.6.1 GDScript; existing native Player fixed-frame transactions, EnemyRuntime, SummonAuthority, typed replay JSON and SaveService; original retained enemy raster atlases.

## Global Constraints

- Approved P15 section6: two ordinary no-affix copies,33%baseHP,TTL480,once-only,zero independent reward; floor2-5; excludes Nullified/Mirroring and species with own split/echo/summon/portal/revival.
- Spawn warnings use at least30 accepted frames; copied damaging action warnings retain their ordinary authored floors.
- Preserve revisions1-9 and schema-seven state compatibility. Splitting does not need another independent clock or duplicate once-only ledger.
- Keep native child state independent from presentation. Seed, source identity, slot, request frame and accepted death receipt determine reservation identity and frozen positions.
- Share existing maximum8 live/warning children and bounded reservations/claims. No recursive copied abilities or separate ordinary encounter roster/reward entry.
- Run actual Player, damage, rollback, cold save, native pixels, shared elite/summon/checkpoint and production encounter gates before milestone completion.
- Use exact staging lists in this shared dirty worktree; coordinate shared Actor/Authority/Driver edits with their current owners. Never push.

## Approach Review

The chosen approach adds a canonical ordinary-copy projection/runtime and keeps
admission in SummonAuthority. It preserves existing ordinary species selection,
motion and mechanisms without duplicating the native lease/TTL transaction.
Generalizing the nine-support-unit runtime would broaden its closed contract
and mix support behavior with ordinary species state. Treating copies as new
principal encounter spawns would need a second admission/reward boundary and
would conflict with their zero independent reward. The focused owned-child
approach matches the retained Mirroring and authored summon implementation.

## Task 1: Native Metadata-Only RED

**Files:**
- Create: `tests/integration/combat/launch_elite_splitting_test.gd`
- Create: `tests/integration/combat/launch_elite_splitting_test.tscn`

**Interfaces:** Consume actual native Player, Sword profile, elite Actor,
FrameBridge, Effects and typed cold aggregate APIs. The gate exposes no test-only
runtime bypass. Revision-nine final death must fail only the missing two-copy
reservation assertion.

- [x] Create an actual canonical Sentinel elite with Splitting at explicit revision9, valid native room and actual Player/FrameBridge ownership.
- [x] Deliver an accepted native lethal body fact; assert the parent's ordinary80HP is distinct from elite160HP and its terminal transition is authentic.
- [x] Assert two pending/warning copy rows and retained room work before final principal defeat; metadata-only revision9 fails these semantic assertions.
- [x] Retain the clean RED under `build/test-evidence/elite-splitting-certified-red` using `ELITE_SPLITTING_TEST_REVISION=9 tools/run_tests.sh --filter launch_elite_splitting --timeout 300`. The only failure is the missing two-copy reservation; no parser, script or leak diagnostics remain.

## Task 2: Canonical Ordinary Copy Contract

**Files:**
- Create: `scripts/enemies/launch/launch_ordinary_copy_projection.gd`
- Create: `scripts/enemies/launch/launch_ordinary_copy_runtime.gd`
- Create: `scripts/enemies/launch/launch_ordinary_copy_actor.gd`
- Create: `tests/unit/enemies/ordinary_copy_runtime_test.gd`
- Create: `tests/unit/enemies/ordinary_copy_runtime_test.tscn`

**Interfaces:**
- `CopyProjection.create(parent_id: String, origin_affixes: Dictionary) -> Dictionary`: returns canonical wrapped ordinary definition or strict failure. Wrapper has ordinary ID/runtime kind, actor kind `summon`,33% canonical ordinary HP, ordinary damage/defense/move speed/radius/actions/mechanisms and closed `copy_contract` binding.
- `CopyRuntime.configure(definition: Dictionary, identity: Dictionary) -> Dictionary`: authenticates the canonical wrapper, delegates ordinary species behavior to EnemyRuntime and seals the wrapped definition digest. Restoration uses the same original child birth identity and species mechanism state.
- `CopyActor.instantiate_copy(parent_id: String) -> Node2D`: loads the actual original enemy scene/atlas, uses CopyRuntime and inherits SummonActor's authority-owned lease, TTL and unrewarded terminal lifecycle.

- [x] Test every canonically legal Splitting parent, exact ordinary HP/damage, original non-affix action set and forbidden own-child species refusal.
- [x] Test wrong parent, affix revision/pair/floor, HP/damage/defense/actions/mechanisms/extra-field mutation and cold definition digest refusal before implementing the helper. The initial missing-module RED is retained under `elite-splitting-copy-red`.
- [x] Implement canonical projections by parsing the retained authored enemy table; no external parent dictionary can supply altered ordinary combat values.
- [x] Configure the inherited ordinary runtime through the wrapped definition and keep child actor kind `summon` for existing roster cleanup and recursion refusal.
- [x] Test actual ordinary action selection, warning/attack facts, accepted damage, final-death decisions, controls, deterministic motion and cold continuation with the new pure child identity.
- [x] Run the canonical contract and expanded control/motion gates; final GREEN is `elite-splitting-copy-state-final`,1/1. Retain the coherent pure modules/tests with precise paths in the native milestone.

## Task 3: Once-Only Native Death Admission

**Files:**
- Modify: `scripts/enemies/launch/launch_elite_affix_projection.gd`
- Modify: `scripts/enemies/launch/launch_elite_affix_runtime.gd`
- Modify: `scripts/enemies/launch/launch_hostile_actor.gd`
- Modify: `scripts/enemies/launch/launch_summon_authority.gd`
- Modify: `scripts/dungeon/native_launch_encounter_driver.gd`

**Interfaces:**
- `AffixRuntime.is_splitting() -> bool`: enabled only for configured revision>=10 and Splitting ID.
- `Actor.native_splitting_configuration() -> Dictionary`: returns the immutable accepted Splitting configuration; empty otherwise.
- Existing prepared Actor final state and `prepared_launch_frame_consumes_actor()` authenticate in-frame final death.
- Existing `capture_native_terminal_split(owner, receipt, targets)` also admits native Splitting after exact actual out-of-frame Health death, canonical receipt, owned source/run/frame and configured revision-ten trait validation.
- `SPLIT` rows use `[run, source, "affix:splitting", 1, slot]` identities, slots0/1, generation1, canonical copy projection, frozen position, request/warning frame, lifetime480 and `retire_on_owner_death=false`.

- [x] Add revision10 to the compiler/runtime/Actor configuration ranges; remove Splitting from current pending IDs while historical revisions retain it.
- [x] Establish the missing final-death RED before implementation; expand to actual out-of-frame death, once-only claims, duplicate callbacks, compensated retry and no spawn on prevented/nonterminal damage during implementation.
- [x] Reserve exactly two copy rows before principal defeat can clear a room. Reuse existing native safe admission, warning restarts and global eight-child budget.
- [x] Authenticate copy rows against ordinary canonical parent, source Splitting configuration, slot/count, exact lifetime/warning and dedicated namespace; ordinary ACTION/DEATH/MIRROR records retain their existing validators.
- [x] Instantiate CopyActor only for `SPLIT` rows; retain original support constructors for the nine authored support IDs.
- [x] Bind orphan copies to the retained scene fallback and let TTL retire actual HP/body, threats, payloads and pending encounter work.
- [x] Retain independent coherent revision-ten code only after actual native gate passes. All native gates are GREEN; local commit `575a8ec` retains18 precise paths and leaves natural revision3 migration independent.

## Task 4: Cold And Physical Continuation

**Files:**
- Modify: `scripts/dungeon/native_launch_encounter_driver.gd`
- Modify: `tests/integration/combat/launch_elite_splitting_test.gd`
- Modify: `tests/integration/save/native_combat_checkpoint_test.gd`

**Interfaces:** Driver child validation chooses CopyRuntime for `SPLIT` and
SummonRuntime for existing support modes. `SPLIT` provenance must refer to an
authored elite source with a legal revision-ten Splitting configuration and its
canonical defeat ledger receipt/frame. Both copies remain child work rather
than independent principal spawns.

- [x] Test typed warning, pending, active and expired copy states; exact fresh reconstruction and next accepted native frame.
- [x] Reject erased claims, source/parent/revision substitution, missing sibling/extra third slot, altered33% HP, future request and shortened warning/TTL. Non-final mother capture is refused; birth bounds are enforced by the closed authority.
- [ ] Certify the production Host/Profile checkpoint with the dead mother absent and two surviving ordinary copy bodies. Actual SaveService aggregate round-trips are GREEN for all14 legal parents; a separate selection revision3 is needed because existing natural recipes contain no Splitting IDs. The explicit checkpoint probe retains the current natural-route RED.
- [x] Verify both child death and TTL clear room work without another principal defeat, independent reward, duplicate callback or recursive copies.

## Task 5: Native Presentation And Retention

**Files:**
- Modify: `scripts/enemies/launch/launch_elite_affix_cue.gd`
- Modify: `scripts/enemies/launch/launch_hostile_actor.gd`
- Modify: `tests/integration/combat/launch_elite_affix_test.gd`
- Create: `docs/current/2026-10-05-native-elite-splitting-evidence.md`

- [x] Draw the authored two-fragment Splitting cue, scaled/high-contrast, with separate geometry beside every legal existing cue; gameplay state is unchanged by accessibility settings.
- [x] Capture actual mother, two30-frame warning rasters and two original enemy copy atlases at640x360/1280x720 Metal; assert actual pixels and visually inspect all twenty retained screenshots.
- [x] Verify actual production Sword contact, all native warning floors, no independent reward, blocked/deferred positions, eight-child capacity, TTL480, source death outside the frame and full late World compensation.
- [x] Run `--filter launch_elite`, `--filter native_summon`, `--filter native_combat_checkpoint` and `--filter production_launch_encounter` with retained test logs;10/10,4/4,1/1 and1/1 respectively. Physical checkpoint covers the existing21 default cases; the explicit natural Splitting case remains RED until revision3.
- [x] Scan `*.log` files including ignored paths for script/parse errors, warnings, orphans and leaks; record the four expected injected settlement rejection diagnostics separately.
- [x] Write consolidated evidence with exact RED/GREEN, reversible choices and remaining certification limits; update the checklist and README index. Native retention is local commit `575a8ec`.
