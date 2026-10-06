# Replay Safety Validator Convergence Evidence

- Status: Focused Verified / Native frame performance pending
- Document Role: Current focused behavioral and call-count evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Full Player replay snapshot validator safety boundaries
- Owner: Plane Walker verification lane
- Depends On: `2026-10-06-replay-safety-leaf-plan.md`
- Last Verified: 2026-10-06

## Retained Behavior

`ReplayRecorder.validate_full_player_snapshot()` still performs one complete
root `replay_value_is_safe()` walk before reading any nested Player state.
Identity, reward-effect and live-talent validators remain independent public
boundaries: direct callers still receive the same normalized value or Boolean
verdict and each direct call performs its own safety walk. The full snapshot
path invokes private after-safety helpers only after the root walk succeeds.

Live-talent digest comparisons use the canonical digest implementation after
the root walk. Public `value_digest()` still performs its own safety check.
There is no trusted argument, caller certificate, cache, schema, serialized
format or gameplay state change. Unsafe Objects, freed Objects, non-finite
values, unsafe Packed floats, safe typed bytes, forged clocks, ownership and
digest tampering remain covered by the same public rejection behavior.

The generic safety function retains its existing recursion behavior. Cyclic
containers are not newly admitted or certified by this focused change and are
outside the retained fixture contract.

## Executable Evidence

The new scene `tests/replay/full_player_safety_walk_test.tscn` runs against an
actual Launch Player snapshot. It compares instrumented and production
validator verdicts, exercises unsafe descendants in all three nested states,
checks freed Object and non-finite refusals, verifies safe packed bytes and
typed caller bytes, and retains exact clock, ownership and digest rejection
codes. Final production GREEN is retained under
`build/replay-safety-walk-20261006/green/`; its stdout and engine log both pass
`tools/runtime_log_validation.py --test-suite-scopes`.

The build-only probe `tools/p15/replay_safety_walk_probe.py` instruments a copy
of the actual Recorder with `gdtoolkit` 4.5.0. The original source is retained
under `build/retained-checkout/current-gate-ea35dc7-20261006/`; its RED run is
under `build/replay-safety-walk-20261006/red-original-final/`:

| Entry | Original safety-walk roots | Candidate safety-walk roots |
| --- | ---: | ---: |
| Full snapshot | 6 | 1 |
| Identity validator | 1 | 1 |
| Reward validator | 1 | 1 |
| Live-talent validator | 3 | 1 |

The original RED has only the two expected call-count assertion failures;
all behavioral assertions pass. Candidate GREEN is 1/1 with strict paired
logs. The focused Python contract for the probe is 5/5 and verifies that
instrumentation preserves recursive implementation, refuses missing or already
instrumented sources, and never overwrites retained evidence or follows
symlinked output paths.

Neighboring Godot regressions are also GREEN with strict paired logs:

- `native_recording_snapshot_test.tscn` in `build/replay-safety-walk-20261006/native-recording/`
- `replay_value_safety_test.tscn` in `build/replay-safety-walk-20261006/value-safety/`
- `full_player_replay_test.tscn` in `build/replay-safety-walk-20261006/full-player/`

## Limits

The call-count result is a structural diagnostic on a build-only instrumented
copy, not a portable FPS or wall-time claim. The integrated uninstrumented
native frame and the complete native matrix remain separate gates. UI polish,
rendered performance and human Shenzhen playtesting remain pending.
