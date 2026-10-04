# P16R Native Training Arena

- Status: Approved / Current
- Document Role: Current focused native training presentation and Boss drill specification
- Authority Level: Implementation below P16 and P16P under standing project authorization
- Applies To: Independent training arena, selectors, controller focus and actual Boss conversion
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16p-native-training-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Six drills, safe native retirement and bilingual arena rendering verified locally

## Native Arena And Controls

`TrainingFlowCoordinator.configure(registry, service)`, `open(task_id = "")`,
`close()`, `is_training_active()` and `closed` are Main's narrow integration
boundary. It owns an independent 640x360 arena, Camera2D and CanvasLayer.
Actual native Players use the existing training foundation. Walls bound the
practice floor; a real Health/Hurtbox target permits weapon practice. Original
deterministic pixel raster artwork has recorded CC0 provenance.

Four OptionButtons select authored tasks, all five characters, all five weapons
and six time pairs. Selection first drains pending saves, then recreates the
native attempt. Reset uses the same safe lifecycle. Back drains before closing;
a failed write keeps the old attempt and controls recoverable. Symbolic play,
reset and back tools have localized tooltips. Controller focus follows the
existing FocusCoordinator; configuration pauses only the owned Player.
Gameplay and configuration modes never pause the SceneTree or alter Main.

The toolbar uses two fixed rows, leaving the bounded arena visible. Bottom
status shows durable objective counts, first-completion state and actual HP/time
energy. Text is localized through the existing CSV workflow. Text scale 1.0/1.5
and 640x360/1280x720 native windows must fit without overlapping controls.

## Actual Boss Conversion

T-05 uses the existing BossChronoWarden scene, identity and action engine. The
training adapter freezes that exact Boss, Health and parent. Conversion is
derived only from a successful accepted Stop frame whose actual TimeManager
target list contains that Boss, whose exact Stop source is installed on the
Boss, and whose native action is WINDUP/RECOVERY with an exposed window and a
positive actual action delay. Boss immunity converts Stop into delay/exposure;
the drill must not require the ordinary enemy frozen flag.

The adapter records the actual before/after action window from the owned
training frame path and rejects an idle Boss, foreign target, stale Boss/Health,
wrong time ability, public frame signal and rejected native frame. It seals one
`boss_conversion` observation through the existing physical Profile boundary.
No public fabricated receipt or production `force_*_for_test` call is allowed.
Weapon damage during the converted window is a later full Boss combat gate.

## Alternatives And Verification

A shared Main arena would entangle active launch ownership; a separate arena
fits the existing training lifecycle. Replacing the proven Boss engine would
duplicate action rules; the actual scene preserves authored attacks and immunity.
A broad legacy Boss rollback rewrite is outside this focused slice. No complete
five-Boss production or full Launch certification is claimed.

Completion requires missing endpoint RED, actual selection/reset/back flows,
safe physical-save refusal, task-five native acceptance and refusal, one-time
reward after physical reload, controller events, text scaling, bilingual native
screenshots, nonblank raster inspection and scanned engine logs.
