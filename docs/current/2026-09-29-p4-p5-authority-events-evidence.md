# Plane Walker P4/P5 Runtime Authority and Event Publication Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P4/P5 runtime-authority and exactly-once gameplay-fact certification evidence
- Applies To: RunState ownership, RoomRuntime lifecycle, RunRuntimeHost, legacy retirement, typed gameplay facts, direct domain routing, and EventBus source constraints
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p4-p5-authority-events.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified HEAD: `bc1638decedbf22eba34141d54a023eef4215c1d`
- Rollback Point: `96a2c605827748fff5f9c8f730157c79d9b3ebde`

## Completion decision

P4 and P5 are locally complete. `RunOrchestrator` owns the only mutable `RunState`; `RoomRuntime` coordinates room entry, encounter completion, player death, Boss victory, runtime failure, and direct terminal commits; `RunRuntimeHost` is the sole lifecycle-fact publisher. `GameState` retains settings, SaveService compatibility, Profile data, and one narrow persisted run-summary helper, but owns no live run state.

The legacy adapter, mirrored phase/floor/room/seed/timer/build state, old CombatHUD, and three old selection views are deleted. EventBus contains typed signals only. Generic string publication, handler storage, deferred queues, StringName event constants, and state-changing runtime subscriptions are absent.

This certification does not change the formal release state. Plane Walker remains `M1 Candidate — External Validation Pending`; authentic external playtest evidence remains `0 / 20`.

## Certified commit chain

| Commit | Deliverable |
|---|---|
| `96a2c60` | Replaces the scene adapter node with `RunRuntimeHost`, V2 HUD, and unified V2 choices |
| `3369e7d` | Retires GameState run mirrors, LegacyRunAdapter, old runtime UI, and adds the authoritative run clock/source contract |
| `d2b4d0f` | Freezes lifecycle signatures and publishes successful run/room/selection/terminal facts once |
| `60bac2c` | Publishes damage, attack, dash, spawn, and time-skill facts once with frozen context payloads |
| `bc1638d` | Removes the generic EventBus and replaces state-changing subscriptions with direct domain commands and local signals |

## Runtime authority boundary

The certified command flow is:

```text
Main / UI
  -> RunRuntimeHost
  -> RunRuntimeFacade
  -> RoomRuntime / RunOrchestrator
  -> private RunState
```

Only `RunOrchestrator` changes run phase or gameplay revision after construction. Runtime and UI consumers receive deep-copied snapshots. The authoritative clock is advanced through `RunRuntimeHost -> RunRuntimeFacade -> RunOrchestrator -> RunState`; pause, Hub, and terminal phases are accepted no-ops, and the HUD projects `snapshot.run_time_ms` without a second timer.

`GameState.record_run_summary(result)` is called at the approved Profile persistence boundary after one terminal fact. It deep-copies result collections and updates completed runs, victories, best rooms, and the last-run summary without recreating live-run authority.

## Direct room and terminal routing

Domain transitions do not depend on EventBus subscription order:

```text
Player HealthComponent.died
  -> RoomController
  -> RoomRuntime.report_player_died
  -> authoritative player_died command
  -> RoomRuntime.terminal_committed
  -> RunRuntimeHost publishes run_ended

Enemy HealthComponent.died
  -> RoomController
  -> RoomRuntime.report_entity_died
  -> EncounterRunner.notify_entity_defeated
  -> room completion command

Boss enemy_summoned
  -> RoomController registers the summon through RoomRuntime
  -> EncounterRunner acknowledgement sets encounter ownership
  -> one enemy_spawned typed fact
```

Rejected player-death commands preserve the active room and emit no terminal commit. Duplicate room completion, selection, death, and terminal commands are idempotently rejected.

## Typed gameplay fact boundary

EventBus retains exactly 14 typed signals:

```text
damage_about_to_apply, damage_applied, hit_confirmed, entity_died,
run_started, room_started, room_cleared, reward_selected, run_ended,
player_attacked, player_dashed, enemy_spawned,
time_skill_started, time_skill_ended
```

Lifecycle signatures include `run_id` and post-command `revision`. Attack, dash, spawn, and time-skill signals include frozen context dictionaries. Payload dictionaries are deep copies before lifecycle emission.

The five-room lifecycle contract verifies these exact successful counts:

```text
run_started       1
room_started      5
room_cleared      5
reward_selected   4
run_ended         1
duplicate IDs     0
```

Failed start, stale selection, duplicate selection, duplicate room completion, duplicate terminal command, rejected actions, duplicate damage, and rejected time skills publish no additional fact.

## Source contracts

`run_authority_contract_test` recursively scans production GDScript/scenes and the M1 seed probe. It rejects reintroduction of GameState live-run fields/methods, LegacyRunAdapter, legacy runtime flags, and legacy HUD/selection nodes.

`event_bus_source_contract_test` recursively scans `autoload/` and `scripts/`. It rejects:

```text
EventBus.publish / publish_deferred / subscribe / unsubscribe
generic handler and deferred-event storage
generic publication method definitions
EventBus connections in RunOrchestrator, RunRuntimeFacade,
RunRuntimeHost, RoomRuntime, RoomController, or EncounterRunner
```

`tools/test_ci_contract.sh` proves all three event contracts are included in stable scene discovery and that `validate_project.sh` runs the unfiltered scene-test entrypoint.

## Verification evidence

Focused gates passed without new leaks:

```text
run_authority_contract
event_bus_source_contract
run_lifecycle_publication
combat_event_publication
run_runtime_host
room_runtime
encounter_runner
rewind (3 scenes)
time_stop_resistance
combat_feedback_runtime
controller_focus_flow
m1_runtime_smoke
reward_system_smoke
```

`reward_system_smoke` retains its previously registered known ObjectDB warning. No new ObjectDB or RID leak was introduced.

The unified command `./tools/validate_project.sh` passed on Godot `4.6.1.stable.official.14d19694e` with logs at:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.mp2UVl
```

The unified result was:

| Gate | Result |
|---|---:|
| Godot scene tests | 59 / 59 passed |
| Documentation governance | 28 / 28 passed; zero violations and zero baseline entries |
| Localization contracts | 7 / 7 passed |
| Playtest-data contracts | 13 / 13 passed |
| M1 release-gate contracts | 27 / 27 passed |
| GDScript coverage contracts | 5 / 5 passed |
| Export contracts | 37 / 37 passed |
| Bootstrap and clean imports | Passed with only approved macOS sandbox environment warnings |

## Honest remaining boundaries

- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`; scene counts are not presented as line coverage.
- Windows, Linux, and macOS export templates remain unavailable locally, so real packaged startup is not certified.
- Authentic external playtests remain `0 / 20`; synthetic or deterministic runs do not replace human evidence.
- No remote push, public build publication, signing, store configuration, paid service, or private credential use occurred.

P4/P5 is therefore `Verified Locally`. P7/P9 export/coverage certification and the external M1 human-evidence gate remain active without weakening their fail-closed status.
