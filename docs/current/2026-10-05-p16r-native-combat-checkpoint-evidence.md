# P16R Native Combat Cold Checkpoint Evidence

- Status: Verified Locally / Current
- Document Role: Native active-combat cold restoration and compensation evidence
- Authority Level: Executable evidence below the P16R specification
- Applies To: Actor, encounter, effect, Player, Host and physical Profile restoration
- Owner: Project runtime implementation lead
- Last Verified: 2026-10-05
- Exit Gate: Actual cold continuation and focused regressions pass

## Verified Production Cases

`tests/integration/save/native_combat_checkpoint_test.tscn` destroys production
Main completely, physically reopens its Profile, creates another Main and
reconstructs the same accepted frame. Its eleven cases cover encounter warnings,
fighting, actor warnings, hostile projectiles, projectile-impact pools,
Player-origin burn, semantic zones with native slow status, Boss recovery and
exposure conversion, an authored sleeping-guardian event ambush, restoration
callback drift and first-presentation drift.

Cold Actor and payload instances differ from the originals. Restored Run,
Player Replay, encounter clocks, waves, actor state, effect state and threat
facts equal their retained preimages. The next accepted Player frame equals the
uninterrupted branch. Reconstructed encounters complete through actual hostile
settlement. Callback drift freezes both Player and RoomController without
revising the durable Profile.

Re-signed room, clock, pending-spawn, wave, actor identity, payload/actor fact,
missing fact, dead-roster and Boss Health mutations reject. An actor state that
passes structural validation but fails actual reconstruction preserves the exact
original Player, scene, Runner, hostile binding and physical Profile, then a
retry succeeds. In-flight spawn publication cannot capture a checkpoint.

## Execution Evidence

Final eleven-case GREEN: `build/test-logs/p16r-combat-checkpoint/final-eleven`.
Six further scene regressions passed: `safe-v1-final`, `tutorial-final`,
`profile-final`, `encounter-final`, `event-final` and `actor-final` beneath the
same log root. Every scene reports zero failures and zero known leak warnings.
Scans found no script/parse errors or leaked instances/RIDs. `git diff --check`
passed. Godot 4.6.1 does not supply line coverage, so no coverage percentage is
claimed.

The safe suite physically writes a version-one checkpoint and cold-restores it.
The tutorial suite opens actual Main training, closes its native flow and
reopens current tutorial commands. Tutorial retention now reads the synchronized
Host Run rather than a stale detached Run snapshot. Retiring an already removed
training Player no longer attempts an in-tree runtime reset.

## Boundaries

Invulnerability, prerequisite-room clears and lethal settlement inputs are
explicit fixtures; they do not prove game balance. The semantic-zone fixture
uses a canonical first wave with a chrono guard and real accepted frames rather
than deleting non-target actors outside the frame transaction. The event fixture
checks its actual overlay-selected event definition before saving.

Snapshots retain stable authored identities and portable status-source bindings,
never Nodes or Health transaction tokens. This milestone supersedes P16Q's
active-combat limitation. Historical content migration remains a separate
compatibility authority and must verify actual current reconstruction before
atomic envelope rebinding.
