# P22B Replay Library

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Replay presentation boundary
- Applies To: Local validated Player recordings and Hub archive entry
- Owner: Project integration lead
- Depends On: `2026-10-05-p22a-player-replay-archive-design.md`, `../../../AGENTS.md`
- Last Verified: 2026-10-05

## Design

Use the existing physical PlayerReplayArchive and isolated PlayerReplayWorld.
A dedicated coordinator projects a local library and creates a fresh admitted
Player for each selection. Reconstruct only validated recorded identity inside
that world, including native generation and initial Meta stats. Live Players
cannot use this reconstruction API. Catalog profiles and mobility must match.
Imported recordings cannot replace the content binding or grant progression.

The viewer displays exact validated frame snapshots at 60 recorded frames per
second, with pause, seek and 0.5/1/2 playback speed. Snapshot viewing does not
claim hostile simulation or verified input execution. The private World2D and
typed bus remain the isolation authority; camera framing follows the recorded
Player, and the native sprite and recorded weapon payloads render there.

World payload history may move backward only while the exact admitted Player
remains disabled in the private ReplayWorld, without a hostile participant or
physics processing. Live, shared-world and reparented Players retain production
history checks. Full replay validates and restores reward-owned and other Health
protection as one consistent target pair; ordinary reward restoration preserves
the live protection boundary. Differing token ceilings and overlapping target
token sets refuse before mutation.

Use the existing modal/focus/accessibility conventions for list, empty state,
selection, compatibility errors, import, export and explicit deletion. Import
is bounded before reading a file. Export writes only an application-owned
directory and reports a path; imported IDs never form arbitrary paths. File
dialogs close with the viewer. Hub travel is disabled while the viewer is open,
and returning restores the Hub focus. Content activation must close and replace
the coordinator so stale bindings cannot enter another save domain.

## Completion Criteria

Actual Godot integration tests must first fail for the missing library. They
then round-trip an actual Player recording through a fresh physical archive,
select and seek the native sprite, exercise timeline pause/speed/end, preserve
live Health and global events, reject malformed or incompatible imports,
export and reload, remove explicitly, and close without leaked actors or focus.
Recorded non-default generation and initial stats reconstruct in the isolated
world; the same command on a live Player refuses. Controller and supported
resolution checks accompany Hub integration and a clean import.

P22B retains P22A's 20-entry/64-MiB limits. Automatic whole-run enemy, room and
economy recording, long-run compression and final replay gameplay certification
remain pending and must not be reported as delivered by this library.
