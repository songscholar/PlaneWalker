# Void Checkpoint Projection Evidence

- Status: Focused Verified / Total-frame performance pending
- Document Role: Current Void event-history ownership and query-cost evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Void auxiliary warm historical replay checkpoints
- Owner: Plane Walker performance lane
- Depends On: `2026-10-06-actor-commit-validation-evidence.md`
- Last Verified: 2026-10-06

## Retained Behavior

The exact production `VoidAuxiliaryRuntime` can retain one decoded immutable
historical checkpoint on the main thread. This state is decoded from the
already authenticated typed replay bytes, then every Dictionary and Array in
it becomes read-only. A warm query copies only the top-level Dictionary.
Expiry replaces its `burns` and `statuses` arrays and its frame value; it does
not mutate historical rows or events.

The context and event keys remain complete exact typed bytes, with the same
accepted-frame rule, event replay, precision compatibility, positive validation
cache, and context invalidation. Integer-to-equal-float authority changes still
refuse. Decoded state is retained only after the original complete validator
accepts a safe, bounded checkpoint. Its serialized replay still has the
original 1 MiB limit, and the cache still contains one checkpoint. This adds
one native decoded copy of a bounded replay; exact native allocation impact
has not yet been measured and is not asserted to equal the serialized size.

Worker threads and custom runtime subclasses continue to decode independent
mutable state from the original replay bytes. Public snapshots remain detached
and mutable. Public restore deep-copies its candidate, can advance its own
clock, and can append new events independently of retained history. Save,
replay, publication, and checksum formats are unchanged.

## Executable Evidence

The final focused scene is
`tests/unit/enemies/void_checkpoint_projection_test.tscn`. It uses the exact
production runtime, actual authored casts and Health receipts, frame expiry,
fresh replay comparisons, typed forgery, public restoration and nested snapshot
edits, explicit custom-subclass ownership, and three read-only worker threads.
Workers explicitly require a private mutable history and test authentic and
forged later frames.

Final original RED is retained in
`build/performance-void-projection/red-original-public-custom-final/`. Both
logs contain exactly three expected sharing/immutability assertions and no
script failure, leak, or behavioral failure. The original source is frozen
under `build/performance-native-validation/same-load-before/`; its runtime
SHA-256 is
`86a0536da93802d3f761590f07e18a83969ea5b877cdfbb8de016e011c22415f`.
Candidate runtime SHA-256 is
`1f9f4c65891c05447e14c4cf326843df19c9518f9457d4b069ae105688be669d`.
The identical final test SHA-256 is
`573b26a522be37f7c5085c1d0a7e74ba5b780e3366ae68a0437afe66ac56172c`;
its scene SHA-256 is
`943a9fb1981cbd563952dae56bb13996607478ddfd6c13d66b8a70de8ca13432`.

Candidate GREEN is 1/1 in `green-public-custom-final/`. All eight neighboring
scenes in `neighbors/` pass strict paired stdout and Godot engine log validation:

- `void_event_checkpoint`: original event reconstruction, custom counted
  validator, staged boundary, context changes, precision, and concurrency.
- `void_auxiliary_validation_cache`: exact typed cache refusals.
- `void_auxiliary_runtime`: actual finite auxiliary content and restoration.
- `boss_snapshot_validation_cache`: complete Boss/context invalidation.
- `actor_commit_validation_pass`: all five physical Boss commit/rollback paths.
- `void_burn_snapshot_query`: actual Actor read-only burn preparation.
- `native_combat_checkpoint`: real native save and historical restoration.
- `boss_exposure_checkpoint`: actual Boss exposure replay restoration.

The earlier `red-final/` fixture parse failure is separate from the behavioral
RED. Its source-class `get()` call was corrected to a loaded Script instance;
that failed run remains failed and is not included in the accepted evidence.

## Rejected Concurrent Sharing

The first candidate shared read-only history with worker threads. Its focused
run in `green/` exited 139 with no PASS. The diagnostic run in
`crash-diagnostic/` reached the three-worker section, emitted a thread-affinity
error, and aborted with exit 134. The native backtrace includes
`Variant::reference`, `Dictionary::operator[]`, and `JSON::_stringify` from
`can_restore_snapshot()` on Godot 4.6.1. These runs are explicitly FAILED.
The attempted LLDB launch was denied by the host's debugger attachment policy;
diagnosis used the retained engine crash stack and stage output instead.

The final candidate restricts shared immutable projection to the exact
production main-thread implementation. Workers retain the original independent
decode, and subclasses retain mutable private replay results. The final test
exercises this boundary explicitly. This is an engine-driven ownership
restriction, not a relaxation of the validation or concurrency gate.

## Local Query Measurements

The build-only producer
`build/performance-native-validation/checkpoint_projection_probe.gd` has
SHA-256
`3dc8f0fbe3c9d28e88c8b8984a3d59cc2f694c8404c7dfcf85d2d7f483ee256e`.
It constructs 40 actual authored scepter casts and 40 actual Health receipts,
retaining 80 events. The complete replay is 69,952 serialized bytes; the event
array alone is 35,688 bytes. It performs 500 repetitions and checks every typed
output after the timed interval. This is an authored synthetic microbenchmark,
not the actual Main phase-two workload or a render test.

Both original and candidate use the identical producer. Each prints the actual
executed runtime SHA-256 above. Their paired logs in
`build/performance-void-projection/production-query-before.*.log` and
`production-query-after.*.log` are strict clean and have PASS.

| Actual production warm private checkpoint query | Mean us |
| --- | ---: |
| Original complete decode | 251.784 |
| Candidate main-thread immutable projection | 6.610 |

The earlier proposed projection omitted events and re-encoded caller history
to retain the exact typed check. That experiment was slower: original decode
225.408 us versus projection plus event recheck 242.154 us. It was rejected.
The retained logs are `checkpoint-projection.stdout.log` and
`checkpoint-projection.godot.log` under `build/performance-native-validation/`.
The subsequent manual frozen projection experiment measured 228.206 us for
complete decode and 11.526 us for shallow projection plus expiry filtering,
with clean paired logs in `checkpoint-frozen.*.log` in the same directory.

These measurements prove less work at the warm main-thread checkpoint query.
They exclude complete Boss validation, cold decode/freezing cost, rendering,
physical recording retention, and native decoded-cache memory impact. Active
scene suites and normal host processes remain possible timing noise. No total
Player/frame improvement, sustained 60 FPS, 45-minute soak, or human playtest
is certified by this microbenchmark. The earlier Actor phase-two timings refer
to their older recorded runtime source and cannot certify this changed source.
