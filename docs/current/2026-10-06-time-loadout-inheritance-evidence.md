# Time Loadout Inherited Processing Evidence

- Status: Focused Verified / Integrated clean validation pending
- Document Role: Current focused fixture repair evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Player loadout duration, inherited lifecycle suspension and actual fixed-frame resumption
- Owner: Plane Walker integration team
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-main-player-lifecycle-evidence.md`

## Retained Failure

The immutable `5a7fb3e` validator correctly rejects
`tests/time/time_loadout_runtime_test.tscn` because its old assertion requires
the Player scene to set `PROCESS_MODE_PAUSABLE`. The verified Main lifecycle
repair intentionally removes that explicit mode: Player must inherit the
CombatRoom lifecycle so hidden Hub physics cannot advance authoritative state.

Current-source RED independently reproduces exactly the same strict error:
`Player scene defaults to pausable processing: expected 1, got 0`.
The retained stdout and paired engine logs are under
`build/test-evidence/time-loadout-inheritance-red/`; top-level stdout is
`build/time-loadout-inheritance-red.stdout.log`, SHA-256
`cc8fa41e78f590ebd0bfe155192fc22656283b361f60a91e01c50c702493b100`.
The frozen checkout and its running validation receive no overlay or restart.

## Executable Fixture Correction

Only `_test_disabled_player_freezes_inherited_time_clock()` changes. Its actual
Player is reparented under a PAUSABLE gameplay parent while the test harness
remains ALWAYS. Both Player and TimeManager must inherit and be effectively
processable while their parent is active.

The fixture enables ordinary Player physics, commits an actual Accelerate
effect, and then exercises three suspension causes independently: disabled
gameplay parent, disabled Player during selection, and global pause. At each
boundary both Player and manager must report `can_process() == false`; after
a real 0.12-second wait the authoritative action frame and effect duration must
remain unchanged, and the active effect must remain present. No manual frame
advancement or counter reset occurs in any suspended interval.

Restoration uses the captured inherited Player mode. After global resume,
actual physics/process yields must advance the authoritative action frame and
reduce the time duration automatically. Physics is then disabled before the
existing manual expiration assertion. Player and parent are both released.
Production scene behavior, time dispatch, fixed-frame clocks and strict log
validation are unchanged.

The corrected test source SHA-256 is
`d64c296142f4c9aa129d9b41f77968b4ac5921fffb80de06e89fb8b4e0073683`.

## Focused Verification

The repaired scene passes 1/1 under
`build/test-evidence/time-loadout-inheritance-green-attempt2/`. Its top-level
stdout SHA-256 is
`dfc316e6e22dee0823ffd5389ed3190836c1efe4f913483ecabe90d7c0b52a8c`.
The first GREEN invocation supplied a regular expression to the runner's literal
substring filter; it matched no scenes and exited 2. That invocation remains at
`build/time-loadout-inheritance-green.stdout.log` and supplies no test result.

Three adjacent scenes pass under
`build/test-evidence/time-loadout-inheritance-neighbors/`:

- `main_player_lifecycle/`: actual Main Hub dormancy, automatic encounter frames, selection and production pause/resume
- `player_fixed_frame_authority/`: Player's authoritative fixed-frame integration
- `time_manager_fixed_frame/`: TimeManager's authoritative effect duration

Their combined top-level stdout is
`build/time-loadout-inheritance-neighbors.stdout.log`, SHA-256
`d7771d73c5c46b3fc5e437c5b32d4cb9b2811aebd93c58b6e1389fc35d49cf10`.
All four successful scenes pass strict stdout and independent Godot-log checks
without unexpected runtime errors or leaks. `git diff --check` passes.
Documentation governance reports zero violations after the Current index link.
All three pinned requirements files pass `pip-audit`; audit stdout is retained
at `build/time-loadout-inheritance-pip-audit.stdout.log`, SHA-256
`59ced18de553fede8719a1a59b3f66dbef1b853158bcbb27559651ee372febd5`.

## Retention Boundary

Focused GREEN does not replace the immutable validator's authentic failure.
These ordinary scene runs report line coverage as unavailable; they do not
measure runtime statement coverage, frame budgets, memory, rendered UI or human
playtests. A fresh committed combined source still requires complete clean
validation and instrumented coverage.
