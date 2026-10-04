# P16Q Native Checkpoint And Cold Restore

- Status: Approved / Current
- Document Role: Current focused native checkpoint specification under standing project authorization
- Authority Level: Physical Profile persistence and production Host reconstruction below P16
- Applies To: RunRuntimeHost, native checkpoint authority, RoomRuntime and inactive EncounterRunner restoration
- Owner: Project runtime implementation lead
- Depends On: `AGENTS.md`, P16 durable Profile and native launch integration
- Last Verified: 2026-10-05
- Implementation Status: Safe native phases verified; actor/timer combat restore remains current follow-up

A checkpoint is captured from actual Host, Player, Run, RoomRuntime and
RoomSceneHost participants. Availability is derived from canonical Run phase,
an inactive runner, no pending spawns and no live hostile nodes. A caller
cannot provide an availability claim. The first delivery supports launch
entrance, cleared rooms, pending rewards, route selection and terminal scenes.
Mid-combat capture returns `CHECKPOINT_UNSAFE` until the separate actor/timer
lifecycle contract is implemented; this milestone does not claim arbitrary
combat-frame resumption or full-product completion.

The Profile envelope stores canonical Run and reward participants alongside a
strict checkpoint extension. Full Player Replay uses the existing bounded
Replay binary-in-JSON codec, retaining Vector2 values, action/time/rewind
participants, earned talents, event modifiers and World payload lifecycle.
The checkpoint binds the exact launch receipt, frozen projection, Run identity
and revision, room snapshot and scene binding. Extension checksums are
integrity checks, never authority to mint a receipt or change a loadout.

Once a native checkpoint exists, Profile writes that change Run or reward
participants atomically refresh the complete checkpoint from the bound Host.
Tutorial and narrative updates cannot retain an older Player or Run digest.
Projected narrative health effects prove exact native preimage compensation
before the physical write and verify their published target afterward.
Explicit abandonment retires the resumable checkpoint in the same terminal
settlement write. Unsupported combat updates preserve the previous primary
and return an actionable refusal instead of creating an inconsistent save.

Cold restore authenticates the current physical primary against the loaded
Profile before creating a candidate facade. It installs the accepted original
loadout, restores exact Player Replay, stages the authored room scene and
reconstructs an inactive RoomRuntime without entering or clearing the room.
It does not call prepare_launch, settle_terminal, floor entrance recovery,
run_started, room_started or room_cleared. Existing pending offers remain the
same offer and revision and can be consumed once after restoration.

Native reconstruction failures compensate the candidate scene, Player loadout
and Replay to the preimages taken before installation and preserve the physical
primary. This does not promise compensation for arbitrary mutations inside
caller-provided scene preparation adapters before Player installation begins.
Publication is separate
from historical gameplay facts. Detached participants or post-publication
drift freeze the restored runtime and report recovery pending.

Completion requires a real SaveService, physical primary reload, destruction
and recreation of Host/Player/room nodes, pending reward continuation,
terminal handling, save/scene/Player failures, stale primary detection,
tampering and scanned Godot logs. Evidence: `docs/current/2026-10-05-p16q-native-checkpoint-evidence.md`.
