# Void P3 Dead Player Heal Consumption

- Status: Retained implementation evidence
- Document Role: Current focused P15 correctness retention review
- Authority Level: Below approved P15 specification
- Applies To: Dead Player zero-gain P3 heal consumption, retry and cold restoration
- Owner: Native Boss implementation lead
- Last Verified: 2026-10-05
- Depends On: `../../AGENTS.md`, `../superpowers/plans/2026-10-05-native-void-auxiliary.md`

## Behavior

Entering Void P3 while the Player is dead now consumes the single authored heal
with an actual zero Health gain. The Player remains dead at zero HP. Restoring an
alive Player state later cannot receive a delayed P3 heal. A Player who dies
between preparation and commit also consumes zero. The existing event payload
already includes the alive flag, so no save schema migration is required.

Preparation reserves the same real target and once-only claim as a live heal.
Rollback restores Health and Boss state; retry consumes once. Cold reconstruction
retains the consumed zero receipt instead of rearming the pending heal.

## Verification

- Meaningful domain RED: `build/void-dead-heal-red` rejected dead-zero consumption
  and allowed a delayed heal after revival.
- Domain GREEN: `build/void-dead-heal-green`, 1/1.
- Actual native rollback, retry, later revival and fresh SubViewport cold restore:
  `build/void-dead-native-green2`, 1/1.
- Existing native and domain arena regressions:
  `build/void-arena-dead-regression2`, 2/2.
- Logs scanned for script errors, engine errors, warnings and leaks.

## Remaining Work

Void auxiliary Step, burst, status, pull and pickup mechanisms continue under the
Active `2026-10-05-native-void-auxiliary.md` plan. This focused repair does not
certify the complete P15 program.
