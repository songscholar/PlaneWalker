# Native Forest Fractional Root Evidence

- Status: Focused Verified / Current
- Document Role: Current focused native root receipt and cold-state regression
- Authority Level: Approved P15 and project standing authorization
- Applies To: Fractional weapon root destruction and phase retirement
- Owner: Plane Walker native hostile integration team
- Last Verified: 2026-10-05
- Depends On: `../superpowers/plans/2026-10-05-native-boss-loadout-matrix.md`

## Retained Behavior

Actual normal Gauntlet case121 destroyed Forest root1 at799frames. The runtime
correctly deducted each accepted amount from remaining root HP, ending atzero.
The cold validator added those fractional amounts in a different order and
obtained99.99999999999999. Its exact100 check rejected the real broken root and
lost its45-frame exposure provenance on the next native frame.

Cold validation and deterministic surviving-root phase selection now replay
the ordered remaining-HP subtraction used by actual damage acceptance. Each
loss must fit the remaining HP; invented overkill or a false zero-HP claim is
rejected. Root identity, geometry, claim order, exposure and sweep ownership
remain closed contracts. No runtime schema or authored damage value changes.

The existing native root fixture now names its actual principal target rather
than an unauthenticated placeholder. A missing phase receipt produces a semantic
assertion instead of an invalid dictionary-property access.

## Executable Evidence

- Exact fractional receipt sequence RED: `build/test-evidence/native-forest-fractional-root-red`,0/1. Native zeroHP cannot restore and an already-broken root incorrectly consumes a phase retirement slot.
- Root and sweep runtime/native GREEN: `build/test-evidence/native-forest-fractional-root-green`,3/3 for both runtime scenes and native sweep. The separate pre-existing placeholder-target failure is retained in that run.
- Corrected existing root native GREEN: `build/test-evidence/native-forest-fractional-root-existing-green`,1/1, with actual root/trunk Health, compensation, physical geometry, cold migration and terminal retirement.
- Actual Gauntlet Forest GREEN: `build/test-evidence/native-boss-matrix-forest-gauntlets-fractional-fixed/native-121-001`,1/1 at2073frames, both HP phases, actual time pair, physical typed checkpoint, exact continuation and one terminal receipt.

The actual matrix keeps original production values and declares its survival
fixture. These focused results certify the repaired fractional path, not all750
cases, unassisted balance, full P15 or the complete game. Successful logs contain
no script/parse errors or leaks; Godot4.6.1 lacks line-coverage instrumentation.
