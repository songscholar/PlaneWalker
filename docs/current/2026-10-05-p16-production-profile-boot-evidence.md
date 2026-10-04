# Plane Walker Production Profile Boot Evidence

- Status: Implemented / Current
- Document Role: Current focused production persistence evidence
- Authority Level: GameState settings boot and actual-content Profile activation
- Applies To: GameState, SaveService content rebinding, ProfileRuntimeService, and compatibility callers
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16k-content-rebinding-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Actual-content boot verified; Main entry, full native resume, and product flow pending

GameState startup loads global settings without touching Profile bytes. Explicit activation uses the actual validated ContentRegistry snapshot and current Meta catalog. An actual schema-v4 Profile can activate directly. The exact known historical synthetic Base fingerprint can migrate through authenticated schema migration and SaveService's exact-preimage rebinding transaction. An unknown fingerprint cannot authorize itself and is refused without changing live memory or primary bytes.

Fresh Profile state comes from the progression authority, including Wanderer and Bow/Sword ownership. The compatibility mirror is derived from the actual Profile snapshot. After activation, old blanket Profile saves and synthetic run-summary writes are refused so production rewards must use the service's durable commands and terminal settlement.

Meaningful missing-boundary RED: `build/test-logs/p16-production-profile-red`. Final GREEN: `build/test-logs/p16-profile-activated-registry`, one physical integration test covering fresh/current-v4/known-legacy/unknown-content, idempotent reactivation, and refusing legacy reset after activation. Compatibility regression GREEN: `build/test-logs/p16-game-state-final-regression`, one legacy GameState integration test. Final logs contain no script errors or leaks. An intermediate test fixture used StringName dictionary keys and incorrect indentation; those diagnostic failures are retained and are not described as passing.

Known prior actual fingerprints still require an explicit trusted content-upgrade policy. The service does not relax general CONTENT_MISMATCH checks. Main entry and terminal settlement integration are the next boundary. This evidence does not certify the full game or export path.
