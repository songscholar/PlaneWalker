# Plane Walker Wave 4C Pixel Presentation and Combat Feedback Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Verified M1 presentation implementation record
- Applies To: M1 Pixel Proxy, synthesized audio, combat feedback, presentation cleanup, and accessibility presentation gates
- Implementation Status: M1 technical scope complete and retained in candidate `79a20fd183fb57b8bdf62019ab80ff3f6e430635`
- Owner: UI and pixel presentation lane
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/specs/2026-09-28-plane-walker-wave-4c-pixel-feedback-design.md`
- Last Verified: 2026-09-28
- Completion Evidence: `docs/current/2026-09-28-wave-4c-pixel-feedback-evidence.md` and candidate commit `79a20fd183fb57b8bdf62019ab80ff3f6e430635`
- Evidence: `docs/current/2026-09-28-wave-4c-pixel-feedback-evidence.md`

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

- [x] Write assertions that require idempotent player/enemy proxy installation and hidden legacy visuals.
- [x] Require light/finisher/heavy/player-hurt profiles to return 3/5/6/2 pause frames and distinct camera/audio values.
- [x] Require at least eight non-empty generated audio cues and distinct Time Stop/Rewind wave data.
- [x] Require attack, dash, windup, hit, and time overlay snapshots to be deterministic and pixel snapped.
- [x] Run the focused presentation contract through its red state before implementation.

### Task 2: Implement Pixel Proxy actors and core animation

**Files:**
- Create: `scripts/presentation/pixel_proxy_actor.gd`
- Create: `scripts/presentation/pixel_proxy_afterimage.gd`

**Interfaces:**
- Consumes: actor `Visual`, `HealthComponent`, velocity, player action snapshot, enemy attack-phase signal, Boss UI snapshot.
- Produces: `bind_actor(actor)`, `play_action(action_id)`, `spawn_afterimage(path_position)`, `get_snapshot_for_test()`.

- [x] Render role-specific hard-edge silhouettes on a two-pixel grid.
- [x] Add idle, movement, attack, dash, time cast, windup, recovery, hit, heal, and death state timers.
- [x] Emit cue requests for enemy/Boss windups and keep all transforms integer snapped.
- [x] Add bounded dash/rewind afterimages that free themselves.
- [x] Run the focused presentation scene and make proxy/animation assertions pass.

### Task 3: Implement synthesized audio and screen/camera feedback

**Files:**
- Create: `scripts/presentation/combat_audio_synth.gd`
- Create: `scripts/presentation/combat_feedback_overlay.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/combat/health_component.gd`

**Interfaces:**
- Consumes: `EventBus.hit_confirmed`, time-skill, dash, attack, death, spawn, and run-end signals.
- Produces: hit feedback classification, generated cue library, overlay modes, camera trauma, actor decoration, test snapshots.

- [x] Generate deterministic mono 16-bit PCM cue streams for attacks, light/heavy hits, player hurt, dash, danger, Time Stop, Rewind, windup, and death.
- [x] Centralize hit pause in `CombatFeedback` so presentation subscribes to domain events rather than the health component calling presentation directly.
- [x] Add deterministic camera offset trauma with exact baseline restoration.
- [x] Add hard-edge damage/low-HP/time overlays and cleanup on run end.
- [x] Route actor-local cues and rewind transaction paths through the coordinator.
- [x] Run the focused presentation scene and verify every audio/profile/overlay assertion.

### Task 4: Polish damage-number UI feedback

**Files:**
- Modify: `scripts/ui/floating_text_layer.gd`
- Test: `tests/presentation/combat_feedback_runtime_test.gd`

**Interfaces:**
- Consumes: existing `EventBus.hit_confirmed` payload.
- Produces: pixel-snapped, outlined, role/tag-colored, lifetime-bounded damage labels.

- [x] Snap spawn and drift endpoints to logical pixels.
- [x] Distinguish heavy, finisher, time, enemy melee, and enemy projectile hits through prefix, scale, and palette.
- [x] Use hard-edge outline and stepped scale/fade motion without gameplay RNG.
- [x] Verify labels self-delete and do not leak after the test.

### Task 5: Verify Wave 4C end to end

**Files:**
- Create: `docs/current/2026-09-28-wave-4c-pixel-feedback-evidence.md`

**Interfaces:**
- Consumes: focused tests and repository validation entrypoint.
- Produces: reproducible test commands, results, limitations, and rollback scope.

- [x] Run the focused headless presentation test and scan its full log.
- [x] Run all presentation/combat/time tests affected by the event integration.
- [x] Run `./tools/validate_project.sh` and inspect import/test logs for script errors and ObjectDB/RID leaks.
- [x] Record results, generated cue policy, and remaining human-feel validation in the evidence document.
- [x] Stage only Wave 4C-owned files and create focused local commits.

## Plan self-review

- Every executable Wave 4C criterion maps to a task.
- Interfaces are additive and do not require edits to Wave 4B encounter ownership files.
- Test commands and expected gates are explicit.
- No final-art or external-audio dependency blocks M1 completion.

## Completion outcome

Wave 4C's M1 technical scope is complete. The final candidate retains Pixel Proxy actors, deterministic synthesized audio, hit/danger/time feedback, camera and VFX cleanup, pixel-snapped damage text, persisted camera-shake/hit-flash/reduced-motion settings, and the associated focused and repository regressions.

Repository Gate `PASS` was verified on candidate `79a20fd183fb57b8bdf62019ab80ff3f6e430635`. The remaining human mix/readability judgment is external evidence, not unfinished Wave 4C code and not authorization for experience tuning.
