# Plane Walker P14F Dungeon Events Evidence

- Status: Implemented / Current
- Document Role: Current evidence record
- Authority Level: P14F event runtime, production integration, Save, Replay, and focused verification evidence
- Applies To: Fifteen regular events, three special events, weighted outcomes, atomic consequences, pending reward/combat, publication, Save/Replay, and UI-safe event state
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/superpowers/plans/2026-10-02-plane-walker-p14f-dungeon-events.md`, `docs/contracts/save-service-v3.md`
- Last Verified: 2026-10-04
- Evidence Status: Implemented
- Worktree Base HEAD: `6fc950b`
- Rollback Point: `548c58f367af104ab1264b95a4c9a4de61488c33`
- Certification Status: Focused gates passed; reviewed implementation commit and complete repository certification pending

## Implemented runtime

The authoritative Base Pack contains fifteen regular and three special events. Selection is deterministic at room entry, obeys floor bounds and repeat policy, and freezes the actual selected event without changing the generated FloorPlan identity. Every authored option has an executable outcome or exact requirement rejection.

Atomic consequences compose resource, health, economy, BuildState, route, flags, modifiers, and authenticated reward/combat continuations. Unresolved continuations keep the event room open. Result dismissal owns the eventual room-clear boundary. Failed recoverable transactions restore participants; failed compensation reaches the typed integrity path.

`RunState` persists the complete event runtime and derives the seen-event projection. The production Facade rebuilds the selected-event overlay on restore. The Host creates and connects RoomRuntime for Launch floors with one room-start publication owner. Relevant integration commits are `5185c1b`, `b7499c6`, and `c16d39a`.

## Save and Replay boundaries

Current SaveEnvelope schema 3 includes the event runtime and validates open, reserved, pending reward, pending encounter, resolved, and dismissed phases. It reconstructs every typed participant, binds assignments to authored event/floor/node definitions, validates the original publication chain, and cross-checks live resource, health, economy, route, curse, flag, modifier, and seen-event projections.

The audit reproduced a corruption bypass in all six phases: clearing both `dungeon_event_runtime` and `seen_event_ids` left initialized resource/health authorities accepted. The repaired validator rejects this combination. Every phase now also writes and loads through the production SaveService using physical JSON I/O.

A further failing reproduction used a genuinely initialized runtime with empty assignments, consistent participants, and a cleared event node. Save validation and new writes accepted the erased history before the repair. The validator now requires cleared-event assignments, with a narrow exception for authored route-skip intermediate rooms backed by completed route and consequence transactions. Physical Save round trips cover both an intermediate event room and an event landing room; clearing the landing without its own history is rejected. Unknown nested fields, duplicated transactions/publications, and validation input immutability are also covered.

Historical v3 shapes without an event runtime remain readable. Ordered migration does not invent assignment, outcome, pending continuation, receipt, or publication history. Historical active runs that already record legacy events retain their original projection and are read-only until complete event authority exists. Content mismatch is decided after closed-envelope and SHA-256 validation, before current content is used to interpret historical event state; it preserves the primary and does not trigger older-backup recovery.

Dungeon Replay schema 3 seals the actual runtime digest and ordered assignment, authored outcome, transaction, consequence receipt, and publication facts. Modern capture requires the original runtime publication secret. Re-signed drift, malformed participants, wrong secret, missing receipts, changed authored outcome, false continuation success, and erased cleared-event history are rejected. The pre-event schema-3 shape is readable only for an empty event history with no cleared event facts.

## Exhaustive event matrix

Commit `6fc950b` adds `all_dungeon_events_smoke_test`. The verified matrix contains:

- `18` event identities, including `15` regular and `3` special;
- `36` options and `39` authored outcome branches;
- `78` executions, with every branch repeated byte-identically;
- `16` pending reward and `2` pending encounter continuations across both passes;
- `9` exact non-floor requirement rejections;
- `252` exactly-once opened, committed, completion, and dismissal publications;
- `9` authored consequence operation kinds with concrete assertions.

## Focused verification

The 2026-10-04 focused runs used Godot `4.6.1.stable.official.14d19694e`:

| Command filter | Passed scenes | Log directory |
|---|---:|---|
| `run_authority_contract` | 1 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.uGQdik` |
| `save` | 6 | `/tmp/planewalker-p14f-save-focused` |
| `run_dungeon_replay` | 1 | `/tmp/planewalker-p14f-replay-focused` |
| `events/` | 10 | `/tmp/planewalker-p14f-events-focused` |

Each filter completed with zero failures and zero unknown leak warnings. `event_save_restore` was rerun after adding the physical per-phase SaveService round trip. `git diff --check` passed.

The cleared-history regression changed from failing in `/tmp/planewalker-p14f-save-audit-final-red` to passing in `/tmp/planewalker-p14f-save-audit-final-green`. That focused scene passed with zero leak warnings after the route-skip compatibility checks were added.

The reward-authority contract initially failed because it required a direct BuildState call in the Orchestrator source. The event integration intentionally moved that call into `RunState.apply_reward_definition` to synchronize event modifier snapshots. The corrected contract keeps one BuildState application boundary and uses a runtime counting authority to prove exactly one complete-definition delegation, empty-resolution no-op behavior, propagated rejection, and unchanged rejected build state.

## Repository certification

The earlier 2026-10-04 complete audit passed all `183` Python contracts and `207 / 208` Godot scenes. Its one failure was the stale direct-call source contract repaired above. That earlier result is not represented as a successful complete gate. Retained audit stdout is `/tmp/planewalker-progress-audit-validation.log`.

This focused evidence must be promoted only after the integration owner runs the complete repository gate against the final combined implementation, records its exact revision, and commits the reviewed implementation and documentation. Concurrent P14G work is outside the focused P14F result.

## Remaining boundaries

- Formal M1 remains `M1 Candidate - External Validation Pending`; authentic human sessions and matched observations remain `0 / 20`.
- Scene pass counts are not GDScript line coverage. Coverage remains unavailable without a trusted instrumentation provider.
- Official export templates, real distributable exports, packaged startup, signing, credentials, and public release remain separate gates.
- Final player-facing map/shop/event/rest/transition/controller interfaces belong to P14G, and complete five-floor route/economy/150-loadout certification belongs to P14H.
- This record certifies backend event state and focused behavior. It does not claim human balance, readability, retention, final art/audio, or complete Replay productization.
