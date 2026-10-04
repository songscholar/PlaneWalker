# Plane Walker Durable Native Host Startup Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Production Host launch installation and startup publication
- Applies To: RunRuntimeHost, CommandResult, ProfileRuntimeService, and native Main scene startup integration
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16j-native-narrative-retention-evidence.md`, `docs/current/2026-10-05-p16-native-floor-entry-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused production Host startup verified; GameState/Main product entry and full mid-run restoration pending

## Delivered Boundary

The production Host starts Launch/Expansion through the actual Profile service. It validates authored loadout before spending a launch sequence, persists the prepared receipt with frozen progression and complete normalized configuration, and installs the original identity into native RunState and Player. Caller-built launch dictionaries cannot bypass this service ownership.

Entrance recovery runs before the full Run/reward participant checkpoint is saved. Gameplay remains frozen until that checkpoint is durable. Only then does the Host publish run_started and floor_started, returning the final native revision. A failed checkpoint can retry without a second identity, recovery grant, or publication. A native setup failure leaves the original prepared receipt available; a fresh physical Profile service can bootstrap it with the original assistance and progression.

Publication callbacks are checked against the saved Run, actual Player identity/generation/participants, and active receipt before publishing floor_started. Identity drift freezes the Player and reports NATIVE_PUBLICATION_PENDING. A consumed run_started cannot be repeated by retry. NATIVE_PUBLICATION_PENDING and NATIVE_RESTORE_REQUIRED are explicit application result codes.

When the next floor is already prepared but entrance recovery fails, the Host freezes Player/room processing, does not advance gameplay time, and refuses route input. Successful retry consumes that entrance once and restores processing. Duplicate entrance notification leaves health and canonical state unchanged.

## Verification

Meaningful RED: `build/test-logs/p16-meta-host-bootstrap-red` (premature run publication and unfrozen Player after Save failure), and `build/test-logs/p16-meta-host-publication-drift-red` (stale floor publication after actual Player identity drift).

Focused final GREEN: `build/test-logs/p16-meta-host-next-floor-final`, one actual Main scene integration including maximum progression, permanent native Stats, actual Base content fingerprint, physical JSON restore, malformed/forged contexts, repeated launch refusal, pre-promotion failure, same-session retry, cold bootstrap after native setup refusal, publication drift, and next-floor entrance recovery. The next-floor fixture advances canonical room domains directly to isolate the Host entrance boundary; it does not certify physical enemy clearing on that route.

Regression GREEN: `build/test-logs/p16-host-regression` (one production Host scene) and `build/test-logs/p16-host-floor-regression` (one floor lifecycle scene). Final logs contain no script errors or leaks. An earlier inherited-scene test lost its exported room path when replacing the script; restoring that fixture path resolved the diagnostic before final verification.

## Remaining Integration

Main's normal Launch entry has not yet switched to this API. GameState content fingerprint migration, Hub entry, terminal settlement/ending order, and full mid-run restoration remain pending. Retained Run/reward state excludes complete Player position/frame, World payload, physical enemy/room state, and therefore is not a full mid-run resume checkpoint. Bootstrap retry explicitly refuses a retained active-run snapshot that requires native restore. A post-publication integrity failure requires that later complete recovery path rather than replaying consumed notifications.

This evidence is not full P16 or full-product certification, formal export verification, line coverage, or human playtest evidence.
