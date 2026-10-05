# Main Player Lifecycle Evidence

- Status: Focused Verified / Full validation pending
- Document Role: Current focused implementation evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Main Hub dormancy, native Player activation, selection and pause
- Owner: Plane Walker integration team
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## Retained Symptom And Cause

The immutable `bf00573` late-600 report waited 12 Hub frames; the `ee642a7`
late-600 report waited 120. Both admitted Boss phase 2 after 2,501 native
frames and measured frames 2,502-3,101. Their authenticated physical endpoint
comparison retains 54 differences at each endpoint: action and world-payload
revisions differ by 108, and rewind history/sample sequences differ by 18.
These are actual differences, not byte-equivalent endpoints.

`scenes/player/player.tscn` explicitly used `PROCESS_MODE_PAUSABLE`. This
overrode Main's disabled `CombatRoom01` during the Hub and allowed hidden
Player physics to advance. The extra 108 Hub frames explain the revision
offsets; rewind samples every six accepted frames, explaining the 18-sample
offset. Launch resets frame clocks but preserves these monotonic revisions
and sequences. Historical reports and physical comparison artifacts remain
unchanged under `build/retained-checkout/` and
`build/native-leaf-boundary-comparison-20261006/`.

## Executable Repair

The new `tests/integration/ui/main_player_lifecycle_test.tscn` uses a real
Main, authoritative content and persisted unlocked Profile fixture. It visits
all nine Hub functions through the existing production performance probe's
Hub navigation, then waits both 12 and 120 actual physics frames. Complete
Player snapshots, including action, time, world-payload and rewind state,
must retain identical Variant bytes from before the first yield.

The same test launches a real Run and selects an authored encounter. It
requires automatic Player frame advancement, complete-state stability during
route selection and production pause, and automatic advancement after both
selection closure and production resume. It never manually advances Player
frames or resets production counters.

RED at `build/test-evidence/main-player-lifecycle-red/` fails exactly five Hub
dormancy assertions: before the first yield, after the first yield, after
nine-function navigation, and after 12/120 physics waits. Launch, automatic
advancement, selection restoration and pause/resume assertions already pass.

The repair removes only the Player scene's explicit process-mode property,
so it inherits Main's CombatRoom lifecycle. Main already disables the room
in Hub, rejected-launch and terminal paths, and activates it as PAUSABLE for
a Run. Host selection safety still stores and restores the prior Player mode.
The performance probe, runtime counters, reset behavior and log policy are
unchanged.

## Focused Verification

All six focused scenes pass both stdout and independent Godot-log checks under
`build/test-evidence/main-player-lifecycle-green/`: the new lifecycle scene,
two existing Main Hub scenes, meta Host launch, Player fixed-frame authority,
and isolated Player replay world. Seven Python native performance contracts
pass. All three pinned requirements files pass `pip-audit`.

Two separate, uninstrumented real Main probes accept all 120 requested frames,
observe three native actors, retain 121 observations classified INTERRUPTED,
and read back physical first/last samples exactly. The reports are under the
GREEN directory at `probe120-hub12/` and `probe120-hub120/`. Hub waits differ,
but both measured ranges are 1-120 and their complete physical samples match:

| Sample | SHA-256 in both reports |
| --- | --- |
| First | `f5ed675fc861ba689d664c0c8eb0314db4648ac2458eac99d4f31de5c4ce0bf4` |
| Last | `e73c727007f7b5012bd6ece26a2f3c4471ac4c6bb763c1afb113bea7ff62aeca` |

Both source inventories retain runtime digest
`1b12c8ca4d09490ba9aa58e692f4d0767531eedff87f74bd670daa74acf3dfe2`.
The repaired Player scene SHA-256 is
`a78e91da888e249c9bcaee9e295123ca395eeb444d8a1757c19974bda5d03be6`;
the focused scene executes the tracked test and scene sources in this change.
The probe's runtime inventory covers scripts/autoloads, so the scene hash is
recorded explicitly. These probes ran on the dirty scene change atop `10a3e96`,
not an immutable archive of the later commit.

The earlier 12-frame attempts at `probe-hub12/` and `probe-hub120/` remain
failed: all native/recording assertions pass, but the authentic performance
validator rejects zero observed actors before the encounter's spawn warning
finishes. The acceptance threshold was retained; longer runs supply actual
actors instead.

## Retention Boundary

This focused change does not recertify either historical 600-frame report,
long-duration Boss performance, rendered FPS, load/memory, full line coverage
or human playtests. Full integrated clean-checkout validation remains pending.
Production lifecycle behavior intentionally changes the initial counter origin;
future performance comparisons must use identical setup parameters and retain
the authentic new samples without normalizing them to the old Hub clock.
The one-line scene correction is the reversible production decision.
