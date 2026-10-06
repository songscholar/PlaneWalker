# Native CPU Profile Diagnostic Evidence

- Status: Diagnostic only / production recorder optimization gate open
- Document Role: Inclusive CPU call timing used to choose the next optimization
- Authority Level: Below approved full-product completion contract
- Applies To: Frozen source clone at `9fd36ef`, native Player fixed-frame path
- Owner: Plane Walker performance lane
- Last Verified: 2026-10-06

This document deliberately retains an instrumented diagnostic, not a normal
performance certificate. It must not be compared directly with the clean
Metal/OpenGL measurements or used to claim a frame-rate improvement.

## Frozen Diagnostic

The diagnostic clone is
`build/retained-checkout/native-cpu-diagnostic-9fd36ef-20261006/`, detached at
`9fd36ef184c79b29b0dc1eac5dd09fe0a6d8f3c3`. The preparation script installs
explicit inclusive timers around the Player fixed-frame boundary, transaction
snapshots, synchronous native replay observation, and their component snapshot
calls. The launcher marks the source manifest `instrumented: true`. The
instrumented runtime aggregate is
`c626118e4364bf3d946185ab745c0ea325bd1dba355ee89cc04c9aa6086f58a7`.

The timer smoke uses a real Main launch, actual Player inputs, fixed 60 Hz,
and 60 accepted frames. It is headless and unrendered, reaches the ordinary
launch encounter rather than the later Void phase-two workload, and passes
the native report plus paired stdout/engine log validation. The timer stack
returns empty at the end. Report SHA-256 is
`469627db0422d7d8bb244fb9150e9d69e44d1be25f89a03ef5109adf12c31c3a`; its
source manifest SHA-256 is
`9e5ead4bc67765fb72b44d948682de41ee1231e088d027c455dfa2f46650752b`.

The source-only preparation contract has three passing Python tests. It
requires exact method names and return types, preserves default arguments,
keeps an uninstrumented fast path, refuses duplicate or wrong-typed methods,
and refuses repeated instrumentation. The instrumentation is intentionally
kept out of the production checkout.

## Inclusive Top-Level Costs

| Instrumented call path | Calls | Mean per accepted frame (us) | Total (us) | Call p95 (us) |
| --- | ---: | ---: | ---: | ---: |
| `PlayerController.advance_action_frame` | 60 | 6,401.85 | 384,111 | 10,042 |
| `NativeRunReplayRecorder._observe` | 60 | 2,054.17 | 123,250 | 2,601 |
| `PlayerController._commit_fixed_frame_event_buffers` | 60 | 994.65 | 59,679 | 1,970 |
| `PlayerController._fixed_frame_transaction_snapshot` | 60 | 171.93 | 10,316 | 199 |
| `PlayerController._fixed_frame_preflight` | 60 | 146.02 | 8,761 | 180 |
| `PlayerController._refresh_weapon_replay_fact_baseline` | 60 | 106.45 | 6,387 | 146 |

The inclusive timer shows replay observation as a material synchronous cost in
this smoke. `_observe` includes a full player replay snapshot and validation;
their inclusive rows are 353.05 us/frame and 378.58 us/frame respectively.
`_fixed_frame_transaction_snapshot` is about 171.93 us/frame. The rewind
history snapshot inside it is only 7.42 us/frame (445 us total across 60
frames), so the bounded rewind history is not the dominant measured cost.

Other component observations are smaller: the character snapshot is 28.87
us/frame inside the fixed transaction snapshot, the weapon snapshot is 20.60
us/frame, health runtime state is 8.90 us/frame, and world replay state is
3.62 us/frame. These are inclusive measurements and overlap their parent
rows; they must not be summed as independent frame times.

## Next Measurement and Limits

The interrupted attempt to run an instrumented 120-frame phase-two sample was
stopped before sampling when the quiet window changed. It is not evidence and
has no report status. The next controlled step is two same-source production
clone runs with identical phase-two inputs and recorder enabled/disabled,
followed by replay and refusal-contract verification. That comparison is
required before changing recording cadence, validation, or snapshot ownership.

This smoke does not certify 60 FPS, release performance, peak enemy density,
Mac/Windows/Linux compatibility, or a recorder-off behavior change. No
production recorder semantics were modified by this diagnostic.
