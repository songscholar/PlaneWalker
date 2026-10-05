# Native Relocation Recoil Evidence

- Status: Focused Verified / Current
- Document Role: Current frozen relocation and native receipt regression evidence
- Authority Level: Approved P15 and project standing authorization
- Applies To: Native relocation under remaining weapon recoil
- Owner: Plane Walker native hostile integration team
- Last Verified: 2026-10-05
- Depends On: `../superpowers/plans/2026-10-05-native-boss-loadout-matrix.md`

## Retained Behavior

Actual Bow, Gun and Gauntlet Void cases reached Void Step with fractional frozen
destinations and remaining weapon recoil. The Actor added recoil displacement
to its relocation. An approximate arrival comparison classified the perturbed
position as landed, while the strict auxiliary receipt correctly refused a
position that differed from the frozen destination.

Native relocation now consumes its frozen displacement without ordinary recoil
addition. Normal movement continues to consume recoil. The existing physical
arrival collision query, room bounds and admission policy remain required; the
change does not grant a landing through blocked geometry.

## Executable Evidence

- Focused semantic RED: `build/test-evidence/native-void-step-recoil-red`,0/1. A real fractional Void Step with finite remaining recoil fails actual frame preparation.
- Focused GREEN: `build/test-evidence/native-void-step-recoil-green`,1/1. The actual body and landing receipt use the exact frozen position, late refusal restores position/recoil/action/receipt/threat, and the same-frame retry owns one landing plus an independently warned followup.
- Existing native temporal Boss regression GREEN: `build/test-evidence/native-relocation-recoil-temporal-regression`,1/1.
- Actual Bow Void GREEN: `build/test-evidence/native-boss-matrix-void-bow-recoil-fixed/native-034-001`,1/1 at3760frames, three actual HP phases, both time casts, physical typed cold checkpoint, exact next frame and authenticated final cleanup.

The focused recoil assignment isolates the regression; it does not substitute a
matrix damage or victory claim. Actual matrix stats remain production values
with the declared survival fixture. All750 native cases and broader P15 gates
remain separate. Successful logs contain no script/parse errors or leaks.
