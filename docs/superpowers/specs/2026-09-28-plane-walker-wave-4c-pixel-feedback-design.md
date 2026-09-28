# Plane Walker Wave 4C Pixel Presentation and Combat Feedback Design

- Status: Approved / Current
- Authority Level: Current implementation design
- Applies To: M1 Pixel Proxy, core actor animation, combat audio, camera/VFX, hit/danger/time-power/UI feedback
- Implementation Status: Ready for execution
- Owner: UI and pixel presentation lane
- Depends On: `AGENTS.md`, full-product completion design, staged M1 combat-feel and pixel-canvas gates
- Supersedes: Temporary Polygon-only greybox presentation for M1 actors
- Last Verified: 2026-09-28
- Completion Gate: focused presentation tests plus `./tools/validate_project.sh`

## Outcome

Wave 4C delivers a complete, replaceable M1 presentation layer without changing gameplay collision, attack ranges, action clocks, encounter definitions, or gameplay RNG. The final-art pipeline remains asset-ID compatible, while the playable build no longer depends on unanimated single-color polygons or silent combat.

## Architecture

`CombatFeedback` remains the single presentation coordinator. It listens to existing typed `EventBus` signals, discovers player and enemy actors, installs a `PixelProxyActor` beside each actor's gameplay nodes, and coordinates:

- hit-stop profiles derived from immutable damage tags;
- deterministic camera trauma that never consumes gameplay RNG;
- a full-screen hard-edge overlay for damage, low health, Time Stop, and Rewind;
- programmatically generated, offline-safe PCM sound cues;
- actor-local idle, move, attack, dash, cast, windup, recovery, hit, heal, and death animation states;
- rewind path afterimages and dash silhouettes;
- pixel-staged floating damage text.

The gameplay actor remains authoritative. `PixelProxyActor` reads presentation-safe state and signals but never writes HP, energy, action state, cooldowns, collision, velocity, encounter state, or run phase. Existing `Visual` polygons remain as palette/state inputs and are hidden only after the proxy is bound successfully.

## Pixel Proxy language

- Pixel unit: two logical pixels at the 640×360 canvas.
- Player: cyan/white hood and blade, dark navy body, forward-facing accent.
- Chaser: red angular silhouette with a bright leading edge.
- Shooter: amber split silhouette with a ranged core.
- Tank/elite: violet block silhouette; elite state adds a gold crown/ring.
- Chrono Warden: magenta 48-pixel clock silhouette with cyan temporal core.
- Every role has a distinct silhouette even when rendered in monochrome.
- Animation transforms and effect anchors snap to integer logical pixels.
- Actor footprints and two-pixel units are defined in screen space, so the combat camera's `0.5` zoom does not halve their intended 640×360 readability.
- Afterimages inherit the source proxy's active action scale and camera inverse scale, and snap their world origin/drift to the same two-screen-pixel grid.
- Attack blade direction and lunge offset read the weapon angle; dash displacement and stretch read the actor's facing. The proxy never writes either source.
- Boss phase, exposure, and Time Stop each have shape, luminance, or texture cues in addition to palette changes.
- Time Stop uses cyan horizontal scan bands; Rewind uses indigo chevrons and reverse trails; danger uses amber/red concentric pulses.

## Combat-feel profiles

| Event | Hit pause | Camera | Audio/visual identity |
|---|---:|---:|---|
| Light sword hit | 3 frames | 3 px | short bright click, white/cyan spark |
| Combo finisher | 5 frames | 6 px | layered impact, larger cross spark |
| Heavy hit | 6 frames | 8 px | low transient, strongest shake/flash |
| Player damaged | 2 frames | 8 px | low warning tone, red edge flash |
| Dash | none | 1 px | short air tick, cyan afterimage |
| Enemy/Boss windup | none | 1–2 px | amber riser; Boss action families use distinct pitch groups |
| Time Stop | none | 2 px | high crystalline chord, cyan scan bands |
| Rewind | none | 3 px | descending reverse chirp, indigo path trail |

Overlapping hit pauses extend the active deadline and never shorten an existing pause. Presentation reset restores camera offset and engine time scale on run end or explicit test cleanup.
The deadline uses Godot's monotonic real-time clock, so the requested duration is independent of rendered FPS and scaled gameplay time.

Camera shake, hit flash, and reduced-motion behavior are runtime-configurable through `CombatFeedback.set_feedback_options()`. Reduced motion disables shake and afterimages, freezes continuous overlay motion, and preserves static action readability.
The three accessibility options are persisted in `GameState.settings`, merged into legacy saves with compatible defaults, and exposed through the existing pause/settings panel.

Presentation hot paths use typed actor capabilities plus cached player and `HealthComponent` references. Property-list reflection is not performed during animation or low-health updates.

## Audio policy

M1 audio is generated at runtime into mono 16-bit PCM `AudioStreamWAV` resources. This provides licensed, repository-local, offline-safe cues without binary asset provenance risk. Cue synthesis is deterministic and uses a private local pseudo-random noise sequence; it never reads `SeedService` or gameplay RNG. Later authored WAV/OGG files can replace cue streams behind the same cue IDs.

## Error handling

- Actors without a `Visual` child retain their original rendering and are skipped safely.
- Audio playback failure does not affect gameplay and is observable through the cue contract/history.
- Camera feedback degrades to overlay/audio when no active camera exists.
- Proxy installation is idempotent and reconnect-safe.
- Freed actors, interrupted rewinds, scene transitions, and run end clear transient references.

## Executable completion criteria

1. Player, Chaser, Shooter, Tank/elite, and Chrono Warden resolve to different Pixel Proxy roles and palettes.
2. Proxy installation hides the original greybox only after successful binding and does not change collision or gameplay state.
3. Core action states expose deterministic, pixel-snapped animation snapshots.
4. Light, finisher, heavy, and player-damage profiles meet the M1 frame windows.
5. Time Stop, Rewind, danger, hit, dash, and UI cues have distinct audio and visual contracts.
6. Rewind and dash produce transient afterimages without consuming gameplay RNG.
7. Damage text is readable, pixel-snapped, tag-colored, and lifetime-bounded.
8. Focused headless tests pass without script errors, ObjectDB leaks, or RID leaks.
9. Full project validation passes, with no new classified warning.
10. Real `Camera2D` position/zoom coverage proves floating text and proxy screen size remain correct.
11. Simulated 30, 60, and 144 FPS schedules restore hit pause at one real-time deadline.

## Self-review

- No placeholders or deferred M1 requirements remain.
- The design preserves Wave 4B action identities and timings.
- Presentation is isolated from gameplay state and deterministic seed channels.
- Final art and authored audio can replace proxies without changing gameplay interfaces.
