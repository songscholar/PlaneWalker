# P22A Player Replay Archive

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Focused replay storage and viewing boundary
- Applies To: Validated full-player recordings, local archive and sharing envelope
- Owner: Project integration lead
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`, `../../../AGENTS.md`
- Last Verified: 2026-10-05

## Storage And Compatibility

Reuse SaveService in a separate archive slot identified by profile ID, save domain,
game version and actual content snapshot. Ordinary Profile payloads and Meta
settlements remain owned by ProfileRuntimeService. This choice retains physical
pending-write verification, backup rotation and recovery. Separate raw files would
duplicate those contracts; embedding recordings in the ordinary Profile would
inflate every progression write and mix distinct ownership.

An archive package has exact versioned fields, the recorded game/content/domain,
the existing safe ReplayRecorder JSON codec, its digest and a content-derived ID.
Decode with the existing object-disabled codec and validate the entire full-player
recording through ReplayPlayer before storage or exposure. Compatibility requires
the exact game, content and save domain. A valid package is a recording for viewing,
not an authenticated leaderboard score. Recomputing a hash does not confer trust.

Store at most twenty recordings and sixty-four MiB of encoded package data. Each
recording retains the existing sixteen-MiB binary codec ceiling. A full archive
rejects additions explicitly; it never silently erases a recording. Duplicates are
idempotent. Removal is a separate explicit command. Imported IDs never form paths.

## Transactions And Playback

Writes compare the physical primary against the instance's last committed archive,
then use SaveService compare-exchange. A stale instance refuses to overwrite newer
data. Failures retain the prior in-memory archive; a post-promotion failure counts
as committed only after physically verifying the exact candidate. Fresh reloads
exercise backup recovery. A read returns defensive copies.

Seeking restores a validated full-player keyframe into an explicitly bound viewing
target and verifies equality using ReplayPlayer. Playback verifies real fixed-frame
execution and time facts; failed execution restores the target and cursor atomically.
The viewing target is isolated from the live run and cannot publish Meta rewards.

The target must be created by a dedicated ReplayWorld SubViewport with its own
World2D and a private instance of the typed event bus. The session binds both
target and world weakly; moving a globally initialized Player into the viewport
does not grant admission. Player/time/weapon target queries filter by the actual
ReplayWorld ancestor, payload spawning uses that root, and playback observes
the private bus. Production queries exclude replay nodes. A disabled Player in
the ordinary world is insufficient: Stop and seek can otherwise affect live
group members, and playback facts can reach live progression subscribers.

P22A covers the existing contiguous full-player recording format. It does not claim
whole-run hostile/room/economy tape recording, compressed periodic keyframes, or a
forty-five-minute gameplay recording fits the current codec. Those are explicit
later replay tasks under the same full-product scope, alongside automatic native
capture and Hub integration. Their pending status must remain visible in evidence.

## Completion Criteria

Meaningful RED precedes implementation. Real Godot tests create actual launch
Players, record movement and a time ability, round-trip through physical Save and
a fresh archive, import/export without unsafe objects, reject rehashed semantic
forgeries and wrong bindings, exercise pending/promoted write faults and stale
writers, and restore/replay an independent actual Player without touching the source.
Documentation, scene discovery and the clean import/export path accompany code.
