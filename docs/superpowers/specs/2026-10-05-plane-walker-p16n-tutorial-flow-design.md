# P16N Native Tutorial Flow

- Status: Approved / Current
- Document Role: Current focused tutorial flow specification under standing project authorization
- Authority Level: Native tutorial presentation and physical Profile integration below P16
- Applies To: TutorialFlowCoordinator, actual Host/Player bindings, review pause ownership and saved hints
- Owner: Project onboarding implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-05-p16l-tutorial-ui-evidence.md`
- Last Verified: 2026-10-05
- Implementation Status: Coordinator implemented and verified; production Main routing follows in its owning milestone

`TutorialFlowCoordinator` owns the review panel and saved-hint presenter in a
CanvasLayer. It configures from the active Registry, physical
ProfileRuntimeService, actual RunRuntimeHost and Player, and current
InputRemapService. Domain progress remains in ProfileRuntimeService.

Binding freezes the Host's Run object, Player instance and character generation,
and durable launch identity. Only the adapter returned by that service may be
drained. Before and after physical persistence, those identities must still be
current. Hints are projected exclusively from successful `context.hints`, never
from adapter notifications or unpersisted pending receipts.

Hub, suspended/paused scenes, review modals, retired or replaced participants,
and terminal runs cannot consume observations. Failed saves keep receipts and
commands retryable. A publication recovery clears presentation and restores
the service-issued adapter only through native physical recovery.

Review may be opened from keyboard F1 or a parent menu for controller use.
Closing releases only a pause acquired by this review and only for the same
participants. Existing external pause ownership remains intact. Remapped
bindings and locale changes render current semantic labels.

Hub training requests are forwarded with the current revision; no receipts or
rewards are fabricated. Guided mode remains unavailable in this production
coordinator until an independent launch policy is frozen and verified. A view
capability separates training availability from guided policy availability.

Completion requires actual Main/Host/Player/Profile integration, physical save
fault injection, stale generation and publication callback checks, native
keyboard/controller review, focused regression and scanned Godot logs.
