# Native Time Sovereign Responses Plan

- Status: Completed / Historical
- Document Role: Historical implementation plan
- Authority Level: Execution details below approved P15 section 7.3
- Applies To: Four authentic time responses, watch counterplay and native persistence
- Owner: Plane Walker native Boss implementation lead
- Last Verified: 2026-10-05
- Implementation Status: Four authentic native responses, watch counterplay, schema9 migration and production Profile recovery verified. Combined full-game certification remains pending.
- Completion Evidence: `../../current/2026-10-05-native-time-response-evidence.md`
- Depends On: `../../../AGENTS.md`, `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Exit Gate: Real paid Player casts trigger each response exactly once, preserve the original ability, defer current primary, grant counterplay, and pass rollback, physical cold recovery and six-pair/two-phase gates.

## Design

TimeManager publishes a narrow native receipt only after its actual transaction
commits. The delivery is authenticated synchronously against the producer;
public UI events and copied receipts cannot queue a response. This receipt
needs no additional Player replay schema. Boss response state belongs to the
Boss domain and is included in its frame and cold snapshots.

A bounded pending queue and monotonic producer watermark admit each paid
generation once. Responses share the authored900/600-frame cooldown and wait
until the primary completes recovery. Stop also waits72frames. Every response
uses at least45 warning frames. Rewind freezes the actual restored endpoint;
native landing is constrained by existing collision and safe-room rules.

Actual accepted watch damage cancels Stop after40 cumulative loss. Six distinct
accelerated body identities shatter the finite120-frame slow field. Authentic
Rewind echo damage grants30-frame watch exposure. Rift's delayed pulse extends
recovery45frames without deleting the paid field. Accepted owner state drives
zone retirement and all positive windows survive cold restoration.

## Execution

- [x] Establish failing domain and actual Player admission criteria.
- [x] Add authenticated producer delivery and bounded response domain.
- [x] Integrate deferred actions, native landing, watch counterplay and finite zones.
- [x] Verify two phases, all six time pairs, five weapons, rollback and physical cold restore.
- [x] Inspect native warning/field raster, record evidence and retain a focused commit.
