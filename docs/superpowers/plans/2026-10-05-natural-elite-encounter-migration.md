# Natural Elite Encounter Migration

- Status: In Progress
- Document Role: Plan
- Authority Level: Implementation plan below approved P15 specification
- Applies To: Additive Wraith and Spore elite route reachability
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05

## Completion Criteria

1. The approved historical `launch_encounters.json` and all forty recipes remain byte-identical; revision 1 retains the same seeds, templates and encounter definitions.
2. A closed, pack-registered additive revision 2 catalog supplies genuine elite Wraith and elite Spore recipes. Actors, affixes, budgets, warnings, anchors and references validate through runtime and content schemas.
3. New Launch runs persist revision 2 in their config. Historical configs with no revision retain revision 1 through restore; explicit unsupported revisions refuse.
4. Actual Host route selection reaches both additive recipes; the real native Driver constructs their elite principals and preserves terminal child encounter work.
5. Physical SaveService reconstruction preserves the chosen revision, concrete encounter and exact continuation, including a historical revision 1 checkpoint.

## Execution

- RED: catalog/config revision contract and reachability test before implementation.
- Implement a separate additive content category, closed parser/schema and pack registration. Keep historical profiles unchanged.
- Add explicit revision-aware selection to the catalog and bind persisted Run configuration in the Facade.
- Verify natural native routes, terminal children, cold recovery, historical selection and related content/route/replay suites.
- Retain code, content, tests and evidence in a precise local commit. External publication remains outside this milestone.
