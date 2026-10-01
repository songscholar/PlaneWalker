# Plane Walker P13A Launch Archetype Authority Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P13A archetype identity, content-reference, draft, build-state, projection, and HUD certification evidence below the approved Full Product Completion Design
- Applies To: Eight Launch archetype profiles, milestone-aware content validation and drafting, authoritative RunBuildState scoring, Replay-compatible snapshots, RunViewState projection, localized HUD identity, and repository certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/plans/2026-10-01-plane-walker-p13a-launch-archetype-authority.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-10-01
- Evidence Status: Verified Locally
- Worktree Base HEAD: `f2137ff`
- Implementation Certification Commit: `efebc11`
- Certified Repository State: `efebc11` plus this documentation-certification commit
- Rollback Point: `f2137ff`

## Completion decision

P13A is locally complete. Plane Walker now has one closed, versioned authority for the eight Launch/Expansion build archetypes, and the content registry, reward draft service, authoritative run state, UI projection, and HUD all use that same identity set. The approved order is:

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

M1, CURRENT, and NEXT remain restricted to `freeze_burst`, `rewind_echo`, and `accelerated_combo`. Launch and Expansion use exactly the eight-key domain above. Mechanic tags such as `heavy_cleave`, `evasive_guard`, `reload_burst`, and `area_control` cannot become top-level build identities.

This certification closes identity, validation, deterministic routing, build-state, and player-facing projection authority. It does not claim the final Launch pool counts. P13B owns the real `50 items / 28 blessings / 18 curses / 15 run talents` pool and effect certification.

## Versioned profile and Registry authority

`archetype_profile_v1.schema.json`, `ArchetypeProfile`, and the Base Pack catalog define exactly eight profiles. Every profile requires version 1, Launch/Expansion availability, bounded mechanic tags, minimum `3 starter / 2 payoff / 1 risk` coverage, one Boss conversion ID, and a localized Boss-response key. Unknown root fields, duplicate or ninth IDs, invalid coverage values, M1 availability, arbitrary effects, unsupported conversions, and overlong identities fail closed.

`ContentRegistry` validates each non-empty `archetype`, every `compatibility.archetype_ids` entry, and archetype-like content tag against an eligible profile before activation. Empty archetypes remain legal only for explicit `utility` plus `generalist` content where that rule applies. The Base Pack manifest contains the archetype catalog and verifies its byte digest before activation.

Current certified SHA-256 values are:

```text
data/schemas/archetype_profile_v1.schema.json
d4db420e578266551cf853ca4931a85783c0b53b5e746586d4884e31c8746baf

data/content_packs/base/content/archetype_profiles.json
9bb211b494e9187ae7eff4d674a4bcdadef24d256856f99b094c735a7b33c067

data/content_packs/base/pack.json
b96adb3160cedcd3bbd3a7af6eeb3b326fc3fcdca79e747d60031d3147b2e678

data/content_packs/base/content/items.json
768f372baffcd5dcc3d8d72ef139a788e151f777524bb864b6d9078d125fc822

data/content_packs/base/content/blessings.json
aa9863cd56e8fff4c5601b2adfbb2cc906bd64fe8fbd62019f02519f0d3a4f26

data/content_packs/base/content/curses.json
182bab81b4739950ace61f42b669cc901a33152dae0bf3a5e89b6a0d993cc9a9

data/content_packs/base/content/talents.json
8ed24bbcf544f8aa165316ed603e5e6f72d2e8c2e915494bcc1701389f9abb13
```

These values certify current bytes only. Earlier evidence retains the hashes that were correct at its own certification commit.

## Milestone-aware deterministic drafting

`DraftService` reads `state_snapshot.config.milestone`, filters candidate content before presentation, and incorporates milestone/profile authority into Launch seed channels without changing the frozen M1 seed behavior.

Executable draft evidence covers:

