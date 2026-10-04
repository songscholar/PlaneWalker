# P20A Native Build Sharing Evidence

- Status: Verified Locally / Current
- Document Role: Current build sharing evidence
- Authority Level: Focused native implementation evidence
- Applies To: Portable loadouts, physical Hub import/export and native UI
- Owner: Project integration lead
- Depends On: [P20A design](../superpowers/specs/2026-10-05-plane-walker-p20a-build-sharing-design.md)
- Last Verified: 2026-10-05

## Actual Behavior

Meditation now exports owned saved builds to canonical `PW1` text and imports
codes through the actual ProfileRuntimeService and BuildLibrary. The code stores
only name, character, weapon and two time abilities. All 150 legal combinations
round-trip with deterministic sorting, Unicode names and stable import IDs.
Malformed/checksum/schema/type/extra-field/unknown-ID values refuse. SHA-256
detects transcription errors; the code does not authenticate a sender.

Receiver unlocks and the 32-build capacity remain authoritative. Physical save
failure leaves library, Profile revision, Hub epoch and primary envelope intact.
The same import retries successfully. Identical imported content returns
`NO_CHANGE`, and retired native callbacks cannot import twice. Currency and
progression remain unchanged by sharing.

The actual Main meditation panel includes a selectable code field, export,
import and explicit clipboard commands. Save rejection retains entered text.
The field participates in the controller focus ring and survives locale changes.
Oversized clipboard input refuses before replacing the current code. Clipboard
controls are unavailable on a headless display; manual text import remains usable.

## Verification

- Meaningful RED logs: `p20a-codec-red`, `p20a-hub-share-red`,
  `p20a-native-share-red` under `build/test-logs`.
- Codec: `p20a-codec-green`, one scene and all 150 combinations passed.
- Final physical sharing, Main sharing and visual contracts:
  `p20a-sharing-scroll-green`, three scenes passed, zero failures/leaks.
- Existing Main Hub command, navigation and broad visual regressions:
  `p20a-hub-regression`, three scenes passed, zero failures/leaks.
- Actual Metal-rendered native view:
  `p20a-sharing-visual-scroll-final.godot.log`, passed, eight nonblank PNGs at
  640x360 and 1280x720, English/Chinese, text scale 1.0 and 1.5.
- Actual native clipboard:
  `p20a-sharing-clipboard-final.godot.log`, copy, paste, oversize refusal and
  Main import workflow passed.
- Physical controller D-pad:
  `p20a-share-controller-red` reproduced incorrect focus order;
  `p20a-share-controller-green` passed after aligning the ring with the visible
  name/save/code/import sequence. Down from the code field reaches Import.

The native screenshot exposed a clipped code field at 640x360/Chinese/1.5.
`p20a-sharing-scroll-red` retained this failure. Export now waits for layout
before focusing and ensuring the field is visible; all eight geometry cases
and the updated native rasters passed. Two representative PNGs were inspected.
Final native logs contain no engine/script errors or object/RID leaks.

## Content And Verification Tools

Seven UI translations were added to both authoritative catalogs. The prior Base
descriptor from `f25c218` is retained as
`data/save/compatibility/base_p20_before_build_sharing.json`. The ledger now has
seven bindings/six reviewed transitions and a new exact localization-only edge.
Current Base fingerprint is
`b14fc01a755799d8e546da96a6054397ae6b45ccf2d4f955b2975acbb367dc5d`,
aggregate `cabe0979ad446caf8742ae8fb52aa46d704fb2d77207dc0bce13002be1c808ab`.
Physical compatibility regression `p20a-content-compat` passed.

Localization validation now reads supplemental CSV sources actually configured
in `project.godot`, including the existing content management catalog. It refuses
missing/invalid sources, path escapes and ambiguous runtime keys; unconfigured
files cannot satisfy references. Four new RED contracts passed after the fix;
the full localization module has 12 passing tests and repository validation passes.

Official Godot line coverage remains unsupported. This milestone completes
portable build sharing, not local rankings, full replay productization, challenge
modes or the full-game playthrough certificate.
