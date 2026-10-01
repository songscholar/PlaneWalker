# Plane Walker P12 Five Complete Characters Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Consolidated P12A-P12G local certification evidence below the approved five-character design
- Applies To: Six milestone-aware character profiles, five complete Launch character runtimes, fifteen talents, character UI and feedback, deterministic Replay, 150 loadouts, 40 talent subsets, 30 pairwise integrations, 4500-sample simulation reporting, and repository certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-30-plane-walker-p12-five-characters-design.md`, `docs/superpowers/plans/2026-09-30-plane-walker-p12-five-characters.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-10-01
- Evidence Status: Verified Locally
- Implementation Certification Commit: `e7b1ef9`
- Certified Repository State: `e7b1ef9` plus this documentation-certification commit

## Completion decision

P12A-P12G are locally complete. Plane Walker now resolves six milestone-aware character profiles and ships five mechanically distinct Launch characters through one deterministic character authority. Wanderer, Time Guardian, Void Walker, Primordial Knight, and Time Lord each have exact Stats and mobility, a resource loop, character skill, five weapon-mastery interactions, four time-ability interactions, three character-scoped talents, HUD state, feedback, controller and accessibility paths, snapshot/reset behavior, Replay coverage, and generation-safe cleanup.

The Launch path includes front-end selection and runtime presentation. The player can select any of five characters, five weapons, and six canonical time pairs, for exactly 150 legal tuples. Character resource, status, cooldown, skill rejection, proxy palette, animation cue, VFX, audio, subtitle, flash, shake, contrast, and reduced-motion behavior are projected through validated UI and feedback contracts. This is not a backend-only completion.

This decision does not change formal M1 status. M1 remains `M1 Candidate — External Validation Pending`, authentic external human playtests remain `0 / 20`, and no synthetic report is represented as feel, comprehension, retention, accessibility acceptance, or balance evidence from a human player.

## Shared deterministic authority

The five character runtimes use one 60 Hz frame pump through `PlayerController.advance_action_frame(frame_intents)`. Live play, Replay, matrix tests, and simulation consume the same profile and action contracts. Gameplay state does not advance from presentation `_process(delta)` paths.

The shared P12 foundations include:

- immutable `DamageInfo` and `DamageResolution`, including true zero-damage prevention;
- monotonic irreversible HP claims and rollback-safe Gameplay Rewind;
- transactional TimeAction prepare, commit, and rollback;
- generation-owned `WorldPayloadAuthority` descriptors;
- stable hostile source, attack-generation, and hit-index identity;
- unscaled `HostileThreatRegistry` gameplay geometry separated from visual accessibility scale;
- schema-3 semantic input with Dash -> Time -> Character -> Weapon priority;
- exactly-once mastery claims keyed by generation, action token, and canonical weapon family;
- fresh Stats, Health, Time, mobility, character, and weapon assembly on accepted loadout activation;
- deterministic critical outcomes with no global gameplay `randf()` dependency.

Rejected actions, invalid profiles, failed assembly, malformed Replay facts, stale callbacks, participant drift, and injected restore faults fail without partial resource, cooldown, HP, payload, event-prefix, or generation mutation.

## Five Launch character loops

- **Wanderer** preserves frozen M1/CURRENT/NEXT behavior while adding the Launch Path Mark, Waypoint Recall, and bounded five-weapon forgiveness routes.
- **Time Guardian** owns Ward, perfect and normal guard decisions, Rebuke, Bulwark/Fortress, time-cooldown conversion, and Boss-safe exposure conversion.
- **Void Walker** owns bounded Void Debt, deterministic risk queries, irreversible Devour cost, capped healing, authorized debt conversion, and Rift-aware effects.
- **Primordial Knight** owns Resonance, action armor, planar echo, Realm Cleave, Rift geometry conversion, instability claims, and Boss poise conversion.
- **Time Lord** owns Codex Pages, Primer, all six equipped time-pair conversions, Infusion, Dominion, and exact base/enhanced bounds without granting an unequipped third ability.

The character-specific runtime and production-integration tests cover boundary frames, resource caps, stale identities, rollback, Rewind non-refund, world ownership, Boss conversion, and non-recursive payload tags.

## Fifteen talents and forty subsets

The Launch pool contains exactly fifteen character talents, three per character. The three frozen M1 talent identities route through Wanderer without changing M1 behavior; twelve Launch identities use typed, bounded modifiers. Cross-character talent activation and a sixteenth identity are rejected.

The executable subset matrix covers all eight masks for each character:

```text
5 characters x 2^3 talent subsets = 40 canonical cases
```

Every case validates installation, behavior, snapshot, Replay/checkpoint, reset, canonical order, and cross-character rejection.

## Player-facing UI and feedback

`RunLoadoutCatalog` supplies stable localized IDs to the Character, Weapon, and Time Pair selectors. The Launch panel emits only validated canonical tuples and retains selected identities across locale refresh. Keyboard, mouse, and controller focus flows remain covered.

`RunViewState` and `RunViewStateProjector` validate and project the exact character-state union beside the five-weapon state union. The combat HUD renders the current character meter, status, and cooldown without leaking internal IDs. `PixelProxyActor` and `CombatFeedback` route character-specific palette, silhouette, aura, skill, hit, rejection, and Boss cues through the existing accessibility budgets.

Primary player-facing files include:

