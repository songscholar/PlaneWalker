# Native Runtime Observation Queries

- Status: Active
- Document Role: Current gameplay performance implementation plan
- Authority Level: Below the gameplay completion plan
- Applies To: Native Host full Run exports and event-player synchronization
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/plans/2026-10-06-gameplay-ui-product-completion.md`
- Last Verified: 2026-10-06
- Contract References: `tests/integration/application/native_runtime_observation_query_test.gd`

The retained diagnostic measured 749 Host full snapshots in 180 actual Player
frames. Each export also obtains complete Run snapshots for event health and
modifier synchronization. RunState already detaches all mutable export fields;
Orchestrator and Host then deep-copy those detached exports again.

## Executable Gate

- [x] Preserve a failing actual Main test for one full export per stable read.
- [x] Add detached health and event exports plus the existing lifetime projection
  at the Orchestrator authority boundary. Materialize full event state only when
  physical HP changes; preserve candidate validation and atomic health commit.
- [x] Remove redundant copies only where the returned full snapshot is already
  detached. Preserve typed fields, complete data and caller mutation isolation.
- [x] Pass focused native health, event lifetime, Host, Save and Replay checks.
- [x] Compare an immutable before/after native Main probe with identical content,
  input, frames and exact physical tape hashes. Report every measured pair.

The change adds no cached gameplay verdict, state writer, clock or save schema.
Headless timing evidence remains separate from rendered 60 Hz certification.
