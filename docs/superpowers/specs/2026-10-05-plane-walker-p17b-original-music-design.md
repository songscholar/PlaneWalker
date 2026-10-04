# P17B Original Music Design

- Status: Approved / Current
- Document Role: Current focused production audio specification
- Authority Level: Presentation implementation below full-product scope
- Applies To: Hub, training, five floors, five bosses, terminal screens and credits
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Original assets reproduce, actual Main selects cues, audio loops and pause correctly, and gameplay snapshots stay identical

Fifteen original PCM stereo loops provide distinct Hub, training, credits,
victory, defeat, five exploration and five boss cues. A standard-library Python
score renderer owns compositions, instruments, exact output and provenance.
Every cue has eight bars, audible melodic/harmonic content and headroom. Notes
release before the loop endpoint to avoid clicks. No third-party samples,
credentials, downloads or commercial decisions are required.

MusicDirector owns two AudioStreamPlayers on the existing Music bus. A read-only
context callback from Main chooses cues. The director crossfades uninterrupted
tracks on its own presentation clock, freezes both players and fades during
pause, and stops on exit. The existing accessibility music volume remains the
bus authority. Music cannot change Run, Player, Profile or replay state.

Main projects the Hub/training/credits visibility first, then the active floor,
uncleared boss room or terminal phase. Source cue IDs remain aligned with the
five authoritative Floor definitions. Imported audio resources and the manifest
must load in a real PCK as well as the source project.

The verification gate includes missing implementation RED, exact renderer
reproduction, WAV format/energy/headroom/loop checks, native imported resources,
interrupted crossfades, pause/exit, real Main routing and full Player neutrality.
Automated audio checks prove technical properties; listening feedback remains
part of external player evaluation.
