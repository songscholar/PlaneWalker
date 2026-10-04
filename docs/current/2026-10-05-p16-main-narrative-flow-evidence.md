# Production Main Narrative Flow Evidence

- Status: Implemented / Current
- Document Role: Current focused native integration evidence
- Authority Level: Main terminal narrative, settlement and credits handoffs
- Applies To: Main, NarrativeFlowCoordinator, RunEndOverlay and NativeRoomPresentation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16o-native-narrative-flow-design.md`, `docs/current/2026-10-05-p16-main-profile-flow-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native terminal handoffs verified; full five-boss combat and combined product certification pending

Main owns the production narrative coordinator and one separately owned occurrence parent. A durable Launch binds its actual Registry, Profile, Run, Player and RoomSceneHost. Victory preserves the visible final room, disables ordinary Player/gameplay processing, hides combat HUD and summary panels, and installs only the service-issued final-heart occurrence. The coordinator's terminal traversal moves the real CharacterBody while advancing no action, weapon, time, reward, replay or domain clock. The Player's collision body remains available after processing is disabled.

Actual Area2D overlap saves the fifth fragment before presenting endings. A saved explicit ending triggers Main settlement. A failed physical settlement preserves the launch, saved choice and retry button. Success opens that ending's separately saved credits. A fresh Main plus physical Profile reload resumes unfinished credits; it spends neither another launch sequence nor a second settlement. Durable credits refresh GameState and return to the native Hub. Duplicate terminal notifications preserve the active token and focus instead of reinstalling or obscuring the flow.

Actual OpenGL screenshots exposed an additional production presentation defect: the opaque legacy Floor covered the native room and the legacy camera halved its 640 by 360 design canvas. NativeRoomPresentation now frames the actual CameraBounds, uses PlayerEntry on confirmed room transitions, disables legacy geometry/collision for Launch, and provides physical outer walls on the native canvas. It restores the legacy presentation and retires native walls on Hub return. During checkpoint restoration, a Host-issued restoration flag suppresses entry repositioning so the saved Player position can remain authoritative. Production Launch also hides the legacy debug instructions.

## Verification

- Missing Main narrative boundary RED: `build/test-logs/p16-main-narrative-red`.
- Missing actual room framing RED: `build/test-logs/p16-native-room-presentation-red`, three intended failures and no script errors/leaks.
- Focused Main terminal/physical-restart/entry GREEN: `build/test-logs/p16-native-room-entry-final`, one scene.
- Final focused regression after Narrative review fixes GREEN: `build/test-logs/p16-main-narrative-final-commit`, one scene, no runtime failures or leaks.
- Main regression GREEN: `build/test-logs/p16-main-native-presentation-regression`, six scenes covering floor effects, native narrative, physical death settlement, Hub commands, Hub flow and visual layout contracts.
- Native OpenGL GREEN: `build/p16-main-narrative-native-final.log`, actual physical contact, settlement failure/retry, separate credits persistence and fresh Main restart. Six PNGs are below `build/visual-evidence/p16-main-narrative`. Final-fragment, ending-choice and reloaded-credits images were directly inspected. Final logs contain no script errors, engine errors, warnings or leaks.

The test builds the five-floor terminal through the existing deterministic domain fixture with authenticated source receipts and actual native room scenes. It isolates final-flow integration; it does not prove that all five production Boss encounters are completable without a fixture. Room art remains the existing Pixel Proxy shell. Full hostile integration, mid-combat restore, training, Expansion and export certification remain separate gates. Intermediate parse and presentation failures are retained as diagnostics, not counted as passing evidence.
