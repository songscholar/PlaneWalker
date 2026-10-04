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

`tests/integration/save/native_run_checkpoint_test.tscn` runs five isolated
physical Profiles against production Main, Host and Player scenes:

- Launch entry retains and restores the same Run, frozen projection and full Replay.
- Cleared elite room restores the actual bound scene and pending reward. The reward
  consumes once and floor routing continues.
- Terminal defeat restores without another launch, settlement or floor entrance.
- A native time rift reconstructs as a new Node, continues its saved deterministic
  World frame clock and expires through the normal payload lifecycle.
- Post-restoration callback drift reports publication pending and freezes both
  Player and RoomController without changing the durable checkpoint.

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
