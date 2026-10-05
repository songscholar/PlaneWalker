# Dungeon Probe Native Encounter Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Below dungeon probe encounter specification
- Applies To: Tool-only encounter adapter and deterministic domain evidence
- Owner: Project integration lead
- Depends On: `../specs/2026-10-05-dungeon-probe-native-encounter-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Affected-seed regression, authoritative core adapter tests and immutable thirty-seed report contract pass with clean logs

**Goal:** Restore canonical event continuation in the existing honest synthetic
dungeon probe.

**Architecture:** A tool-only Node translates RoomRuntime lifecycle calls to
LaunchEncounterRuntime. The existing probe applies explicit completion commands
and retains its production Player/Facade/content integration.

**Tech Stack:** Godot 4.6.1, LaunchEncounterRuntime, Python report contracts.

## Tasks

- [x] Add affected seed 20261006 to the existing actual Player five-floor
      regression; run `./tools/run_tests.sh --filter dungeon_seed_reward_regression`
      and retain its sleeping-guardian RED.
- [x] Add `tools/dungeon/domain_encounter_runner.gd` with exact core validation,
      sequential-frame advancement, safe synthetic identity mapping and runner
      signals. Add `tests/unit/dungeon/domain_encounter_runner_test.gd` / `.tscn`
      for warning/receipt, failure and cancellation contracts.
- [x] Replace the event probe's legacy runner with the tool adapter. Advance
      explicit frames with a 4096-frame upper bound, recording failure on
      exhausted or rejected work; retain all canonical definition fields.
- [x] Include all tool adapter sources in `tools/run_dungeon_simulation.py`
      runtime digests; verify the digest contract rejects tool changes.
- [ ] Require clean focused GREEN, then retain code/tests/evidence with precise
      file staging. Re-run the full Python report contract on that fixed commit.

Whole native combat and real human playtests remain separately certified lanes.
