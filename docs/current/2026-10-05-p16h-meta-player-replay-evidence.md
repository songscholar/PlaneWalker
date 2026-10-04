# Plane Walker Native Permanent Player and Replay Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Native Player permanent Stats and Replay identity boundary
- Applies To: PlayerController, ReplayRecorder, and native permanent loadout tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16f-meta-stats-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused native integration verified; Main activation and combined certification pending

## Delivered Boundary

Player accepts an optional authenticated `meta_run_projection` only for Launch or Expansion. It derives permanent totals from the selected authored character base and the selected weapon forge level before installing native Stats, Health, and the run reward baseline. Repeated configuration cannot compound benefits. Invalid projections refuse before live state changes. Character permanent bonuses remain empty until an authoritative native source exists.

The existing Health damage policy applies frozen Void reduction once in combination with event damage multipliers. Physical damage receives no Void reduction. The detached projection getter does not expose mutable runtime state. Entrance healing is still a projected policy and is not yet executed at room or floor entry.

Full Player Replay schema 8 binds the permanent projection digest, including policies absent from final Stats. Schema 7 remains the contract for Launch without Meta; schema 2 remains the M1 contract. Meta checkpoints cannot downgrade to schema 7 or restore onto a Player with another frozen projection. The existing JSON codec and ReplayPlayer loader preserve this identity.

## Verification

Meaningful feature RED: `build/test-logs/p16-meta-player-contract-red`. Earlier parse and stale resource-hash fixture failures are not counted as feature RED.

Focused GREEN: `build/test-logs/p16-meta-player-final`, one native scene. It installs all 150 legal combinations of five characters, five weapons, and six time pairs; checks native Stats, Health and reward baselines; rejects malformed, contradictory, foreign, and wrong-milestone projections atomically; verifies actual Void and physical damage; and records, JSON-encodes, loads, seeks, and restores a Meta checkpoint on a fresh native Player.

Regression GREEN: `build/test-logs/p16-meta-replay-regression` (11 scenes) and `build/test-logs/p16-meta-player-input-regression` (9 scenes). The logs contain no script failures or object leaks. Independent read-only review found no blocking issue. Godot line coverage remains unsupported, and scene/loadout totals are not a coverage measurement.

## Remaining Integration

ProfileRuntimeService launch receipts and frozen projection must still be installed through the production Host and Main flow. Entrance healing needs an exactly-once native entry boundary. This evidence does not certify those paths, all-product completion, human playtests, formal exports, or packaged startup. The previous immutable certification timed out after 1200 seconds and remains failed.
