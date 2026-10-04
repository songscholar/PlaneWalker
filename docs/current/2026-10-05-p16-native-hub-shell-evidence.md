# Plane Walker Native Hub Scene Evidence

- Status: Implemented / Current
- Document Role: Current focused native scene evidence
- Authority Level: Native Hub scene shell and original pixel asset production
- Applies To: HubSceneHost, HubDistrictScene, three district scenes, and their native tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native scene shell verified; nine destination business panels and Main flow remain pending

The three native districts consume the actual authored Hub JSON and stream one scene at a time. Each has an independent 640x360 raster, three NPCs, and a Hub-only walker. Actual InputMap movement reaches all nine NPC destinations. Nearby interaction and an accessible epoch-checked route publish the authored function IDs; paused, disabled, invented, and retired controls cannot publish. Arbitrary scene paths are refused before replacing the active scene. Combat Player/loadout state is independent from this shell.

`tools/generate_hub_assets.py` deterministically creates the four PNGs and a hash manifest from original procedural pixel artwork, licensed CC0-1.0 without third-party sources. Pack activation and business interactions are separate gates.

Focused GREEN: `build/test-logs/p16-hub-streaming-native`, one native scene test, no script errors or leaks. The earlier `p16-hub-streaming-green` correctly failed because the Hub category was not yet active in Registry. The shell test now explicitly reads authored JSON and does not claim Registry activation.

Real OpenGL visual GREEN: `build/test-logs/p16-hub-native-visual.log`. Forty-eight screenshots under `build/p16-hub-screenshots` cover three districts, Chinese/English, 640x360/1280x720/1920x1080/3440x1440, and text scales 1.0/1.5. Rendered pixel diversity and localized Label minimum/viewport bounds pass. The Chinese council screenshot at 640x360/1.5 was inspected directly. Settings changes are in-memory within an isolated test process. The log contains no errors or leaks.

This is not a completed Hub product flow, full P16 certification, export certification, or human playtest evidence.
