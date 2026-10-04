# P16Q Safe Native Checkpoint Evidence

- Status: Approved / Current
- Document Role: Current verification evidence for authenticated native cold restoration
- Authority Level: Executable evidence below the P16Q specification
- Applies To: Profile checkpoint capture, native Host reconstruction and rollback
- Owner: Project runtime implementation lead
- Depends On: `docs/superpowers/specs/2026-10-05-plane-walker-p16q-native-checkpoint-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Physical cold restore and targeted regression suites pass with scanned logs

## Verified Native Cases

`tests/integration/save/native_run_checkpoint_test.tscn` runs six isolated
physical Profiles against production Main, Host and Player scenes:

- Launch entry retains and restores the same Run, frozen projection and full Replay.
- Cleared elite room restores the actual bound scene and pending reward. The reward
  consumes once and floor routing continues.
- Terminal defeat restores without another launch, settlement or floor entrance.
- A native time rift reconstructs as a new Node, continues its saved deterministic
  World frame clock and expires through the normal payload lifecycle.
- Post-restoration callback drift reports publication pending and freezes both
  Player and RoomController without changing the durable checkpoint.
- A checkpointed launch can be explicitly abandoned, physically reopened and
  proved unavailable for resumption or duplicate settlement.

The same suite rejects unsupported live encounters, invalid inner digests,
re-signed mismatched scene seeds and stale in-memory Profiles whose physical
primary changed. A before-promotion save fault preserves the Profile. Scene
activation failure preserves exact Player Replay, original World object,
scene identity and generation, then succeeds after the adapter is cleared.

## Execution Evidence

Meaningful missing-API RED: `build/test-logs/p16q-checkpoint/red`.
Expanded semantic RED: `build/test-logs/p16q-checkpoint/expanded-red` and
`build/test-logs/p16q-checkpoint/expanded-domain`.
Final five-case GREEN: `build/test-logs/p16q-checkpoint/complete-safe-green`.
One scene passed, zero failed, zero known leak warnings. Log scans found no
script errors; the macOS certificate lookup warning is existing environment
noise. Godot 4.6.1 does not expose line coverage in this runtime, so no coverage
percentage is claimed.

Seven targeted regression scenes also passed with zero known leak warnings:
`meta_host_launch`, `profile_runtime_service`, `room_runtime`,
`encounter_runner`, `room_scene_host`, `run_floor_plan_state` and
`native_training_flow`. Their retained logs are the corresponding
`build/test-logs/p16q-checkpoint/regression-*` directories. Scans found no
script errors or leak diagnostics. `git diff --check` passed.

The persisted primary proves actual Base provenance:

- Pack: `35b38b70f84c80df5433475c385344b5206eb9922164f8a7aa82277baaca18f7`.
- Aggregate: `897d72f310a123362093fcd27d31eac692689ab0a1583177d3d807abf6407a49`.
- Source: final test user-data `p16q-checkpoint/profiles/checkpoint_entrance/base/primary.json`,
  captured by ContentSnapshotProvider from the actual Host registry.

## Atomic Profile Synchronization

Ordinary native Run retention now refreshes the complete checkpoint in the same
physical write as its canonical Run and reward state. Tutorial and narrative
Profile writes use the bound actual Host. A narrative health effect captures
its validated native target silently, proves exact Player Replay and Run
preimage restoration before saving, then publishes and verifies the complete
checkpoint. Callback drift reports publication pending and blocks further
Profile commands. Unsupported live combat still refuses a checkpoint update.

An explicit abandonment atomically clears the resumable checkpoint while
retaining its terminal Run and settlement receipt. A physical reopened Profile
cannot resume or settle that launch twice. The native suite now has six cases,
including abandonment, Player movement synchronization, and a failed ordinary
retention before primary promotion preserving the complete native preimage.

Meaningful synchronization RED: `build/test-logs/p16q-checkpoint/synchronization-red`.
Meaningful abandonment RED: `build/test-logs/p16q-checkpoint/abandon-red`.
Six-case GREEN: `build/test-logs/p16q-checkpoint/sync-final-guarded`.
Profile, native narrative, tutorial and actual Main tutorial cold resumption
also passed in `sync-profile`, `sync-narrative`, `sync-tutorial` and
`sync-main-resume` under the same checkpoint log root. Every scene passed with
zero known leak warnings and scans found no script errors or leak diagnostics.

The same suite verifies a single-use authenticated first-presentation callback.
It pauses the native participants without cancelling saved weapon/time actions
or the actual restored rift; a second call is refused. A fifth-floor cold
restoration also installs authenticated reward state before full Replay
preflight so earned resource maxima are available to all native participants.

The six-case GREEN physical primary proves the newer reviewed Base binding:

- Pack: `5410744506218905c156ee9a1ca868a1baa6bf16130602875e8d29aa3d3bbe0a`.
- Aggregate: `d484655161da5bbfddd7fd3fc82afd54b363fc0609020c2070eac7a885fde074`.
- Source: `abandon-green-stable/user-data/tests__integration__save__native_run_checkpoint_test/files/p16q-checkpoint/profiles/checkpoint_entrance/base/primary.json`.

The fingerprints above supplement the original safe milestone evidence; they
were captured from actual activated content rather than supplied fixture pins.

## Current Limits

Active combat, enemy actors, pending waves and encounter timers remain refused.
The next milestone must recreate those native participants and prove mid-combat
continuation after actual scene destruction. This delivery is a safe checkpoint
foundation and does not claim full-product completion.

The Player installation transaction starts from a fresh native standalone Player
with an empty original World. It preserves accepted production loadout generation
and uses existing Replay participant contracts. Arbitrary mutations inside
caller-provided preparation adapters before the installation transaction begins
are not covered by the compensation evidence.
