# Native Fixture Isolation Evidence

- Status: Focused Verified
- Document Role: Current save/resume fixture startup and environment evidence
- Authority Level: Below approved full-product completion contract
- Applies To: `native_launch_route_fixture.gd`, Main native resume and checkpoint scenes
- Owner: Gameplay performance lane
- Depends On: `docs/superpowers/plans/2026-10-06-gameplay-ui-product-completion.md`, `AGENTS.md`
- Last Verified: 2026-10-06

## Failure Cause

Running the Main save/resume scenes directly without the test runner's isolated
`PLANEWALKER_USER_DATA_DIR` reused a local profile. When that profile was not
compatible with the current Base content, Main correctly left `_profile_error`
set and did not create optional `TutorialFlow` or `HubFlowCoordinator` nodes.
The fixture then called `set_process` on a missing TutorialFlow node, obscuring
the actual profile initialization failure.

## Repair

The shared route freeze helper now treats Tutorial and Narrative flows as
optional domain presentation nodes. The Main resume fixture also fails at its
boundary with a direct Profile/flow readiness assertion and includes the
profile error in the message. This preserves the production fail-closed profile
behavior while making an unisolated test invocation actionable.

## Verification

With fresh absolute user and data directories, Main native resume passes all
assertions and strict stdout/Godot log validation at
`build/fixture-fix-main-resume/`. The full native combat checkpoint scene also
passed all 25 cases under an isolated directory at
`build/fixture-isolated-checkpoint-full/` before this focused guard was added.

These changes do not alter gameplay state, content compatibility or save
semantics; they make fixture prerequisites explicit and avoid a misleading null
node error.
