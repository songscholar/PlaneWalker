# Native Phase Ranger Evidence

- Status: Verified
- Document Role: Current
- Authority Level: Native implementation evidence below approved P15 specification
- Applies To: Phase Ranger species shifts, visible arrival cues and historical checkpoints
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [mechanism plan](../superpowers/plans/2026-10-05-native-hound-phase-mechanisms.md)

## Accepted Mechanism

Current Rangers own a deterministic species clock with the authored 180-frame
cooldown, at-most-80px displacement and 30 vulnerable recovery frames. A
23-frame departure marks one frozen candidate using original CC0 raster art.
The species module reuses the proven Teleporting receipt pattern through
optional parameters; existing affix defaults remain unchanged.

An Actor admits a candidate only inside the authored room, clear of static
collision and actual Player/enemy bodies. It checks that same landing at the
last warning frame and again before commit/publication. New occupancy produces
a BLOCKED receipt and full recovery, with no instant replacement landing.
Late occupancy rejects publication and restores exact position, receipt,
clocks, generation and Health through the ordinary shared frame rollback.

Stop freezes warning progress through its exact control boundary. Rift slows
ordinary movement but does not alter the sealed shift landing. All 30 recovery
frames block attacks and motion while ordinary weapon damage remains effective.
A due shift lets the current projectile action finish and owns the next idle
boundary. Species shifts and a Teleporting affix take turns without duplicated
relocation or a frozen pair of clocks.

## Historical State

Only Ranger domain snapshots advance to schema2. Actor and Driver envelopes,
authored content digests and pack fingerprints stay unchanged. Exact schema1
Ranger snapshots normalize to an explicitly disabled shift, preserving prior
action/control continuation. Floating schemas, extra historical mechanism
fields, noncanonical landing offsets and malformed disabled counters refuse.
Actor normalization participates in the production Driver's exact cold-state
comparison, so a historical aggregate remains restorable.

Raster projections retain only the state they draw. This also fixes Hound
sigils rejecting otherwise valid Rift control changes; normal Hound weapons,
dormancy, rollback and cold behavior remain covered by the dedicated suite.

## Executable Evidence

- `build/native-phase-final-domain`: marked cooldown, Stop/Rift, full recovery, static and Player blocking, late-occupancy rollback/retry, busy action handoff, strict historical continuation and 900 real native frames with Teleporting affix.
- `build/native-phase-retention-profile`: actual seeded Floor4 Host route, physical Profile/SaveService checkpoint, fresh Main exact next-frame continuation, real Sword recovery damage, genuine paid Rewind preserving landing history, production historical Driver reconstruction and accepted next frame.
- `build/native-phase-playback-drain-a`: final physical checkpoint regression additionally confirms all actual MusicDirector playback weak references retire before process exit; 1/1 passed without script errors or leaks.
- `build/native-phase-arrival-visual-retained.log`: native Metal raster and pixel checks at 640x360 and 1280x720; screenshots under `build/visual-evidence/native-enemy-mechanisms/` show the complete Ranger and arrival cue.
- `build/native-phase-teleport-regression`: existing native Teleporting affix suite, 1/1 passed.
- `build/native-phase-complete-enemy`: complete enemy runtime suite, 1/1 passed.
- `build/native-hound-rift-projection`: Hound Rift projection and existing five-weapon, budget, cold, rollback and reform suite, 1/1 passed.
- Existing summon lifecycle, native combat, actual weapon input and domain suites pass. New summon-admission work is certified separately by its owner.

Successful Godot logs are checked for script errors and engine object leaks.
The installed Godot 4.6.1 runtime does not provide GDScript line coverage.
Physical checkpoint tests use fresh user-data directories and cancel their
transient Player actions before teardown. Their bounded weak-reference check
allows AudioServer's independent mix thread to retire stopped WAV playback.

## Reversibility

The species module, Actor hooks and arrival cue are isolated from authored
content. Historical schema1 continuation remains an explicit supported state.
The atlas is reproducible through the retained original-art generator and
CC0 manifest. External publication and full-program certification remain
separate from these focused native mechanism proofs.
