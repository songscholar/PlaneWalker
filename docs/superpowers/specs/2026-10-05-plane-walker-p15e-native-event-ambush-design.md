# P15E Native Event Ambush Specification

- Status: Approved / Current
- Document Role: Current executable specification for production event encounters
- Authority Level: Below standing project authorization
- Applies To: Launch event templates, catalog, Facade and RoomRuntime
- Owner: Project runtime implementation lead
- Depends On: `AGENTS.md`, `2026-10-05-plane-walker-p15n-production-launch-encounters-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual Main event ambush and targeted regressions pass

The authored Sleeping Guardian encounter continuation must run through the
production native Launch driver in its actual event room. Its original profile
identity remains the event consequence authority; the concrete recipe identity
remains the encounter authority. Neither identity may silently replace the other.

Completion criteria:

1. All three authored event rooms declare a physical enemy-wave anchor at
   (416, 176), mirrored exactly in their template definitions.
2. Event recipe selection validates the actual event template and chooses only
   authored combat recipes whose offsets pass the existing room geometry checks.
   The accepted seed, profile and actual node identify the deterministic channel.
3. Actual Main seed 6 reaches the selected Sleeping Guardian event through Host
   routing and starts native actors using the actual room anchor.
4. Only a settled Runner with the exact concrete encounter ID resolves the
   original profile continuation. Forged, active and duplicate completions have
   no event consequence. Failure settlement retains the original continuation ID.
5. Accepted Player frames and authenticated native actor deaths complete every
   selected wave, allow event dismissal and reopen normal routing.
6. Catalog, RoomRuntime, event Facade, native encounter and checkpoint regressions
   pass with no script errors or unexpected leaks.

Prerequisite room clears and lethal Health fixtures are explicit integration
fixtures. They do not establish unaided event balance or five-floor gameplay.
Content descriptor and compatibility ledger updates remain owned by the root
content-governance lane; the four changed content files are handed over by hash.
