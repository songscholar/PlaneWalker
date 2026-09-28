# Plane Walker Wave 4C Pixel Presentation and Combat Feedback Implementation Plan

> **For agentic workers:** Execute each task with tests first and keep Wave 4B encounter/gameplay files unchanged.

**Goal:** Deliver a complete M1 Pixel Proxy, core animation, synthesized audio, and combat-feedback layer without changing gameplay timing or collision contracts.

**Architecture:** Extend the existing `CombatFeedback` autoload into a presentation coordinator. New focused presentation nodes render programmatic pixel actors, overlays, deterministic camera trauma, and offline PCM audio from existing gameplay signals.

**Tech Stack:** Godot 4.6, typed GDScript, CanvasItem drawing, Tween-free deterministic state timers, `AudioStreamWAV`, existing serial scene-test harness.

## Global Constraints

- Logical resolution remains 640×360 with integer scaling.
- Presentation RNG must never consume gameplay RNG.
- Presentation code must not modify collision, attack ranges, action clocks, encounter state, run phase, HP, energy, or cooldowns.
- Do not modify `encounter_runner`, `room_controller`, `run_director`, or `m1_room_plan`.
- Scan headless logs for script errors and ObjectDB/RID leaks.

---

### Task 1: Lock the presentation contract with failing tests

**Files:**
- Create: `tests/presentation/combat_feedback_runtime_test.gd`
- Create: `tests/presentation/combat_feedback_runtime_test.tscn`

**Interfaces:**
- Consumes: `CombatFeedback`, existing player/enemy scenes, `DamageInfo` tags.
- Produces: executable expectations for proxy roles, animation states, hit profiles, audio cues, overlays, and cleanup.

- [ ] Write assertions that require idempotent player/enemy proxy installation and hidden legacy visuals.
- [ ] Require light/finisher/heavy/player-hurt profiles to return 3/5/6/2 pause frames and distinct camera/audio values.
- [ ] Require at least eight non-empty generated audio cues and distinct Time Stop/Rewind wave data.
- [ ] Require attack, dash, windup, hit, and time overlay snapshots to be deterministic and pixel snapped.
- [ ] Run `godot --headless --path . --scene tests/presentation/combat_feedback_runtime_test.tscn` and confirm the missing presentation API fails.

### Task 2: Implement Pixel Proxy actors and core animation

**Files:**
- Create: `scripts/presentation/pixel_proxy_actor.gd`
- Create: `scripts/presentation/pixel_proxy_afterimage.gd`

**Interfaces:**
- Consumes: actor `Visual`, `HealthComponent`, velocity, player action snapshot, enemy attack-phase signal, Boss UI snapshot.
- Produces: `bind_actor(actor)`, `play_action(action_id)`, `spawn_afterimage(path_position)`, `get_snapshot_for_test()`.

- [ ] Render role-specific hard-edge silhouettes on a two-pixel grid.
- [ ] Add idle, movement, attack, dash, time cast, windup, recovery, hit, heal, and death state timers.
- [ ] Emit cue requests for enemy/Boss windups and keep all transforms integer snapped.
- [ ] Add bounded dash/rewind afterimages that free themselves.
- [ ] Run the focused presentation scene and make proxy/animation assertions pass.

### Task 3: Implement synthesized audio and screen/camera feedback

**Files:**
- Create: `scripts/presentation/combat_audio_synth.gd`
- Create: `scripts/presentation/combat_feedback_overlay.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/combat/health_component.gd`

**Interfaces:**
- Consumes: `EventBus.hit_confirmed`, time-skill, dash, attack, death, spawn, and run-end signals.
- Produces: hit feedback classification, generated cue library, overlay modes, camera trauma, actor decoration, test snapshots.

- [ ] Generate deterministic mono 16-bit PCM cue streams for attacks, light/heavy hits, player hurt, dash, danger, Time Stop, Rewind, windup, and death.
- [ ] Centralize hit pause in `CombatFeedback` so presentation subscribes to domain events rather than the health component calling presentation directly.
- [ ] Add deterministic camera offset trauma with exact baseline restoration.
- [ ] Add hard-edge damage/low-HP/time overlays and cleanup on run end.
- [ ] Route actor-local cues and rewind transaction paths through the coordinator.
- [ ] Run the focused presentation scene and verify every audio/profile/overlay assertion.

### Task 4: Polish damage-number UI feedback

**Files:**
- Modify: `scripts/ui/floating_text_layer.gd`
- Test: `tests/presentation/combat_feedback_runtime_test.gd`

**Interfaces:**
- Consumes: existing `EventBus.hit_confirmed` payload.
- Produces: pixel-snapped, outlined, role/tag-colored, lifetime-bounded damage labels.

- [ ] Snap spawn and drift endpoints to logical pixels.
- [ ] Distinguish heavy, finisher, time, enemy melee, and enemy projectile hits through prefix, scale, and palette.
- [ ] Use hard-edge outline and stepped scale/fade motion without gameplay RNG.
- [ ] Verify labels self-delete and do not leak after the test.

### Task 5: Verify Wave 4C end to end

**Files:**
- Create: `docs/current/2026-09-28-wave-4c-pixel-feedback-evidence.md`

**Interfaces:**
- Consumes: focused tests and repository validation entrypoint.
- Produces: reproducible test commands, results, limitations, and rollback scope.

- [ ] Run the focused headless presentation test and scan its full log.
- [ ] Run all presentation/combat/time tests affected by the event integration.
- [ ] Run `./tools/validate_project.sh` and inspect import/test logs for script errors and ObjectDB/RID leaks.
- [ ] Record results, generated cue policy, and remaining human-feel validation in the evidence document.
- [ ] Stage only Wave 4C-owned files and create one focused local commit.

## Plan self-review

- Every executable Wave 4C criterion maps to a task.
- Interfaces are additive and do not require edits to Wave 4B encounter ownership files.
- Test commands and expected gates are explicit.
- No final-art or external-audio dependency blocks M1 completion.
