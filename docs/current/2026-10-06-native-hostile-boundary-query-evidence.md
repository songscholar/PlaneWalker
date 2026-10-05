# Native Hostile Boundary Query Evidence

- Status: Implemented / Current
- Document Role: Current focused native boundary verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Hostile Bridge run identity, frame clock and terminal observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-boundary-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

Boss run identity queries read the current domain identity. Actor boundary
queries return a new three-field dictionary with current run identity, runtime
frame and terminal state. Other runtimes take one original full snapshot;
foreign actors without the native API keep the Bridge full-snapshot fallback.
Only Bridge scalar observation sites use the projection. Complete frame-start
transaction compensation, full rollback validation, physical geometry, health
publication and receipt authority remain in place.

The fallback preserves the raw frame Variant for the original summon-roster
comparison. Query output is detached, and no stored readiness certificate or
caller-controlled current-state cache is introduced. Independent read-only
review of all three production diffs found no actionable issue.

## Focused Contracts

`build/native-hostile-boundary-red` retains exactly one missing-native-API
assertion, without parse/script failures or leaks. Final GREEN in
`build/native-hostile-boundary-green` exercises the five authored Boss scenes
using counted real runtimes. Configuration, readiness and retirement take zero
complete Boss snapshots. Frame start retains exactly one full compensation
checkpoint. Actual frame advance refuses stale readiness, historical rollback
restores every complete typed Actor field, terminal mutation preserves
retirement, changed live run identity refuses foreign readiness, and authentic
state safely retries. Mutation of public query output cannot change domain
state. The ordinary enemy test retains exactly one original complete domain
snapshot when native query APIs are absent.

All 44 focused scenes pass:

| Contract | Retained Logs | Scenes |
| --- | --- | --- |
| Native boundary observation | `build/native-hostile-boundary-green` | 1 |
| Native hostile Bridge | `build/native-hostile-boundary-bridge` | 1 |
| Actor transaction and rollback | `build/native-hostile-boundary-transaction` | 1 |
| Actual Void Player frame | `build/native-hostile-boundary-void-frame` | 1 |
| Actual Boss actor | `build/native-hostile-boundary-boss-actor` | 1 |
| Enemy unit contracts | `build/native-hostile-boundary-enemies` | 39 |

Every paired stdout/Godot log passes the strict scoped runtime validator.
Bridge declares four exact expected synchronous refusal operations; Void
Player frame declares one. Each scope has the exact error message and count,
returns false, and completes in both logs. There are no unexpected runtime
errors, warnings, script/parse failures or object/RID leaks. Godot is
`4.6.1.stable.official.14d19694e`; line coverage is unsupported. Documentation
governance and diff whitespace checks pass.

## Remaining Measurement

The isolated uninstrumented complete-frame comparison against the previous
query slice is pending. This focused contract result makes no performance,
600-frame throughput, rendered FPS, 45-minute soak or human playtest claim.
No content, gameplay value, admission budget or recorder capacity changes.
