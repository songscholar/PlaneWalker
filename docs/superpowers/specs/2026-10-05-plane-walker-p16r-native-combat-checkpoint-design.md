# P16R Native Combat Cold Checkpoint Specification

- Status: Approved / Current
- Document Role: Current executable native combat checkpoint specification
- Authority Level: Production restoration below standing project authorization
- Applies To: Native encounter driver, hostile actors, Player, Host and Profile persistence
- Owner: Project runtime implementation lead
- Depends On: `AGENTS.md`, `2026-10-05-plane-walker-p16q-native-checkpoint-design.md`, `2026-10-05-plane-walker-p15e-native-event-ambush-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual Main native combat reconstruction and compensation tests pass

Native checkpoints must reconstruct active production encounters after complete
scene destruction. Persistent snapshots must not retain Node instances or
in-process Health transaction capabilities. Existing version-one safe checkpoints
must remain readable.

Completion criteria:

1. A version-two checkpoint authenticates a typed native encounter extension
   against the Run, room, accepted Player frame and activated authored recipe.
2. Native waves, warning clocks, actor birth identities, positions, Health ledgers,
   action/control/status state, pending hostile work, payloads and threat facts
   reconstruct through their actual production owners.
3. Actual Main seed 4 reaches `layer_01_a` and its authored `moth_crossfire`
   encounter. Warning, fighting and actual persistent hostile payload checkpoints
   reopen through a new physical Profile service and new Main/Host/Player nodes.
4. Rebuilt actors and hostile payloads are new native instances. Their accepted
   frame continuation matches the uninterrupted run and eventually settles the
   original encounter once, without replaying spawn publication.
5. Malformed, misbound and re-signed inner state is rejected before publication.
   Failed scene or aggregate reconstruction restores the exact prior Player,
   scene, Runner and durable Profile state.
6. Capture refuses unpublished/in-flight frames and unresolved portable Node
   references. Safe checkpoint, event ambush, native hostile and Profile
   regressions remain green with clean error/leak scans.

Invulnerability and lethal Health fixtures are explicit test setup; they do not
establish combat balance. Native Actor checkpoint APIs are coordinated with the
enemy lifecycle owner to preserve one authoritative state boundary.
