# Plane Walker Content Rebinding Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Explicit compatible-content Save migration
- Applies To: SaveService content rebinding API
- Owner: Runtime integration agent
- Last Verified: 2026-10-05
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`
- Evidence Status: Verified Locally
- Certification Status: Focused storage boundary verified; GameState activation pending

## Delivered Boundary

`rebind_profile_content(profile_id, save_domain, prior_snapshot, target_snapshot, expected_primary)` requires a SaveService already configured to the exact prior content snapshot and a complete authenticated primary envelope obtained through inspection. It validates the target snapshot, reads the current source primary, and refuses an altered or stale preimage. Before final promotion it reads the primary again so another authentic Save instance cannot have its write overwritten during a callback.

The candidate retains the complete validated payload and profile creation time, increments one physical save sequence, and passes the existing strict Meta and Save validators. Pending and final-primary validation use the explicit target snapshot internally; backup rotation uses the original source binding. Ordinary loading and inspection retain their existing strict configured-content policy. Service configuration cannot change while a write is active.

The service publishes its target binding only after an actual candidate commit. A post-promotion failure is reconciled only by an independently read primary exactly matching the complete target candidate. Compatible pending or backup files do not prove commit. A missing primary with no recovery files and an empty expected preimage updates the binding without creating a profile or claiming a file commit. Remaining recovery files refuse this new-profile path.

## Verification

Meaningful missing-API RED: `build/test-logs/p16-content-rebinding/api-red` (`b6nUXN`). Fixture typing, shared-case-directory mistakes, and JSON numeric normalization debugging are not counted as feature RED.

Final GREEN: `build/test-logs/p16-content-rebinding/final` (`qsZb7Q`). The physical scene derives its target from the actual validated Base Registry and starts from the documented historical synthetic GameState descriptor. It checks every existing Save fault point, failed promotion and exact-preimage retry, committed-primary reconciliation, malformed target and altered preimage refusal, ordinary mismatch protection, another writer's genuine primary, profile isolation, global settings preservation, authenticated no-op, physical restart, and missing-primary/recovery-file behavior.

Existing regressions GREEN: `save-regression` (`1KUgYJ`), `envelope-regression` (`kvJ1Qs`), and `gamestate-regression` (`fsgmq9`) under the same directory. Logs contain no script errors or object leaks. Godot line coverage remains unsupported and no coverage percentage is claimed. Independent read-only review by the onboarding integration agent found no blocking issue.

## Remaining Integration

The caller selects and records an authorized compatible content transition. This storage API does not infer gameplay compatibility from a new fingerprint. Actual Meta catalog changes still require a separate catalog/state migration and remain subject to current strict validation. Root GameState/Main integration is a separate milestone.

Old-content backups remain intact for explicit rollback under their original configured content. They are not silently accepted as target-content recovery. A physical cross-process writer could still race between the final preimage read and the filesystem rename; this API verifies callback-time conflicts and does not claim an operating-system compare-and-swap lock.

## Retention Decision

Retain this focused, reversible local commit. It adds one explicit migration API and two optional internal validation parameters while preserving ordinary content-mismatch behavior. No remote publication was performed.
