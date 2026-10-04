# P16O Native Narrative Flow

- Status: Approved / Current
- Document Role: Current focused native narrative specification under standing authorization
- Authority Level: Native occurrence and presentation boundary below P16
- Applies To: NarrativeFlowCoordinator, native dialogue/story/ending/credits views and actual contact
- Owner: Project narrative implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Native coordinator, strict views and actual contact verified; Main handoff evidence owned by the parent milestone

Configure with the actual Registry, physical Profile service, RunRuntimeHost,
RoomSceneHost, Host-owned Player and combat runtime parent. Domain sources,
dialogue eligibility, ending predicates and command persistence remain owned by
the physical service. Presentation consumes detached strict views.

Freeze Run/Player/generation and active RoomSceneHost generation around commands.
Retired scenes, different bodies, stale revisions, forged signals and failed
physical promotion cannot display saved content or publish completion. Occurrence
callbacks require the exact service-issued Area2D, actual Player overlap and an
active authored room anchor. No narrative rewards or receipts are fabricated.

At canonical final victory, install heart_fragment_5 at the actual boss room's
room_exit anchor while the durable launch receipt remains active. The Player
must contact the Area2D before collection is persisted and ending choice is
presented. Main must keep neutral Player movement possible and suppress combat,
Host progression and the old terminal overlay until contact and final choice.
Coordinator traversal calls only actual CharacterBody2D.move_and_collide and
retains the actual collision body with DISABLE_MODE_KEEP_ACTIVE. It freezes and
restores the original disable mode for the exact Run/Player/generation. It never
advances Player action, time, reward, health or replay participants.

Ending selection is saved before ending_selected is emitted. Main then settles
the native terminal exactly once and calls show_selected_credits. Credits have
their own durable completion command; interrupted or skipped credits can resume
from the saved selection and settled Profile before returning to Hub.

The coordinator also supports actual NPC dialogue and occurrence choice/story
panels, source installation, authored content recall and retirement. Native
selection safety and explicit focus scopes suppress gameplay while interactive
panels are open. All UI uses existing bilingual authored strings and native
safe-area/accessibility patterns.

The current native placement fallback uses the one authored room_exit anchor in
each room template. Cleared rooms present one eligible authored floor occurrence
at a time, prioritizing that floor's actual defeated boss heart. Hidden steps and
choices remain subject to authored sequence and prerequisites. This is a working
contact placement fallback; distinct authored environmental locations remain a
future scene/content production milestone.

Completion requires missing-feature RED, native physical contact/failure tests,
five ending projections, stale callbacks, independent saves and recoveries,
controller/UI bounds, actual raster markers, log scans and focused commits.
