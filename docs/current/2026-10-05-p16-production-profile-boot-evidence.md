# Plane Walker Production Profile Boot Evidence

- Status: Implemented / Current
- Document Role: Current focused production persistence evidence
- Authority Level: GameState settings boot and actual-content Profile activation
- Applies To: GameState, SaveService content rebinding, ProfileRuntimeService, and compatibility callers
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16k-content-rebinding-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Actual-content boot and reviewed history verified; full native resume and final product certification pending

GameState startup loads global settings without touching Profile bytes. Explicit activation uses the actual validated ContentRegistry snapshot and current Meta catalog. An actual schema-v4 Profile can activate directly. The exact known historical synthetic Base fingerprint can migrate through authenticated schema migration and SaveService's exact-preimage rebinding transaction. Two reviewed actual Base snapshots can also rebind through the pinned compatibility ledger. Each candidate requires independent authenticated inspection before migration; a matched candidate's physical rebind failure is returned without trying another migration. An unknown fingerprint cannot authorize itself and is refused without changing live memory or primary bytes.

Fresh Profile state comes from the progression authority, including Wanderer and Bow/Sword ownership. The compatibility mirror is derived from the actual Profile snapshot. After activation, old blanket Profile saves and synthetic run-summary writes are refused so production rewards must use the service's durable commands and terminal settlement.

Meaningful missing-boundary RED: `build/test-logs/p16-production-profile-red`. Final GREEN: `build/test-logs/p16-profile-activated-registry`, one physical integration test covering fresh/current-v4/known-legacy/unknown-content, idempotent reactivation, and refusing legacy reset after activation. Compatibility regression GREEN: `build/test-logs/p16-game-state-final-regression`, one legacy GameState integration test. Final logs contain no script errors or leaks. An intermediate test fixture used StringName dictionary keys and incorrect indentation; those diagnostic failures are retained and are not described as passing.

Trusted-history RED: `build/test-logs/p16-production-profile-trusted-actual-red`. GREEN: `build/test-logs/p16-production-profile-trusted-actual-green`, one physical integration scene covering the two exact reviewed histories, current-v4, historical synthetic, fresh and unknown Profiles. All non-fresh fixtures preserve 37 shards, extension payload, zero launch sequence and idempotent physical activation. Final logs contain no script errors or leaks. Ledger provenance and all physical transaction faults are recorded separately in `docs/current/2026-10-05-p16-actual-content-compatibility-evidence.md`.

The ledger accepts only reviewed localization-only transitions with the same Meta catalog and save schema. General CONTENT_MISMATCH checks remain strict. Main entry and death settlement are verified separately in `docs/current/2026-10-05-p16-main-profile-flow-evidence.md`. This evidence does not certify full native resume, the complete game or the export path.
