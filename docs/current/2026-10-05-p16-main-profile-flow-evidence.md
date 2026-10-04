# Plane Walker Main Profile Flow Evidence

- Status: Implemented / Current
- Document Role: Current focused Main persistence integration evidence
- Authority Level: Production launch, terminal settlement, and return entry
- Applies To: Main, RunRuntimeHost, RunEndOverlay, and ProfileRuntimeService
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16-production-profile-boot-evidence.md`, `docs/current/2026-10-05-p16-encounter-timer-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Actual launch and death settlement verified; full Hub, victory, and resume pending

Main activates actual-content Profile authority, starts a durable LAUNCH run, and binds the actual native Player to narrative observation. Actual Player death persists canonical terminal statistics and currency through physical SaveService promotion. Failed promotion preserves the active receipt and terminal for retry. Successful settlement retires the receipt before allowing return, and the next launch uses the next monotonic identity without reloading Main. HUD presentation is hidden outside an active run.

Fabricated run-ended notices cannot award currency or take terminal focus. Repeated actual terminal notices cannot repeat settlement or consume a save sequence. Victory remains blocked until the final heart fragment and this launch's ending choice are durable; the native final-heart/ending/credits presentation is still pending.

RED: `build/test-logs/p16-main-profile-red` exposes the missing durable launch receipt. GREEN: `build/test-logs/p16-main-profile-save-retry-final`, one native integration test using an authored route and actual physics time, Player death, before-primary-promotion fault injection, retry, repeated notices, and relaunch. Durable Host regression: `build/test-logs/p16-meta-host-main-regression`. Both final logs have no script errors or leaks. Earlier fixture errors and a passing assertion run with a timer leak remain failures.

The returned entry currently uses the compatibility StartMenu. The native Hub scene and business panel integration are next. An existing active receipt that needs native restoration is refused rather than presented as a resumed run. This evidence does not certify full mid-run resume, victory completion, or the export path.