```text
scenes/ui/launch_loadout_panel.tscn
scripts/ui/launch_loadout_panel.gd
scripts/application/run_loadout_catalog.gd
scenes/ui/combat_hud_v2.tscn
scripts/ui/views/combat_hud_view.gd
scripts/application/run_view_state_projector.gd
scripts/presentation/pixel_proxy_actor.gd
autoload/combat_feedback.gd
```

## Character Replay and external facts

Launch character Replay authenticates character profile identity/version, run and generation identity, frame, capture sequence, content digest, event prefix, terminal digest, character coordinator/runtime/talent state, Time state, irreversible claims, hostile threats, and sorted world-payload descriptors.

Replay tests cover all five characters and these authority boundaries:

- Gameplay Rewind preserves already committed world payloads and does not recreate consumed payloads.
- Replay checkpoint restore invalidates the current generation and reconstructs recorded descriptors exactly.
- Reset and loadout replacement invalidate the outgoing generation, so late callbacks fail closed.
- Record-time and playback-time malformed, no-op, wrong-frame, wrong-token, wrong-generation, wrong-run, forged-ledger, unstable-hostile, stale-payload, profile-mismatch, and prefix-drift inputs reject atomically.
- Frozen Wanderer M1/P11 Replay behavior remains supported on its certified compatibility path.

The final Replay regression includes the optimized mastery fact projection. Replay still validates the complete input projection, but stores only the fields required by character mastery transitions. This removed repeated deep copies and plan hashing without widening depth limits or weakening tamper checks; the previously slow Gauntlets external-fact path completes within the test timeout.

## 150-loadout and pairwise certification

The runtime matrix covers the exact Cartesian product:

```text
5 characters x 5 weapons x 6 canonical time pairs = 150 loadouts
```

Each character shard runs all 30 weapon/time combinations twice through a real Player, advances only through the authoritative frame pump, exercises character skill, mastery, and both equipped time abilities, validates character/weapon UI state and Replay, resets twice, and compares deterministic pre-reset and clean-reset digests.

The 30-case pairwise integration uses the approved mapping and covers all 25 character-weapon pairs, all 30 character-time pairs, and all 30 weapon-time pairs while exercising room lifecycle, Chrono Warden conversion, checkpoint restore, and terminal cleanup.

## Synthetic simulation evidence

`tools/run_character_weapon_simulation_matrix.py` accepts only the canonical `--seeds 30` input and produces five characters, five weapons, six time pairs, 150 loadouts, 40 talent-subset cases, and 4500 deterministic samples.

Two independent outputs are byte-identical:

```text
/private/tmp/planewalker-p12-sim-a.json
/private/tmp/planewalker-p12-sim-b.json
```

Internal report `content_digest`:

```text
9683cec0cdaadc715b5cca2fde18abaea1a6b30f7beb4ac8f4c6b72962f8657d
```

SHA-256 of each complete output file:

```text
187837487c55fa05ad8f3b17cbb15d3cbb76654257a37273d4e6e412d4dfda07
```

The methodology seals the current Base Pack, character-profile, and weapon-profile digests. The contract rejects noncanonical seeds, omitted character profiles, unknown fields, NaN/INF, summary drift, digest tampering, and human-evidence claims. The report declares `synthetic: true` and `human_playtests: 0`.

## Complete repository gate

The final local certification at implementation commit `e7b1ef9` passed:

- documentation governance contracts: `30 / 30`;
- localization contracts: `8 / 8`;
- playtest and simulation-report contracts: `29 / 29`;
- M1 release contracts: `27 / 27`;
- GDScript coverage contracts: `5 / 5`;
- export contracts: `37 / 37` in contract mode;
- character simulation report contract: `8 / 8`;
- Godot scene suite: `154 / 154`;
- project validation: `PASS`.

Retained validation log:

```text
/private/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.RGMciJ
```

The only registered scene-suite warning is the existing `tests/reward_system_smoke.tscn` ObjectDB leak. Final log scans found no unexpected `SCRIPT ERROR`, parse error, failed resource load, RID leak, or unregistered ObjectDB leak. Godot bootstrap and clean imports contained only the registered macOS CA-store and sandboxed global editor-settings diagnostics. The original wrapper did not persist its final stdout line or shell exit code, but all 154 ordered log pairs, the final coverage artifact, every preceding contract/import artifact, and the runner failure scan are complete and green. Future certification wrappers must persist top-level stdout and exit status together. `git diff --check` passes.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- No synthetic simulation, deterministic matrix, automated UI test, or agent review is represented as human experience evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` because no trusted instrumented provider report exists.
- Export contract mode verifies repository policy and fail-closed execution behavior only. Installed Windows/Linux/macOS templates, distributable creation, packaged startup, platform signing, credentials, remote push, store setup, and public publication remain external boundaries.
- The implementation is certified at `e7b1ef9`. This evidence record does not invent the hash of its own later documentation-certification commit.

## Next local program

P12 closes the complete five-character runtime program. The next repository-local Full Product step is P13: eight archetype mechanics and the complete Launch item, blessing, curse, and talent pools, followed by the staged five-floor/five-Boss, Hub/meta, narrative/endings, replay product, rankings, Mod, operations, cosmetics, and DLC/content-pack programs. M1 external evidence remains an honest parallel gate and does not stop authorized repository implementation.
