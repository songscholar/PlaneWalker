# Dungeon Probe Native Encounter Adapter

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Focused synthetic probe integration repair
- Applies To: Authored event encounter commands in the deterministic dungeon probe
- Owner: Project integration lead
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`, `../../../AGENTS.md`
- Last Verified: 2026-10-05

## Design

The thirty-seed domain probe currently instantiates the legacy EncounterRunner
without a native scene binding. Canonical event definitions now contain Launch
recipe and floor identities; production correctly refuses that incomplete
binding. Seven canonical seeds consequently fail the sleeping-guardian event.

Use a tool-only Node adapter around the existing LaunchEncounterRuntime. The
core remains authoritative for exact definition validation, sequential frames,
warning/spawn timing, spawn registration, defeat receipts and completion. The
adapter exposes the existing RoomRuntime runner protocol, maps test entities to
stable source IDs, and advances explicit bounded synthetic frames. Registered
entities receive exactly one explicit domain defeat command. No recipe marker,
production binding requirement, warning frame or native validation is removed.

Using the real native scene driver would turn this domain/economy probe into a
different full-combat workload and require real gameplay inputs. Reverting to
legacy recipes would bypass the contracts that revealed the stale fixture. The
tool-only adapter therefore matches the report's existing methodology and keeps
production EncounterRunner unchanged.

Adapter snapshots include the RoomRuntime compatibility fields and a defensive
copy of the core state. Invalid or repeated facts refuse without changing the
core. Failed spawn admission publishes encounter failure; cancellation clears
test identity mappings. Sources are content-derived stable IDs, independent of
process-specific instance identifiers. Advancement does not happen implicitly
through timers or rendering frames.

## Completion Criteria

First reproduce a canonical sleeping-guardian failure using the actual Player,
Facade and existing probe runner. Then verify canonical warning timing,
registration, duplicate/forged defeat rejection, completion, spawn failure and
cancellation through the adapter. Re-run the affected seeds and the complete
thirty-seed/five-floor report contract from immutable sources.

Include the adapter in the report's runtime-source digests. Keep report metadata
`synthetic: true`, `human_playtests: 0`, and
`combat: domain_completion_commands`. Passing this probe is domain integration
evidence and does not establish native combat or human gameplay completion.
