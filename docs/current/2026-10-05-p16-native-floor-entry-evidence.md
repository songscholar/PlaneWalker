# Plane Walker Native Meta Floor Entry Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Frozen run progression and native floor entry transaction
- Applies To: RunState, RunOrchestrator, RunRuntimeFacade, MetaRunProjection, and SaveEnvelope
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16h-meta-player-replay-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused native boundary verified; production Main activation and combined certification pending

## Delivered Boundary

Launch and Expansion RunState bind the authenticated permanent projection before initializing floor/event participants. Event transactions preserve this projection and its canonical prefix of consumed floor entrance markers. Save validation authenticates both after physical JSON normalization. A detached native RunState handle allows the Profile service to validate actual participants.

W-04 heals the actual Player by two percent of permanent maximum HP at an entry node, capped at maximum and without reviving a dead Player. The facade installs physical health silently, commits canonical health and its entrance marker, refreshes event participants, and only then publishes healing. A duplicate notification succeeds without changing health, markers, or revision. Physical installation and event refresh failures compensate all participants; a later retry heals exactly once.

Native restore now refuses extra build fields before mutation. If a final equality check fails, it restores clock fraction, resources, statistics, consumed offers, floor state, and build state. Target event participant validation checks the target health rather than the previous live health.

## Verification

Meaningful RED: `build/test-logs/p16-meta-restore-atomicity-red`, where an unknown build field was refused but altered clock/statistics remained installed.

Focused GREEN: `build/test-logs/p16-meta-floor-compensation-final`, one native integration scene covering actual permanent Player health, duplicate entries, JSON restore, corrupt markers/digest/health, direct native restore refusal, physical install failure, event refresh failure, silent compensation, and successful retry.

Regression GREEN: `build/test-logs/p16-meta-entry-final-save-regression` (four scenes) and `build/test-logs/p16-meta-entry-final-floor-regression` (three scenes). Logs contain no script errors or object leaks. An intermediate typed-array error was fixed before the final GREEN and is not treated as feature evidence.

## Remaining Integration

Production Host/Main and Hub must still install durable launch receipts and persist complete startup before gameplay publication. This focused evidence does not certify the full product, line coverage, formal exports, or human playtests.
