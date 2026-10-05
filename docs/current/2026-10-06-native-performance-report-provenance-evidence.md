# Native Performance Report Provenance Evidence

- Status: Implemented / Current
- Document Role: Current focused verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native performance report source identity, outer verdict and durable recording status
- Owner: Project integration lead
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-06
- Certification Status: Development verification only; full gameplay, rendered performance and human playtests pending

## Demonstrated Failures

The frozen `54866d4` late-phase run reached recorder backpressure. Its report
asserted `recording.status: INTERRUPTED`, while its final physical manifest
retained the entry as `FAILED`. The Python launcher stopped on the nonzero
process result before adding source identity to the failed report.

Independent review also reproduced three passing native reports followed by
a nonzero process exit, a script error or a changed runtime source. The command
failed, but the retained report still said `pass` and its report validator
accepted it. A timeout before native serialization left no final execution
outcome in the pre-run manifest.

## Repair

The launcher retains the original runtime file SHA-256 map before execution,
then always finalizes the manifest with source stability, process exit code,
timeout and strict log outcome. Existing native reports retain the native
verdict separately. Their overall verdict becomes failed for process, log,
source or report-validation failures. A timeout cannot invent native samples.

Native report serialization now follows Main retirement and audio release.
After the worker joins, a fresh physical manifest reload supplies the actual
recording status by entry ID. Physical first/last equality and all prior
sample, scheduling, content and no-human/FPS assertions remain required.

## Verification

- The Python failure-source regression was RED with a missing `source` field.
  Seven contract test methods now pass, including independent process, log,
  source-change, timeout and invalid-native-report cases.
- The actual blocked-writer scene was RED because no retained-status API
  existed. Its original bounded queue, continued gameplay and physical FAILED
  assertions now pass with the new report-status assertion. Strict logs are
  `build/performance-evidence-status-red-20261006` and
  `build/performance-evidence-status-green-20261006`.
- A 12-frame development attempt failed the existing observed-actor contract.
  It remains an unsuccessful attempt at
  `build/performance-evidence-source-smoke-20261006`; it is not combat or
  performance certification.
- The completed actual Main first-floor Boss probe retains 120 consecutive
  frames and 121 tape observations in
  `build/performance-evidence-source-boss-smoke-20261006`. Fresh physical
  first/last reads are byte-exact and the durable entry is `INTERRUPTED`.
  Source fingerprint is
  `468f88a7b2796fcb6a3ea1758a39ba9bf7018b34503812a35c39cf9b059cf160`.
  Its Player mean is 9.327 ms and p95 is 13.920 ms, under concurrent validation.
  These short headless samples do not certify rendering, late phases, sustained
  recording, whole-game frame rate or a clean combined checkout.

Both native GREEN runs have clean script-error and object/RID-leak checks.
Godot is `4.6.1.stable.official.14d19694e`. No production gameplay, buffer limit,
replay format or content value changes in this repair.
