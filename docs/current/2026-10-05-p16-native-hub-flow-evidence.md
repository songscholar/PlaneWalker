# Plane Walker Native Main Hub Flow Evidence

- Status: Implemented / Current
- Document Role: Current focused native production Hub evidence
- Authority Level: Main entry, Hub panels, and Profile command routing
- Applies To: Main, HubFlowCoordinator, HubPanelView, HubRuntimeFacade, and TutorialFlowCoordinator
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16-main-profile-flow-evidence.md`, `docs/current/2026-10-05-p16n-tutorial-flow-evidence.md`, `docs/current/2026-10-05-p16-native-hub-shell-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native entry and focused commands verified; complete P16 and product certification pending

Production Main opens one actual Hub district with original pixel art, a native walker, NPC interaction, three direct destinations, district travel, settings, and a physical-controller Back menu entry. A separate CanvasLayer keeps the Hub raster independent of the combat camera. All nine destinations open closed authoritative projections: council, archive, gateway, training review, forge, meditation, merchant status, gallery, and mirror. Profile ownership and candidate validation supply prices, prerequisites, availability, forge preferences, build operations, and dialogue choices.

Real controls persist Meta purchases, sword upgrades, named builds, removal, and owned loadout selection through ProfileRuntimeService. Save promotion failures leave the entire Profile unchanged and retain retry controls. Retired callbacks cannot repeat a purchase or launch. A stale revision refreshes the owned projection, and rejected loadout controls restore the authoritative selection. Returning from lesson review refreshes the Hub after independent Profile changes. Gateway launch remains reachable in the fixed footer at large text scale.

Main binds tutorial observation to the actual launched Run and Player, handles review before dungeon/pause commands, and retires the observer at actual terminal state. The training destination opens the actual lesson panel. Practice drills and guided-run policy still need their own native bootstrap and physical service boundary; this evidence does not claim those features complete. Optional daily/leaderboard/social providers truthfully report unavailable and do not block the base launch.

RED: `build/test-logs/p16-main-hub-red` exposes the missing production Hub. Focused GREEN: `build/test-logs/p16-main-hub-native-final` covers native navigation, real physical-controller entry/cancel, tutorial review, durable gateway launch, purchase promotion failure/retry, exact cost, forge, build create/select/remove, physical JSON reload, and stale revision recovery. Main death settlement regression: `build/test-logs/p16-main-profile-tutorial-regression`. All final passing scene logs contain no script errors or leaks.

The 192 native OpenGL captures are retained under `build/p16-main-hub-screenshots`: three scene views and nine panels, Chinese/English, 640x360, 1280x720, 1920x1080, 3440x1440, and text scales 1.0/1.5. Final renderer log: `build/p16-main-hub-complete-visual.log`, PASS with no script errors or leaks. The native visual test checks nonblank pixels, chrome minimum sizes and viewport bounds, and the full centered Hub raster transform. Chinese large-text council scene and gateway, and English large-text council panel were visually inspected. Earlier runs exposed a combat-camera half-scale bug, large-text footer overflow, incomplete localization imports, and intermediate contract edits; those failures remain diagnostic evidence rather than certification.

Final-heart traversal, actual ending/credits presentation, complete in-flight resume, training, guided runs, complete enemy/boss production integration, Expansion providers, and clean export remain active program work.
