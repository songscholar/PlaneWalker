# Plane Walker Encounter Timer Lifecycle Evidence

- Status: Implemented / Current
- Document Role: Current focused native encounter lifecycle evidence
- Authority Level: EncounterRunner phase ownership and cancellation
- Applies To: EncounterRunner delays, warnings, pause, and retirement
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16-native-floor-entry-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native timer lifecycle verified; complete product certification pending

EncounterRunner owns a physics Timer for each pending delay or warning. Pause inherits the runner's pause policy; cancellation, failure, or leaving the scene removes the Timer and retires its continuation. Reentrant wave/warning callbacks recheck the generation before publishing a later phase.

RED: `build/test-logs/p16-encounter-timer-red` exposes the unowned SceneTreeTimer, warning progression while paused, and retirement leak. GREEN: `build/test-logs/p16-encounter-timer-final` covers pause, resume, and cancellation. Regression: `build/test-logs/p16-encounter-runner-regression`. Actual Main room retirement is also clean in `build/test-logs/p16-main-profile-save-retry-final`. Final logs contain no script errors or leaks. The earlier verbose Main leak log is retained as failure evidence.

This fixes lifecycle behavior of the existing native runner. It does not certify the new launch enemy and payload encounter authority or all forty recipes in production.
