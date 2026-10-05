# P21A Native Boss Rush Implementation

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Focused execution plan
- Applies To: Native Boss Rush, stage checkpoint and Hub entry
- Owner: Runtime integration lane
- Depends On: `../specs/2026-10-05-p21a-native-boss-rush-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Boss Rush native/storage and Main tests, eight native visual combinations, localization/governance validation and error/leak-free logs must pass before the focused commit.

1. Write a failing native/storage test for the actual five-stage flow and forged-notice refusal.
2. Add the authored catalog and strict aggregate checkpoint protocol.
3. Bind native Player/Boss/room/bridge/effects to RunOrchestrator stages, preserving selected loadout and explicit fresh-stage preset.
4. Add physical launch/completion/retry/continued checkpoints without regular Meta settlements.
5. Integrate actual Hub controls, gameplay HUD, stage summary and return workflow.
6. Exercise native/UI/regression tests, retain raster evidence and document recovery limits.
7. Commit the precise file set and extend daily/authored/endless modes.
