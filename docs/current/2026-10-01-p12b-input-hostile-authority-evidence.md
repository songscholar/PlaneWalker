# Plane Walker P12B Input, Mastery, Replay, and Hostile Authority Evidence

- Status: Focused Verified / Current
- Document Role: Current evidence record
- Authority Level: P12 Tasks 2D-2E semantic input, mastery facts, replay compatibility, hostile identity, and unscaled threat evidence
- Applies To: Input schema 3, character-skill arbitration, mastery-family exactly-once facts, deterministic critical contexts, full-player replay migration, hostile attack identity, HostileThreatRegistry, presentation projection, and lifecycle retirement
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-30-plane-walker-p12-five-characters-design.md`, `docs/superpowers/plans/2026-09-30-plane-walker-p12-five-characters.md`
- Last Verified: 2026-10-01
- Evidence Status: Verified Locally
- Worktree Base HEAD: `0e50751`
- Implementation Commits: `add95e3`, `3a4769d`, `7f3689e`, `26ff039`, `4653e00`
- Rollback Point: `0e50751`

## Completion decision

P12 Task 2D and Task 2E are implemented and focused-verified locally. Input profile schema 3 adds the semantic `character_skill` action without rewriting existing schema-2 binding records. The live fixed-frame Player path arbitrates one sampled edge set in the exact order `Dash -> time slot 1 -> time slot 2 -> character skill -> declared weapon semantics`; accepted higher-priority actions suppress and discard lower edges, while rejected actions fall through without hidden buffering.

Weapon mastery uses one claim per `(generation, action_token, canonical weapon family)`. Multiple targets, pellets, zones, ticks, mastery IDs, echoes, and presentation callbacks cannot mint a second claim. Mastery payloads and contexts accept only Replay-safe value data. Character action snapshots retain claims, old full-player snapshots migrate deterministically from nested action schema 1 to schema 2, and malformed or unknown versions fail closed without mutating the caller value or live Player state.

Hostile damage now carries deterministic `hostile_source_id`, `attack_generation`, and authored `hit_index`. The Run host owns one `HostileThreatRegistry`; RoomController injects the same authority before hostile `_ready()`. Melee, Shooter bursts, projectiles, Tank pulses, Chrono Warden attacks, summons, and Time Crack hazards share committed identities correctly. Threat facts retain unscaled domain geometry, while `CombatTelegraph2D` applies accessibility scaling only to presentation. Attack completion, cancellation, death, room teardown, run failure, and terminal cleanup retire their matching facts.

## Input and replay evidence

- Input schema 1 follows the explicit `1 -> 2 -> 3` production migration chain; the generic schema-3 router rejects a direct schema-1 request.
- Schema 2 keeps every prior binding record byte-for-byte and adds keyboard `C` plus controller button `8` when available.
- Keyboard and controller collisions use deterministic finite fallback orders; exhaustion returns `NO_REACHABLE_CHARACTER_SKILL` without modifying the source profile, InputMap, or on-disk primary.
- Joypad button indices `0..31` round-trip; `32` rejects.
- Recovery order is current primary, current backup, schema-2 primary/backup, then schema-1 primary/backup.
- Full-player replay migration adds only `mastery_claims: []` to a valid nested action schema-1 snapshot, then recomputes frame and terminal summaries.
- Replay-safe mastery validation rejects Object, Resource, Callable, and nested unsafe values before claim installation or publication.
- Deterministic critical calculation accepts a frozen critical outcome or a validated seeded roll context and contains no global `randf()` or `randi()` path.

## Hostile authority evidence

- Room hostile IDs derive from run, room, encounter, spawn slot, spawn definition, and ordinal; two same-type enemies receive distinct stable IDs.
- One committed Shooter burst shares a generation while projectiles receive ordered hit indices.
- Tank pulses, Time Crack ticks, Boss melee/area/burst actions, and summon children preserve their intended committed identity boundaries.
- Burn/status ticks use explicit `status:` source identity and status generation rather than consuming the hostile attack allocator.
- Threat facts validate exact fields, finite unscaled geometry, and inclusive active-frame bounds.
- Registry queries cover circle, cone, line, Rift corridor, summon-slot, and target-circle geometry.
- Accessibility scales `1.0`, `1.25`, and `1.5` change only projected visual radius/length; gameplay containment and nearest-threat distance remain unchanged.
- Presentation code projects facts and never reads `CombatTelegraph2D.get_snapshot()` as gameplay authority.

## Focused verification

The following local gates passed with zero scene failures and zero leak warnings:

- input suite: `9 / 9`;
- replay suite: `6 / 6`;
- hostile attack identity: `1 / 1`;
- hostile threat registry: `1 / 1`;
- enemy suite: `2 / 2`;
- Boss suite: `5 / 5`;
- character action coordinator, mastery fact, character priority, fixed-frame authority, event publication, EventBus source contract, deterministic damage calculator, Player action runtime, and semantic weapon input;
- content-pack and content-registry contracts after refreshing the Base Pack localization integrity hash;
- RunRuntimeHost, room runtime, encounter, accessibility, controller focus, combat feedback, time loadout, M1 runtime smoke, run lifecycle publication, elite mechanic, and elemental-status adjacent gates.

`git diff --check` passed for both implementation slices. The complete `./tools/validate_project.sh` repository gate will be rerun after the active Wanderer/Time Guardian Player/Health/Time integration stops changing shared files; this record does not pre-claim that future result.

## Retention and rollback review

- Retain `3a4769d` for semantic input, mastery facts, replay-safe contexts, Player arbitration, and nested replay migration.
- Retain `26ff039` for deterministic hostile identity, shared threat authority, lifecycle retirement, and presentation separation.
- Retain `add95e3` for explicit deterministic critical contexts.
- Retain `4653e00` because localization changes must keep the Base Pack SHA-256 manifest valid; omitting it prevents ContentRegistry boot.
- Each commit is locally reversible. Reverting Task 2E also requires reverting the earlier `7f3689e` threat-fact foundation to avoid leaving an unused authority surface.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`; authentic external human sessions remain `0 / 20`.
- GDScript line coverage remains unavailable from the installed Godot CLI provider.
- Export templates, packaged startup, signing, remote push, store publication, and external credentials are not certified here.
- This evidence closes P12 shared input/mastery/hostile foundations only. Complete character gameplay, Boss exposure Replay state, character HUD/presentation, fifteen active Talents, schema-4 character Replay, the 150-loadout runtime matrix, and two byte-identical 4500-sample reports remain later P12 work.
