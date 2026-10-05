# Replay Safety Leaf Traversal Plan

- Status: Approved / Current
- Document Role: Current focused performance repair plan
- Authority Level: Below approved full-product completion contract
- Applies To: Generic Replay value traversal and unchanged public verdicts
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-native-recording-snapshot-evidence.md`, `2026-10-06-native-hostile-frame-query-evidence.md`
- Exit Gate: Variant contracts, strict neighboring regressions, exact physical input bytes and the measured local cost gate pass

## Root Cause and Criteria

The unified native Main profile records 7.886 ms per accepted frame in outer
Replay safety checks. The physical fifth-floor frame-2501 keyframe is 106,244
native snapshot bytes. Its original traversal takes 3.476 ms, while a
build-only equivalent traversal takes 0.922 ms. Recursive calls for every
primitive leaf dominate the cost; normalizing/copying the whole native
snapshot takes only 0.344 ms. No production source has changed at this point.

The focused local acceptance criterion is at most 2,000 microseconds mean
safety time for that authenticated native keyframe on the current machine,
using 20 actual calls. The original source is RED at 3,475.85 microseconds.
This is a bounded local cost gate, not a portable FPS claim or CI wall-time
threshold. The physical data, engine, strict logs, source identity and before
measurement remain retained in `build/native-cold-cost-20261006/`.

## Implementation and Verification

1. Add a native scene contract for every current Godot Variant category,
   including each value at the root and inside Arrays and Dictionaries.
   Preserve finite Float checks, permitted key types, freed Object refusal,
   packed Float rejection, typed empty containers, readonly mutation isolation,
   and all existing geometry/packed/depth behavior.
2. Record the failing original physical cost gate and run the behavioral
   contract before implementation. Behavior already passes; performance fails.
3. Handle the existing contiguous NIL-through-STRING_NAME scalar whitelist
   without recursive leaf calls. Every Float remains checked; nested containers
   and Packed cases still use the complete original checks. No cached verdict,
   caller certificate, schema, hash, type or gameplay value changes.
4. Re-run the behavioral contract, actual keyframe cost gate and relevant
   replay/recorder/stream/save scenes. Strictly scan both Godot logs. Preserve
   original typed input bytes and public rejection results.
5. Obtain independent review and retain the focused code/test/evidence commit.
   Re-measure the complete uninstrumented Main frame separately. The 750 native
   matrix, final line coverage, exports, UI and human playtests remain separate.

Root owns `scripts/replay/replay_recorder.gd` and this slice. Hostile Actor and
Bridge work remains with the performance lane; the native matrix lane keeps
its original frozen source untouched throughout this change.