- 1000 M1 starter seeds, each retaining the exact three frozen routes;
- 30 canonical Launch seeds `20260901..20260930`, each producing a valid three-option starter offer, repeating byte-equivalent offer dictionaries for identical inputs, and collectively exposing all eight routes;
- one reinforcement case for every Launch archetype, containing one dominant payoff, one pivot starter, and one utility or safety option;
- fail-closed behavior for unknown milestones, unknown dominant identities, unavailable profiles, insufficient coverage, owned-content exhaustion, and noncanonical cached-offer identity;
- 30 M1 seeds across the first four authoritative rooms, with every resolved option accepted by `RunBuildState.validate_definition()`;
- explicit CURRENT and NEXT candidate-domain regression tests that reject Launch-only routes before the player can select them.

This last compatibility check closes the previously observed reward-flow regression where a Launch-only `perfect_guard` definition could be displayed during M1 and then rejected after selection.

## Authoritative build state and player-facing UI

`RunBuildState.apply_definition()` is the single build-content write path. It rejects duplicate content, unknown categories, milestone-domain violations, and legacy mechanic tags; appends the stable content identity to the correct collection; increments a non-empty archetype exactly once; leaves explicit utility content unscored; and recomputes the dominant route by score followed by approved archetype order.

The authoritative snapshot uses exactly three score keys for M1/CURRENT/NEXT and exactly eight for Launch/Expansion. The projector validates `authoritative.config.milestone` at the snapshot boundary, while standalone `RunViewState` accepts only one of those two exact supported domains and rejects missing, extra, negative, non-finite, or inconsistent dominant values.

The combat HUD caches the stable archetype ID but renders the localized `ARCHETYPE_<ID>_NAME` key. Locale refresh changes the visible label without mutating the authoritative identity. This is a player-facing completion, not a backend-only taxonomy.

## Implementation commits

```text
867b63b docs(builds): plan p13a archetype authority
f67d1e4 feat(builds): add launch archetype profiles
9986bfa feat(content): validate launch archetype references
8b92223 feat(rewards): route drafts through launch archetypes
9610bf1 feat(builds): enforce milestone archetype authority
11e6090 feat(ui): project authoritative build archetypes
98680aa test(rewards): cover compatible milestone domains
efebc11 fix(validation): migrate launch archetype fixtures
```

## Complete repository gate

The final local `./tools/validate_project.sh` run at implementation commit `efebc11` passed:

- bootstrap and clean Godot imports;
- Draft 2020-12 schema, content-pack, localization, documentation, playtest, release, coverage-contract, export-contract, and simulation-report checks;
- all focused P13A profile, registry, draft, run-state, projector, ViewState, HUD, choice-panel, and reward-smoke contracts;
- Godot scene suite: `156 / 156`;
- failed scenes: `0`;
- project validation: `PASS`;
- documentation governance: zero violations;
- `git diff --check`: clean.

Retained validation log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.SPoYy7
```

The only registered scene-suite warning remains the existing `tests/reward_system_smoke.tscn` ObjectDB leak. Expected invalid-input diagnostics emitted by destructive fixtures are followed by passing assertions and are not unregistered runtime failures.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- No deterministic seed run, synthetic fixture, automated UI contract, or agent review is represented as human feel, balance, comprehension, accessibility, or retention evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` because no trusted instrumented provider report exists.
- Export contract mode verifies repository policy and fail-closed execution behavior. Installed platform templates, real local distributable export, packaged startup, signing, credentials, remote push, store configuration, and publication remain uncertified external or environment-dependent boundaries.
- P13A does not certify the final Launch content counts or the gameplay effect of every future pool entry.

## Next local program

P13B is the next repository-local stage. It must deliver exactly 50 Launch items, 28 blessings, 18 curses, and 15 run talents through the P13A archetype authority, replace placeholder or identity-only entries with typed bounded effects, certify every effect handler and cross-reference, prove each route meets its starter/payoff/risk coverage, preserve M1/CURRENT/NEXT compatibility, and add deterministic pool, build-formation, UI, Replay, and full-repository evidence.
