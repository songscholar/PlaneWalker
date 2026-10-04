# Plane Walker Successful Player Frame Observation Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Native successful Player frame observation interface
- Applies To: PlayerController and TutorialNativeAdapter
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16i-native-tutorial-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused native frame interface verified; production tutorial UI activation pending

## Delivered Boundary

Player emits `authoritative_frame_committed` only after all fixed-frame participants, observations, and Replay baselines have committed. A detached normalized-intent getter accepts only the most recent successful frame in the same run and owner generation. This allows tutorial observation to distinguish real movement input from actual knockback. Successful full Replay restore invalidates the observation cache even for an identical checkpoint and emits no action notification. The observation cache is excluded from gameplay snapshots.

## Verification

Native adapter GREEN: `build/test-logs/p16-tutorial-native` is superseded by the precise runs recorded in the linked native tutorial evidence. That scene verifies actual movement, dash, primary, skill, and time input; physical knockback with no movement intent; detached/stale getter reads; generation and callback drift; and World commit failure with full physical compensation and successful same-frame retry.

Replay regression: `build/test-logs/p16-meta-observer-replay` passed ten of eleven scenes; the Gauntlets external-fact scene exceeded the deliberately short 30-second timeout without a script error. Targeted rerun `build/test-logs/p16-meta-observer-gauntlets-retry` passed that scene with a 90-second limit. Both runs reported no leaks. These combined results verify the eleven affected scenes; the initial short-timeout run is recorded as failed, not retrospectively relabeled.

## Remaining Integration

Profile persistence and native tutorial UI must consume the observer through the authenticated adapter. This interface alone does not certify onboarding, full-product readiness, line coverage, or clean export.
